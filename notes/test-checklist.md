# Phone test checklist

Run this on the phone against the APK in release
[v1](https://github.com/nahalewski/3DSEmu/releases/tag/v1). Write the build's commit next to
each result. Send failures to the owner shown, with the build's commit,
what you did and what happened (a screenshot or logcat if you have one).

Owners:
- **UI**: Recomp, session_01B82yRgmRopEVZPmBZUARQa (drawing, layout,
  shapes, sounds);
- **Azahar**: session_013PNMyX83779nhA9vKnmhc8 (3DS, the app shell);
- **melonDS**: session_01TGEiGGaHmMjnngCJ3pdPpr (DS, and Virtual Console
  GB / GBC / GBA);
- **romdb**: session_01DaUwbkJDZHPgGCgPAnNbtS (game names, CI checks).

Last green build: `12b1010` (run 9). Result: `-` = not run yet.

| # | Check | Owner | Build | Result |
|---|---|---|---|---|
| 1 | Cold start: boot animation, then Health & Safety, then HOME | UI | | - |
| 2 | HOME grid shows 3DS, DS, GB, GBC and GBA tiles and the recomp Pokémon games | UI + each emulator's owner for its tiles | | - |
| 3 | Tiles show proper names and box art or cartridges (No-Intro names) | melonDS (DS/VC), Azahar (3DS), romdb (name data) | | - |
| 4 | The Azahar folder opens, and each settings page and tool in it opens and comes back with Back | Azahar | | - |
| 5 | The melonDS and Virtual Console folders open, and their settings pages save | melonDS (data), UI (pages) | | - |
| 6 | A 3DS game launches in Azahar and returns to HOME | Azahar | | - |
| 7 | A DS game runs on both screens, and touch on the bottom screen hits the right spot | melonDS | | - |
| 8 | A GB game in full screen, then native, via the C-stick | melonDS (running), UI (shapes) | | - |
| 9 | A GBC game in full screen, then native, via the C-stick | melonDS (running), UI (shapes) | | - |
| 10 | A GBA game in full screen, then native, via the C-stick; L and R work | melonDS (running), UI (shapes) | | - |
| 11 | A recomp Pokémon game runs natively in full screen; HOME returns to the menu | UI | | - |
| 12 | In-game saves survive quitting and a force-stop (3DS, DS, GB/GBC/GBA, recomp) | owner of that system | | - |
| 13 | Save states: save, load and survive a restart (DS, VC) | melonDS | | - |
| 14 | Download Play sends a game to a second phone, and it starts there with its save | Azahar (files), UI (screens) | | - |
| 15 | Folding: closed = cover screen; open = back to where you were | UI | | - |

## Failures

Most recent first: date, build, check #, what happened, who was told.

(none yet)
