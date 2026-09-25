# gen1recomp Fold

## 3DS Fold: Azahar with the 3DS HOME menu (`build.sh`)

One app that is both things at once: [Azahar](https://github.com/azahar-emu/azahar),
the 3DS emulator, is the base Android app, and it opens on this repo's 3DS
HOME menu (the fold3ds layer on gen1recomp, described below).  The HOME menu
is unchanged: same shell, top screen, applet bar, icon grid, play
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
  The icons are in `fold3ds/icons3ds/` (`az_<page>.png`,
  `azahar.png` for the folder), drawn by `tools/make_azahar_icons.py`.
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

    build.sh                 apply.sh --package-only, then Azahar at a pinned commit + azahar/, builds
    fold3ds/azahar.lua       reads Azahar's library, opens Azahar (love.system.openURL)
    fold3ds/home3ds.lua      + 3DS game tiles and the Azahar folder
    fold3ds/init.lua         + the top screen for them; the 3DS skin as the only skin
    fold3ds/icons3ds/        the Azahar folder's icons (tools/make_azahar_icons.py draws them)
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
`AZAHAR_COMMIT` picks another Azahar commit.  (`build-apk.yml` still builds
the gen1recomp-only APK with `apply.sh`.)

Desktop testing of the HOME menu works as below.  `POKEPORT_FOLD_FAKEAZAHAR=1` adds
three made-up 3DS games to the grid.

## gen1recomp Fold on its own (`apply.sh`)

gen1recomp on a foldable phone, as a 3DS.  This is upstream
[gen1recomp](https://github.com/bryanthaboi/gen1recomp)'s own Android app
(LÖVE 11.5, its launcher, its game engine, its mods) plus one layer,
`fold3ds/`, that plugs into the engine's display and input seams.  `apply.sh` clones upstream at a pinned commit,
drops `fold3ds/` in, applies `patches/` (the launcher's compact
bottom-screen layout, active only on the fold), appends one line to
`main.lua`, adds the folder to the packaged `game.love`, and runs
upstream's own Android build script.

## What it does

* **Open (inner screen)**: the 3DS, on a pale blue-white wallpaper.  The top shell's screen shows the game
  (or, in the launcher, the selected game's cartridge with arrows that
  change the game and a tap on the cart that plays it); the bottom shell's screen
  shows upstream's launcher with all its menus (GAMES, MODS, FIND, ONLINE,
  SKINS, IMPORT, settings) or, in game, the game's Pokémon animated
  (Yellow's Pikachu surfs).  Touch inside either screen reaches the
  launcher or the game as if that screen were the whole window.
* **Top screen shapes (in game)**: a tap on the C-stick above X cycles
  GAME BOY COLOR (the 10:9 screen at a whole pixel scale), WIDESCREEN (the
  whole screen opening) and FULL SCREEN (the whole top panel, over the
  Game Boy Color frame).  The choice is remembered.
* **L / ZL / R / ZR**: L over ZL at the middle of the left edge, R over
  ZR at the right, beside the hinge.  They fade out when nothing touches
  that edge and come back at a touch.  In game L / R are the GBA's L / R
  (FireRed / LeafGreen) and ZL / ZR slow the game down / speed it up; in
  the launcher L / R change tabs and ZL / ZR fast-scroll; on the 3DS HOME
  menu L / R scroll the icons and ZL / ZR change their size.  Settings >
  3DS Shell turns them off.
* **Menus on the bottom screen**: START's menu (and everything opened
  from it) and the mod manager draw on the bottom screen while the world
  stays on the top.  SELECT in the overworld opens the mod manager; SELECT
  again closes it.
* **Bottom-screen launcher**: no wordmark and no cartridge (the cartridge
  is on the top screen); the GAMES / MODS / FIND / ONLINE / SKINS / IMPORT
  strip scrolls sideways by dragging; the header stays put while the page
  under it scrolls with the up / down arrows at the screen's right edge or
  the D-pad's up / down (hold to repeat).  The circle pad and the D-pad's
  left / right move the focus.  Settings is its own screen, and carries
  the app updater, the patch notes, Troubleshooting and the BOIS CLUB
  GAMES mark that used to sit under every page.
* **SKINS (fold)**: a *THEME* card switches the bottom screen between
  *Classic* and *3DS*.  The 3DS theme turns the bottom screen into the 3DS HOME
  menu: the applet bar (Settings, Mods, Find, Online, Skins, Import, Save
  Sync, Exit) with the two icon-size buttons, the icon grid (every game)
  filling down then across on a strip you swipe or flick sideways, the
  name bubble over the selected icon at one row, the play meter (the
  blue bar fills with time in the app; every 12 hours full pays a coin,
  up to 99999) and Manual / Open.  Five
  sizes, 1 row of 4 across to 5 rows of 9 across (size buttons, a pinch,
  or X / Y), and every change animates the icons from their old slots to
  their new ones.  Hold an icon until it lifts to drag it somewhere else;
  size and order are remembered.  Tap to select, tap again or A to open;
  Manual opens a game's manage page.  An opened icon shows its page
  (light theme: white panels, HOME-menu blue selection) under a back bar;
  back, B or HOME returns to the menu.  The top screen is the 3DS's
  too: the status bar (signal, Internet, the play coins, date and time,
  battery), the tiled wallpaper with the selected game's cartridge
  floating over it -- a solid 3D Game Boy Color cart (GBA cart for
  FireRed / LeafGreen) in the game's shell colour with its label on the
  front, bobbing and swaying over a soft shadow and spinning in when you
  pick another game (your own label art: `fold3ds/labels/<version>.png`)
  -- and the game's name; tapping it
  plays a ready game.  Tile icons come from
  `fold3ds/icons3ds/<id>.png`, with stand-ins until they exist.  And a *COVER STICKERS* card puts
  pictures of your own on the closed lid, as many as you like, stacked
  newest on top.  The editor crops a picture (drag the frame or its
  corners), rounds its corners, sizes it, keeps or drops its white edge
  and turns it freely (the knob above it on the cover preview, the Turn
  buttons, or L / R); drag it on the preview to place it.  On the cover
  screen a sticker peels: drag it and its nearest corner folds back to its
  white backing; peel it far enough and it comes off in your finger (a
  second finger twists it), and letting go sticks it down there, on top.
  Every re-stick leaves its corner lifted a little more and starts it
  wearing with play time -- sooner the more it has been re-stuck -- until
  it falls off; a sticker never peeled stays on for good.  Fallen stickers
  wait in SKINS (*Put the fallen ones back*).  Stickers keep their
  proportions, stay on the lid's flat face and are cut to the shell's
  shape.
* **Download Play (3DS theme)**: the orange icon on the applet bar.
  Picking it (d-pad) shows its banner turning in 3D under the top screen's
  panel, as the 3DS does.  *Send a game* packs a game's saves
  (`saves/<game>/`, `save_<game>.lua` and backups) and, if asked, the
  installed mods; *Receive a game* finds phones that are sending, lists
  them, and receives with a progress bar and the link speed; *Install*
  (tap twice) unpacks it, moving every file it replaces into
  `downloadplay/backup_<time>/`.  The ROM and the data extracted from it
  never travel: each phone imports its own.  The transfer is Google's
  Nearby Connections (`android/FoldPlay.java`): the phones find each other
  over Bluetooth and the files move over Wi-Fi Direct / Wi-Fi whenever
  that is faster.  Android asks for Nearby devices permission the first
  time.  `POKEPORT_FOLD_FAKEDP=1` stands in for a second phone on a
  desktop.
* **L / R on the HOME menu**: the L-camera and camera-R buttons sit in
  the top screen's lower corners (3DS theme); L, R or a tap on either
  opens the Camera, as on the 3DS.  (ZL / ZR still resize the icons.)
* **Steps**: the 3DS theme's top screen status bar shows today's steps
  in the 3DS pedometer's grey pill (footprints, "8692 Steps", the time),
  from the phone's step counter (`FoldBridge` "steps", counted from the
  start of the day, separate from the Pokewalker mod's bridge).  Android
  asks for Physical activity permission once; without it the date shows
  instead.  `POKEPORT_FOLD_FAKESTEPS=<n>` fakes it on a desktop.
* **Volume slider**: the VOL slider on the top half's left edge moves:
  drag it (top loud, bottom off) and it sets the app's volume.  The
  phone's volume keys move it too, without Android's volume popup
  (Settings > 3DS Shell > Volume keys move the 3DS slider).
* **Boot screen**: the first time the menu comes up on the open 3DS, the
  G1R Deluxe logo fills both screens (`fold3ds/boot/top.jpg`,
  `bottom.jpg`, cut to 5:3 and 4:3) with a slow push-in and a light
  sweep, to the lid's click and the 3DS HOME menu's welcome jingle, then
  fades into the menu (3.6 s; a tap or any button skips it).  Unfolding
  the phone later clicks too.
* **Camera (3DS theme)**: the orange camera icon at the front of the
  HOME menu's applet bar opens the 3DS Camera.  The phone's live camera
  picture fills the top screen inside white corner brackets (yellow while
  the self-timer counts down, green as the shutter fires, with a white
  flash and a shutter click).  On the bottom screen: Shoot (or A, L, R),
  Photos, Settings, zoom + / - (or up / down, up to 4x), the rear / front
  camera switch (or X), the filter chip (or left / right), and the modes
  Auto, Video, Multi (four shots half a second apart in one 2x2 picture)
  and Self-Timer (3 s).  Filters, after the 3DS camera's effects and
  lenses (`fold3ds/camfilters.lua`, shaders): Normal, Sepia, Black &
  White, Negative, Posterize, Pinhole, Fisheye, Mosaic, Mirror, Sparkle,
  Sketch -- in the viewfinder, the pictures and the videos.  Video: Shoot
  starts and stops (a red REC timer and red brackets while it runs, up to
  ten minutes), H.264 with the microphone's sound in
  `videos/HNV_0001.mp4`; the album shows videos with a play mark and A
  plays them in the phone's video player from the gallery copy
  (Movies/Gen1Recomp).  Photos shows the
  pictures newest first, ten to a page (swipe or left / right), the chosen
  one big on the top screen, with info and delete (tap the bin twice).
  Settings: camera, shutter sound, grid lines, and whether a copy goes to
  the phone's gallery (Pictures/Gen1Recomp).  Pictures are saved as
  `photos/HNI_0001.png`, ... in the save folder, exactly what the top
  screen shows.  Android asks for camera permission the first time.  The
  camera stops while the phone is folded or the applet is closed.  Native side:
  `android/FoldCamera.java` (Camera2), `android/FoldRecorder.java`
  (MediaCodec H.264 + AAC into MediaMuxer) and
  `patches/android-camera.patch` (`love.system.foldCamera` in liblove:
  YUV to RGBA straight into an ImageData, RGBA to YUV for the encoder;
  the CAMERA and RECORD_AUDIO permissions).
* **Menu sounds**: the 3DS HOME menu's own sound effects
  (`fold3ds/sounds/`, trimmed) on the menus -- tiles, the applet bar,
  resizing, lifting and dropping icons, scrolling, HOME, back, launcher
  buttons, stickers peeling / sticking / falling, the play coin, and a
  chime when the menu first comes up.  Silent in game except HOME and the
  C-stick.  Settings > 3DS Shell > Menu sounds turns them off.
* **Mods**: MODS has a *Download mods* button that opens FIND on the
  community catalog (gen1recomp.com/mod, the
  `bryanthaboi/gen1recomp-mod-index` feed): every listed mod, voxel ones
  included, downloads from its author's GitHub release, and MODS' update
  check keeps them current.  *Import* still installs a mod .zip.  The
  catalog as of the build ships in the APK (`fold3ds/modindex/`, refreshed
  by `apply.sh`) so the list is there before the first live fetch; no mod
  itself is bundled.
* **Shell buttons**: the drawn A, B, X, Y, D-pad, stick, START, SELECT and
  HOME press real input.  In game they are the Game Boy buttons (X and Y
  are R and L for FireRed / LeafGreen); HOME returns to the launcher.  In
  the launcher they drive its controller navigation (D-pad moves the
  focus, A activates, B backs out, Y switches to the pointer cursor,
  START / SELECT as upstream maps them).
* **Closed (cover screen)**: the closed lid, on a black wallpaper, fills the screen, whole,
  turned on its side on a portrait cover.  Opening the phone returns to
  the 3DS.
* The app locks landscape so the hinge runs across the middle; the game's
  own touch overlay is switched off because the shell replaces it.

## Build

    ./apply.sh                    # debug APK, app id com.nahalewski.gen1recompfold
    ./apply.sh --release          # with upstream's signing variables set

Needs the Android SDK (platform 36, build-tools 36, NDK 25.2.9519653) and
a JDK; see upstream's `mobile/ANDROID.md`.

GitHub Actions builds it too (`.github/workflows/build-apk.yml`): every push
to `main`, and every 12 hours, attaches the APK to a GitHub Release.  It is signed with
`ci/debug.keystore`, a fixed debug key, so each build installs over the last.

## Desktop testing

With LÖVE 11.5 installed, from the prepared tree
(`build/gen1recomp`):

    POKEPORT_FOLD=ds  POKEPORT_FOLD_SIZE=1076x1038 love .   # the opened 3DS
    POKEPORT_FOLD=lid POKEPORT_FOLD_SIZE=2424x1080 love .   # the cover screen

`POKEPORT_FOLD_TEST` runs `fold3ds/dev/driver.lua` (not shipped): a
script of `frame:action:arg` items separated by `;`, for example
`40:touch:422,714;70:shot:/tmp/a.png;100:quit`.  `POKEPORT_FOLD_FAKECAM=1`
gives the Camera applet a moving test picture.

## Credits

Based on the Pokémon Gen 1 Recompilation Project by BOIS CLUB GAMES, LLC
(https://github.com/bryanthaboi/gen1recomp).  3DS shell art supplied by
the port's author.  Idle animations from the Generation V sprites in
github.com/PokeAPI/sprites.  Ported by nahalewski.
