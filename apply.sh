#!/usr/bin/env bash
# Builds the G1R Fold APK: upstream gen1recomp's own Android app plus the
# fold3ds layer.  Needs the Android SDK (API 36, build-tools 36, NDK
# 25.2.9519653), a JDK, git and python3.  Output: build/gen1recomp/dist/android/debug/*.apk
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM_COMMIT="${UPSTREAM_COMMIT:-c8b64177f60f94d8e052445f36fbd09550e73c48}"
mkdir -p "$HERE/build"
if [ ! -d "$HERE/build/gen1recomp/.git" ]; then
  git clone https://github.com/bryanthaboi/gen1recomp.git "$HERE/build/gen1recomp"
fi
cd "$HERE/build/gen1recomp"
git fetch -q origin "$UPSTREAM_COMMIT" 2>/dev/null || true
git checkout -q "$UPSTREAM_COMMIT"
git checkout -q -- main.lua scripts/build_android.sh
# the layer
rm -rf fold3ds && cp -r "$HERE/fold3ds" fold3ds
# hook it into main.lua (last lines) and package it into game.love
printf '\n-- the Android foldable layer (fold3ds/): a 3DS on a foldable, the lid on its cover\npcall(function() require("fold3ds").install() end)\n' >> main.lua
python3 - <<'PY'
import re, pathlib
p = pathlib.Path("scripts/build_android.sh"); s = p.read_text()
s = s.replace("main.lua conf.lua src data assets tools/save-editor \\", "main.lua conf.lua src data assets fold3ds tools/save-editor \\")
s = s.replace("-x 'data/generated/*' -x 'assets/generated/*')", "-x 'data/generated/*' -x 'assets/generated/*' -x 'fold3ds/dev/*')")
p.write_text(s)
PY
export GEN1RECOMP_ANDROID_APPLICATION_ID="${GEN1RECOMP_ANDROID_APPLICATION_ID:-com.nahalewski.gen1recompfold}"
export GEN1RECOMP_ANDROID_APP_NAME="${GEN1RECOMP_ANDROID_APP_NAME:-gen1recomp Fold}"
bash scripts/build_android.sh "$@"
