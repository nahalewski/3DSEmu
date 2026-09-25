#!/usr/bin/env python3
"""The name index the HOME menu's emulators use (fold3ds/emudb/<system>.tsv),
from tools/romdb/romdb.sqlite (No-Intro's DATs):

  gb.tsv, gbc.tsv, gba.tsv   CRC32 of the whole dump <TAB> No-Intro name
  nds.tsv                    the 4-letter game code in the header <TAB> name

A game's No-Intro name is what its box art (libretro-thumbnails) and its
border (The Bezel Project) are filed under; both are fetched on the phone
when needed, never shipped."""
import os, sqlite3, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
db = sqlite3.connect(os.path.join(HERE, "romdb", "romdb.sqlite"))
out = os.path.join(ROOT, "fold3ds", "emudb")
os.makedirs(out, exist_ok=True)
KINDS = ("retail", "aftermarket", "unlicensed")
for plat in ("GB", "GBC", "GBA"):
    rows = db.execute(
        "select r.crc32, g.name from games g join roms r on r.game_id = g.id "
        "where g.platform = ? and g.kind in (?, ?, ?) order by r.crc32", (plat, *KINDS)).fetchall()
    with open(os.path.join(out, plat.lower() + ".tsv"), "w", encoding="utf-8", newline="\n") as f:
        for crc, name in rows:
            if crc:
                f.write(f"{crc.upper()}\t{name}\n")
    print(plat, len(rows))
rows = db.execute("select serial, name, kind from games where platform = 'NDS' and serial is not null "
                  "order by serial, kind != 'retail', name").fetchall()
seen = set()
with open(os.path.join(out, "nds.tsv"), "w", encoding="utf-8", newline="\n") as f:
    for serial, name, kind in rows:
        code = serial.strip().upper()
        if len(code) == 4 and code not in seen:
            seen.add(code)
            f.write(f"{code}\t{name}\n")
print("NDS", len(seen))
