# UI requests for the 3DS UI session

One line per request: date, session, what should appear and which data or function it uses.

2026-09-25, melonDS / SkyEmu session (session_01TGEiGGaHmMjnngCJ3pdPpr): DS and Virtual Console games playing inside the 3DS shell.
  Data: fold3ds/melonds.lua (provider id "melonds") and fold3ds/vc.lua (id "vc"), both on fold3ds/emuprovider.lua over fold3ds/emucore.lua.
  Beyond the emus.lua contract each provider has:
    running() -> the playing tile or nil
    update(dt) -> call every frame
    screen(i) -> Image; 0 top, 1 the DS touch screen; screen.swap already applied
    screenSize(sys) -> GB/GBC 160x144, GBA 240x160, DS 256x192 per screen; frames arrive as Images replaced each frame
    press(btn) / release(btn) / releaseAll() -> the shell's names; home toggles the pause menu; zr fast, zl slow; cstick is yours (screen shape)
    touch(phase, u, v) -> u, v 0..1 on the drawn DS touch screen
    menu() -> { open, rows = { {id,label} }, sel }; menuDo(id, { cycleScreen = fn }) -> "closed" when the game closed
    toast() -> text, time
    stop(); boxArt(t); cartSkin(t) -> { shape = "ds"|"gb"|"gba", cart = true, color, labelImage, noLabel, cacheKey }
    borderName(t) -> the No-Intro name (per-game border)
    page() -> { title, rows = { {key,label,value,choices={{value,label}},text=maxlen} | {action,label,sub} | {info,label} } }
      while a folder icon's page is open; setSetting(key, value), act(action), closePage()
    message() -> a one-shot message (e.g. "Copy your games into ...")
  Tiles: t.system is "nds" | "gb" | "gbc" | "gba".
  Folder icons to draw (fold3ds/icons3ds/<id>.png):
    melonds (folder: Omnindo, DS settings and tools), nds_screen, nds_profile, nds_system, nds_audio, nds_controls, nds_folder, nds_about, nds_setup, nds_add;
    vc (folder: Virtual Console), vc_screen, vc_system, vc_audio, vc_controls, vc_folder, vc_about, vc_add.
  Drafts to adopt or discard: notes/emu-ui-draft/ -- borders.lua (+ borders/gb.png, gba.png, CC-BY 4.0 libretro common-overlays), cart3d.diff (DS card), init-borders.diff (the game over TOP.full inside its system's border; BORDER / FULL SCREEN).
