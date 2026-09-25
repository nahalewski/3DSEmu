#!/usr/bin/env python3
"""Build romdb.sqlite: English-language GB/GBC/GBA/DS/3DS dump metadata.

Source: the No-Intro DAT files mirrored by libretro-database.  These hold
titles, regions, serials, sizes and hashes of known-good dumps; no ROM data
and no download links.  Use verify.py to identify your own dumps against it.

    python3 build_db.py [--dat-dir DIR] [--out romdb.sqlite]

Without --dat-dir the DATs are fetched from GitHub.
"""
import argparse
import os
import re
import sqlite3
import urllib.parse
import urllib.request

DAT_URL = ("https://raw.githubusercontent.com/libretro/libretro-database/"
           "master/metadat/no-intro/{}.dat")

PLATFORMS = {
    "GB": "Nintendo - Game Boy",
    "GBC": "Nintendo - Game Boy Color",
    "GBA": "Nintendo - Game Boy Advance",
    "NDS": "Nintendo - Nintendo DS",
    "3DS": "Nintendo - Nintendo 3DS",
}

# Regions whose releases are English when No-Intro gives no language tag.
ENGLISH_REGIONS = {"USA", "Europe", "World", "United Kingdom", "UK",
                   "Australia", "Canada", "Ireland", "New Zealand"}

LANG_TAG = re.compile(r"^[A-Z][a-z](-[A-Za-z]+)?(,[A-Z][a-z](-[A-Za-z]+)?)*$")
KIND_TAGS = [("beta", r"^Beta"), ("proto", r"^Proto"), ("demo", r"^Demo"),
             ("sample", r"^Sample"), ("kiosk", r"Kiosk"),
             ("unlicensed", r"^Unl$"), ("pirate", r"^Pirate$"),
             ("aftermarket", r"^Aftermarket$")]
REV_TAG = re.compile(r"^(Rev [\w.]+|v[\d.]+\w*)$")

GAME_RE = re.compile(r"^game \($(.*?)^\)$", re.M | re.S)
FIELD_RE = re.compile(r'^\t(name|region|serial) "(.*)"$', re.M)
ROM_RE = re.compile(r"^\trom \( (.*) \)$", re.M)
ROM_FIELD_RE = re.compile(r'(\w+) ("[^"]*"|\S+)')


def load_dat(name, dat_dir):
    if dat_dir:
        with open(os.path.join(dat_dir, name + ".dat"), encoding="utf-8") as f:
            return f.read()
    url = DAT_URL.format(urllib.parse.quote(name))
    with urllib.request.urlopen(url) as r:
        return r.read().decode("utf-8")


def classify(name):
    """Split a No-Intro name into title and tags, and decide if it is English."""
    tags = re.findall(r"\(([^)]*)\)", name)
    title = re.split(r" \(", name, 1)[0].strip()
    regions = [r.strip() for r in tags[0].split(",")] if tags else []
    langs = next((t.split(",") for t in tags[1:] if LANG_TAG.match(t)), None)
    if langs is not None:
        english = any(l.split("-")[0] == "En" for l in langs)
    else:
        english = any(r in ENGLISH_REGIONS for r in regions)
    kind = "retail"
    for k, pat in KIND_TAGS:
        if any(re.search(pat, t) for t in tags):
            kind = k
            break
    revision = next((t for t in tags if REV_TAG.match(t)), None)
    return title, regions, langs, english, kind, revision, tags


def parse(text):
    for m in GAME_RE.finditer(text):
        body = m.group(1)
        fields = dict(FIELD_RE.findall(body))
        roms = []
        for rm in ROM_RE.finditer(body):
            rom = {k: v.strip('"') for k, v in ROM_FIELD_RE.findall(rm.group(1))}
            roms.append(rom)
        yield fields, roms


SCHEMA = """
CREATE TABLE source (platform TEXT PRIMARY KEY, dat_name TEXT, dat_version TEXT);
CREATE TABLE games (
    id INTEGER PRIMARY KEY,
    platform TEXT NOT NULL,      -- GB, GBC, GBA, NDS, 3DS
    name TEXT NOT NULL,          -- full No-Intro name
    title TEXT NOT NULL,         -- name without tags
    regions TEXT,                -- comma separated
    languages TEXT,              -- comma separated, NULL if untagged
    serial TEXT,
    kind TEXT NOT NULL,          -- retail, beta, proto, demo, sample, kiosk, unlicensed, pirate, aftermarket
    revision TEXT,
    tags TEXT                    -- every parenthesised tag, ' | ' separated
);
CREATE TABLE roms (
    game_id INTEGER NOT NULL REFERENCES games(id),
    filename TEXT NOT NULL,
    size INTEGER,
    crc32 TEXT, md5 TEXT, sha1 TEXT
);
CREATE INDEX games_title ON games(title);
CREATE INDEX games_platform ON games(platform);
CREATE INDEX roms_crc ON roms(crc32);
CREATE INDEX roms_md5 ON roms(md5);
CREATE INDEX roms_sha1 ON roms(sha1);
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--dat-dir")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "romdb.sqlite"))
    args = ap.parse_args()

    if os.path.exists(args.out):
        os.remove(args.out)
    db = sqlite3.connect(args.out)
    db.executescript(SCHEMA)

    for platform, dat_name in PLATFORMS.items():
        text = load_dat(dat_name, args.dat_dir)
        version = re.search(r'^\tversion "(.*)"$', text, re.M)
        db.execute("INSERT INTO source VALUES (?,?,?)",
                   (platform, dat_name, version.group(1) if version else None))
        kept = 0
        for fields, roms in parse(text):
            name = fields.get("name", "")
            title, regions, langs, english, kind, revision, tags = classify(name)
            if not english:
                continue
            cur = db.execute(
                "INSERT INTO games (platform,name,title,regions,languages,serial,kind,revision,tags)"
                " VALUES (?,?,?,?,?,?,?,?,?)",
                (platform, name, title, ",".join(regions),
                 ",".join(langs) if langs else None, fields.get("serial"),
                 kind, revision, " | ".join(tags)))
            for rom in roms:
                db.execute("INSERT INTO roms VALUES (?,?,?,?,?,?)",
                           (cur.lastrowid, rom.get("name"),
                            int(rom["size"]) if rom.get("size", "").isdigit() else None,
                            (rom.get("crc") or "").upper() or None,
                            (rom.get("md5") or "").upper() or None,
                            (rom.get("sha1") or "").upper() or None))
            kept += 1
        print(f"{platform}: {kept} English entries")
    db.commit()
    db.execute("VACUUM")
    db.close()
    print("wrote", args.out)


if __name__ == "__main__":
    main()
