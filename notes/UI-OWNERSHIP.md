# Who changes the UI

The user's rule: **only the 3DS UI session changes the UI.**
That session is session_01B82yRgmRopEVZPmBZUARQa.

## The UI (the 3DS UI session only)

Everything that is drawn, laid out, animated or played as a sound:

- `fold3ds/init.lua`: its drawing, layout, input routing, top-screen
  borders / GBC / WIDESCREEN / FULL SCREEN, boot and startup, volume
  slider, L/R, stickers.
- `fold3ds/home3ds.lua`, `theme3ds.lua`, `cart3d.lua`, `sticker.lua`,
  `camera.lua`, `camfilters.lua`, `eshop.lua`, `activity.lua`,
  `friends.lua`, `notes.lua`, `sfx.lua`, and the drawing half of
  `dlplay.lua`.
- The art and sound folders: `fold3ds/skin`, `icons3ds`, `banners`,
  `homesprites`, `labels`, `carts`, `boot`, `health`, `eshop`, `dlplay`,
  `idle` and `sounds`.
- `patches/launcher-fold.patch` (the launcher's look).

## Everyone else (the Azahar and melonDS / SkyEmu sessions)

These stay yours:

- the emulators and the native side: `azahar/`, `shell/`, `android/*.java`,
  JNI, `build.sh`, the Gradle files and the workflows;
- the data modules' logic: game lists, transfers, `romdb`, and the data
  functions in `fold3ds/azahar.lua`.

When you need something on screen (a new tile, icon, border, banner,
screen or button), don't edit UI files. Ask the UI session:

- make a one-shot Routine (`create_trigger` with
  `persistent_session_id = session_01B82yRgmRopEVZPmBZUARQa`), or
- add a line to `notes/ui-requests.md` on `pixel-fold`.

Say what data or function it should call. The UI session builds it and
replies.

Always merge `origin/pixel-fold` before pushing.
