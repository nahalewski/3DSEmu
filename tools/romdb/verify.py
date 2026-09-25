#!/usr/bin/env python3
"""Identify your own ROM dumps against romdb.sqlite by SHA-1.

    python3 verify.py pokered.gb dumps/*.gba

Prints the matching No-Intro entry for each file, or NO MATCH for a bad or
modified dump (or a non-English release, which the database leaves out).
"""
import hashlib
import os
import sqlite3
import sys

DB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "romdb.sqlite")


def sha1_of(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def main(paths):
    if not paths:
        print(__doc__)
        return 2
    db = sqlite3.connect(DB)
    status = 0
    for path in paths:
        digest = sha1_of(path)
        rows = db.execute(
            "SELECT g.platform, g.name, g.serial, g.kind FROM roms r"
            " JOIN games g ON g.id = r.game_id WHERE r.sha1 = ?", (digest,)).fetchall()
        if rows:
            for platform, name, serial, kind in rows:
                print(f"OK        {path}: [{platform}] {name}"
                      f"{f'  serial {serial}' if serial else ''}{'' if kind == 'retail' else f'  ({kind})'}")
        else:
            print(f"NO MATCH  {path}: sha1 {digest}")
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
