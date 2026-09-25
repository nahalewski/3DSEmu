# gen1recomp Fold

## 3DS Fold: Azahar with the 3DS HOME menu (`build.sh`)

One app that is both things at once: [Azahar](https://github.com/azahar-emu/azahar),
the 3DS emulator, is the base Android app, and it opens on the 3DS HOME menu
from [3dsfoldrecomp](https://github.com/nahalewski/3dsfoldrecomp).  The
HOME menu is unchanged: same shell, top screen, applet bar, icon grid, play
coins, camera, stickers, sounds, and the recomp games playing from their
icons on the bottom screen.  Azahar is added to it:

* **3DS games on the HOME menu.**  Every game in Azahar's library (the
  games folder and installed titles) is a tile next to the recomp games,
  with its own icon.  On the top screen it shows as a 3DS game card with
  that icon as its label.  Tap it again, press A or Open, or tap the top
  screen, and Azahar plays it.  Back or Azahar's close-game option return
  to the HOME menu.  Manual opens the game's options in Azahar: cheats,
  shortcuts, the save / DLC / update / mod folders, compress,
  uninstall, and so on.  Tiles can be rearranged and resized like the
  others.
* **The Azahar folder.**  One folder tile holds an icon for each Azahar
  settings page and tool, so the grid stays tidy:
  3DS Library, Emulation Settings (all of them), Graphics, Screen Layout,
  Controls, Sound, System Settings, General, 3DS Camera, Storage, Web
  Service, Debug, Install CIA, Games Folder, System Files, GPU Drivers,
  Multiplayer, Artic Base, Azahar Folder, Share Log, About Azahar.  Open
  the folder and its icons fill the grid, with Close Folder first and the
  folder's name on the play-meter row.  B, HOME or Close Folder closes
  it.  Each icon opens that page directly; Back returns to the folder.
  The icons are in `shell/fold3ds/icons3ds/` (`az_<page>.png`,
  `azahar.png` for the folder), drawn by `shell/tools/make_azahar_icons.py`.
  Replace any PNG to restyle it.
* **The 3DS skin is the only skin.**  The Classic launcher look and the
  THEME card are gone; the bottom screen is always the HOME menu.
* **First run.**  Until Azahar has its folder, a *Set Up 3DS* tile takes
  the grid slot of the 3DS games.  Opening it, or any Azahar icon, runs
  Azahar's own first-time setup (user folder, games folder, permissions).
* **Nothing removed from Azahar.**  Every Azahar screen, setting and
  feature is still there.  They open from the folder instead of from
  Azahar's own home screen, which is no longer a launcher entry.
* Same app id (`com.nahalewski.gen1recompfold`) and signing key
  (`ci/debug.keystore`) as gen1recomp Fold, so it installs over it and
  keeps the recomp saves.  arm64 only.

How it fits together:

    build.sh                 fetches both at pinned commits, applies the layers, builds
    shell/                   the layer on 3dsfoldrecomp (the HOME menu, LÖVE)
      fold3ds/azahar.lua       reads Azahar's library, opens Azahar (love.system.openURL)
      fold3ds/icons3ds/        the Azahar folder's icons
      patches/                 home3ds.lua (3DS tiles, the folder), init.lua (top screen, 3DS skin only)
      tools/                   the icon generator
    azahar/                  the layer on Azahar (Android)
      patches/                 :love module, launcher, app id, three small hooks
      java/.../fold3ds/        Fold3dsBridge (library -> HOME menu), Fold3dsLinkActivity
                               (HOME menu -> Azahar), Fold3dsMain (Azahar's own screens)
      res/                     the link activity's theme, the launcher icon

The HOME menu (`org.love2d.android.GameActivity`) is the launcher.  When it
comes to the front, `Fold3dsBridge` scans Azahar's library (the same scan
Azahar's games list runs) and writes `fold3ds_azahar/games.tsv` plus the
game icons into the LÖVE save folder, where `fold3ds/azahar.lua` reads
them.  Tapping something calls `love.system.openURL("fold3ds-azahar://…")`.
The invisible `Fold3dsLinkActivity` receives it and starts the game, settings
page or tool on top of the menu.

Build:

    ./build.sh               # build/out/*.apk

Needs the Android SDK (platforms 35 and 36, build-tools 36, CMake 3.30.3,
NDK 27.3.13750724 for Azahar and NDK 25.2.9519653 for LÖVE), JDK 17, git
and python3.  GitHub Actions runs it on every push to `pixel-fold`
(`.github/workflows/build-3ds-fold.yml`) and attaches the APK to a Release.
`SHELL_COMMIT` / `AZAHAR_COMMIT` pick other commits of either project.

Desktop testing of the HOME menu works as below (from
`build/3dsfoldrecomp/build/gen1recomp`).  `POKEPORT_FOLD_FAKEAZAHAR=1` adds
three made-up 3DS games to the grid.

## gen1recomp Fold on its own (`apply.sh`)

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

    ./apply.sh                    # debug APK, app id com.nahalewski.gen1recompfold
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
