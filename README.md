# G1R Fold

gen1recomp on a foldable phone, as a 3DS.  This is upstream
[gen1recomp](https://github.com/bryanthaboi/gen1recomp)'s own Android app
(LÖVE 11.5, its launcher, its game engine, its mods) plus one layer,
`fold3ds/`, that plugs into the engine's display and input seams.  No
engine file is edited: `apply.sh` clones upstream at a pinned commit,
drops `fold3ds/` in, appends one line to `main.lua`, adds the folder to
the packaged `game.love`, and runs upstream's own Android build script.

## What it does

* **Open (inner screen)**: the 3DS.  The top shell's screen shows the game
  (or, in the launcher, the selected game's cartridge with arrows that
  change the game and a tap on the cart that plays it); the bottom shell's screen
  shows upstream's launcher with all its menus (GAMES, MODS, FIND, ONLINE,
  SKINS, IMPORT, settings) or, in game, the game's Pokémon animated
  (Yellow's Pikachu surfs).  Touch inside either screen reaches the
  launcher or the game as if that screen were the whole window.
* **Shell buttons**: the drawn A, B, X, Y, D-pad, stick, START, SELECT and
  HOME press real input.  In game they are the Game Boy buttons (X and Y
  are R and L for FireRed / LeafGreen); HOME returns to the launcher.  In
  the launcher they drive its controller navigation (D-pad moves the
  focus, A activates, B backs out, Y switches to the pointer cursor,
  START / SELECT as upstream maps them).
* **Closed (cover screen)**: the closed lid fills the screen, whole,
  turned on its side on a portrait cover.  Opening the phone returns to
  the 3DS.
* The app locks landscape so the hinge runs across the middle; the game's
  own touch overlay is switched off because the shell replaces it.

## Build

    ./apply.sh                    # debug APK, app id com.nahalewski.g1rfold
    ./apply.sh --release          # with upstream's signing variables set

Needs the Android SDK (platform 36, build-tools 36, NDK 25.2.9519653) and
a JDK; see upstream's `mobile/ANDROID.md`.

## Desktop testing

With LÖVE 11.5 installed, from the prepared tree
(`build/gen1recomp`):

    POKEPORT_FOLD=ds  POKEPORT_FOLD_SIZE=1076x1038 love .   # the opened 3DS
    POKEPORT_FOLD=lid POKEPORT_FOLD_SIZE=2424x1080 love .   # the cover screen

`POKEPORT_FOLD_TEST` runs `fold3ds/dev/driver.lua` (not shipped): a
script of `frame:action:arg` items separated by `;`, for example
`40:touch:422,714;70:shot:/tmp/a.png;100:quit`.

## Credits

Based on the Pokémon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC
(https://github.com/bryanthaboi/gen1recomp).  3DS shell art supplied by
the port's author.  Idle animations from the Generation V sprites in
github.com/PokeAPI/sprites.  Ported by nahalewski.
