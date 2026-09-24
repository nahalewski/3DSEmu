# gen1recomp-Fold

The Android foldable build of the gen1recomp console ports: the same
runtime, launcher and 3DS skin as the `psp/` tree of
https://github.com/nahalewski/Data-Monsters, kept here as its own
repository so the app can check this repository's releases for updates.

Build (see README.md, section Android):

    python3 tools/fetch_mods.py mods_extra        # optional: community mods
    ANDROID_SDK=... ANDROID_NDK=... SDL_DIR=... bash ports/android/build.sh

Releases: tag a release (for example `v0.1.1`, matching `VERSION`) and
attach `dist/android/gen1recomp.apk`; the app's GAMES tab compares its
`VERSION` with the latest release tag and opens the release page.

Based on the Pokemon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC
(https://github.com/bryanthaboi/gen1recomp). Ported by nahalewski.
