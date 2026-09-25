# Drafts for the 3DS UI session (not wired in)

Written in the melonDS / SkyEmu session before the UI rule, handed over as
drafts: the UI session adopts, changes or drops them.

* `borders.lua` -- the top screen's per-system borders (GB, GBC, GBA, DS)
  inside `TOP.full`, the shell's printed Game Boy Color frame covered.  The
  screen hole of any border is found from its see-through pixels.  A game's
  own border comes from The Bezel Project by its No-Intro name, downloaded
  only when the game starts (`emu_cache/bezels/`); a DS game's is cropped to
  its upper screen.  GBC and DS borders are drawn in code.
* `borders/gb.png` -- libretro common-overlays `ctr/borders/img/gb-integer.png`
  (made for the 3DS top screen); `borders/gba.png` -- `borders/img/gba-4k.png`
  scaled to 1280 x 720.  Both CC-BY 4.0 (github.com/libretro/common-overlays).
* `cart3d.diff` -- a DS card shape for `cart3d.lua` (`skin.shape = "ds"`),
  and `skin.labelImage` / `skin.noLabel` for any game's box art.
* `init-borders.diff` -- `init.lua`: in game the picture covers `TOP.full`,
  in its system's border (BORDER) or as large as fits (FULL SCREEN); the
  recomp versions map to GB / GBC / GBA borders.
