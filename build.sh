#!/usr/bin/env bash
# Builds the 3DS Fold APK: Azahar (the 3DS emulator) as the base Android
# app, with this repo's 3DS HOME menu (gen1recomp, its launcher and the
# fold3ds layer, on LÖVE) as the screen it opens on.
#
#   1. this repo's apply.sh prepares gen1recomp with fold3ds/ and packs
#      game.love (--package-only);
#   2. Azahar at a pinned commit (with its submodules), plus this repo's
#      azahar/ layer (azahar/patches/, the Kotlin bridge, resources), with
#      the prepared love-android module linked in as :love and game.love in
#      its assets;
#   3. Azahar's Gradle build: assembleVanillaRelWithDebInfoLite (optimised,
#      signed with ~/.android/debug.keystore).
#
# Needs the Android SDK (platforms 35 and 36, build-tools 36, CMake 3.30.3,
# NDK 27.3.13750724 for Azahar and NDK 25.2.9519653 for LÖVE), JDK 17, git,
# python3.  Output: build/out/*.apk
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
B="$HERE/build"
AZAHAR_REPO="${AZAHAR_REPO:-https://github.com/azahar-emu/azahar.git}"
AZAHAR_COMMIT="${AZAHAR_COMMIT:-56d99197957f9c89609def36514319d961ce01eb}"
TASK="${FOLD3DS_GRADLE_TASK:-assembleVanillaRelWithDebInfoLite}"
# the HOME menu's own DS and Virtual Console cores (emu/)
MELONDS_REPO="${MELONDS_REPO:-https://github.com/rafaelvcaetano/melonDS-android-lib.git}"
MELONDS_COMMIT="${MELONDS_COMMIT:-431ab4bd0003c4356e25fce89640ae1004579b9b}"
SKYEMU_REPO="${SKYEMU_REPO:-https://github.com/skylersaleh/SkyEmu.git}"
SKYEMU_COMMIT="${SKYEMU_COMMIT:-01516d6798e3652b583e6a366085bb51c43b528d}"

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

# a repository at a pinned commit under build/, back to exactly that commit
# (these are build trees: the layers below are applied to them afresh)
checkout() {
  local url="$1" commit="$2" dir="$3"
  if [ ! -d "$dir/.git" ]; then
    git init -q "$dir"
    git -C "$dir" remote add origin "$url"
  fi
  git -C "$dir" fetch -q --depth 1 origin "$commit"
  git -C "$dir" checkout -q -f "$commit"
  git -C "$dir" reset -q --hard "$commit"
}

mkdir -p "$B"

# ---------------------------------------------------------------- 1. the 3DS HOME menu
say "gen1recomp + fold3ds -> game.love"
"$HERE/apply.sh" --package-only
G="$B/gen1recomp"
LOVE_MODULE="$G/mobile/android/love"
GAME_LOVE="$G/mobile/android/app/src/embed/assets/game.love"
[ -f "$GAME_LOVE" ] || { echo "no game.love at $GAME_LOVE" >&2; exit 1; }

# ---------------------------------------------------------------- 2. Azahar
say "Azahar $AZAHAR_COMMIT"
A="$B/azahar"
checkout "$AZAHAR_REPO" "$AZAHAR_COMMIT" "$A"
git -C "$A" submodule update -q --init --recursive --depth 1 --jobs 8 \
  || git -C "$A" submodule update -q --init --recursive --jobs 8
for p in "$HERE"/azahar/patches/*.patch; do git -C "$A" apply "$p"; done
APP="$A/src/android/app/src/main"
mkdir -p "$APP/java/org/citra/citra_emu/fold3ds" "$APP/assets" "$APP/res/xml"
cp "$HERE"/azahar/java/org/citra/citra_emu/fold3ds/*.kt "$APP/java/org/citra/citra_emu/fold3ds/"
cp -r "$HERE/azahar/res/." "$APP/res/"
# gen1recomp's own app resources that LÖVE's Java reaches by name: the
# launcher art, the game shortcuts' icons, the updater's file provider
GRES="$G/mobile/android/app/src/main/res"
for d in "$GRES"/drawable-*; do
  mkdir -p "$APP/res/$(basename "$d")"
  cp "$d"/*.png "$APP/res/$(basename "$d")/"
done
cp "$GRES/xml/full_update_paths.xml" "$APP/res/xml/"
cp "$GAME_LOVE" "$APP/assets/game.love"
ln -sfn "$LOVE_MODULE" "$A/src/android/love"
# liblove for arm64 only, like the rest of the APK
sed -i "s/abiFilters 'armeabi-v7a', 'arm64-v8a'/abiFilters 'arm64-v8a'/" "$LOVE_MODULE/build.gradle"

# ---------------------------------------------------------------- 2b. emucore
# The HOME menu's own emulators (emu/): the melonDS core for DS games and
# SkyEmu's cores for GB / GBC / GBA, as libemucore.so in a :emucore module
# that the app depends on (fold3ds/emu.lua loads it with LuaJIT's FFI).
say "emucore: melonDS $MELONDS_COMMIT, SkyEmu $SKYEMU_COMMIT"
checkout "$MELONDS_REPO" "$MELONDS_COMMIT" "$B/melonds"
checkout "$SKYEMU_REPO" "$SKYEMU_COMMIT" "$B/skyemu"
EMU="$A/src/android/emucore"
rm -rf "$EMU"
mkdir -p "$EMU/src/main"
cp "$HERE/emu/android/AndroidManifest.xml" "$EMU/src/main/"
sed -e "s|@MELONDS_DIR@|$B/melonds|" -e "s|@SKYEMU_DIR@|$B/skyemu|" \
    -e "s|@SKYEMU_COMMIT@|${SKYEMU_COMMIT:0:7}|" -e "s|@NATIVE_DIR@|$HERE/emu/native|" \
    "$HERE/emu/android/build.gradle.kts" > "$EMU/build.gradle.kts"
grep -q 'include(":emucore")' "$A/src/android/settings.gradle.kts" \
  || printf '\n// fold3ds: the DS and Virtual Console cores (emu/)\ninclude(":emucore")\n' >> "$A/src/android/settings.gradle.kts"
grep -q 'project(":emucore")' "$A/src/android/app/build.gradle.kts" \
  || sed -i 's|    implementation(project(":love"))|&\n    implementation(project(":emucore"))|' "$A/src/android/app/build.gradle.kts"
grep -q 'project(":emucore")' "$A/src/android/app/build.gradle.kts" \
  || { echo "could not add :emucore to Azahar's app" >&2; exit 1; }

# ---------------------------------------------------------------- 3. the APK
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
[ -n "$SDK" ] || { echo "set ANDROID_SDK_ROOT" >&2; exit 1; }
printf 'sdk.dir=%s\n' "$SDK" > "$A/src/android/local.properties"
say "gradle $TASK"
(cd "$A/src/android" && chmod +x gradlew && ./gradlew --no-daemon "$TASK")
mkdir -p "$B/out"
rm -f "$B/out"/*.apk
find "$A/src/android/app/build/outputs/apk" -name '*.apk' -exec cp {} "$B/out/" \;
say "APK:"
ls -lh "$B/out"/*.apk
