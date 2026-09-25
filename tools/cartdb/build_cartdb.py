#!/usr/bin/env python3
"""Build `cartdb.sqlite`: cartridge artwork for every game, all six systems.

    python3 build_cartdb.py            # uses cache/Metadata.zip, downloads if absent
    python3 build_cartdb.py --coverage # just re-print the numbers from the built db

The 3DS theme's top screen floats a 3D cartridge for the selected game with that
game's label on its front (`fold3ds/cart3d.lua`, labels from
`fold3ds/labels/<version>.png`). Today there are eight hand-named Pokemon
labels. This builds the database behind all of them, for GB, GBC, GBA, DS, 3DS
and Switch.

It holds URLs and metadata, never image bytes -- same rule as `tools/romdb`,
whose game list it joins against.

WHAT THE SOURCES ACTUALLY ARE (probed, 2026-09-25, not assumed):

  LaunchBox Games Database -- `Metadata.zip`, 107 MB, reachable from Ben's PC.
    Covers all six platforms and is the ONLY source of cart art for GB, GBC and
    GBA. Image types `Cart - Front`, `Cart - Back`, `Cart - 3D`. Keyed by game
    name, so it needs title matching.

  GameTDB -- `art.gametdb.com/<plat>/cart/<region>/<code>.png`, keyed by the
    4-character serial romdb already stores. **DS only.** The team plan says
    "GameTDB carts already used for 3DS"; that is not so --
    `3ds/cart/US/ECLP.png` is 404 and only `box` exists for 3DS. The old
    `fetch-cartridges.yml` looped over every art kind and logged what landed, so
    the intent was there and the carts never were. GameTDB also throttles: it
    starts returning `SSL: UNEXPECTED_EOF` after a burst, so a probe that treats
    any exception as "no art" UNDERSTATES coverage. `probe_gametdb.py` keeps 404
    and "could not tell" apart for that reason.

  Switch is absent from `tools/romdb` entirely -- the No-Intro DATs libretro
    mirrors do not include it -- and `art.gametdb.com/switch/` does not exist.
    So for Switch, LaunchBox is both the game list and the art.
"""
import argparse
import collections
import io
import os
import re
import sqlite3
import sys
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")
ZIP = os.path.join(CACHE, "Metadata.zip")
ROMDB = os.path.join(HERE, "..", "romdb", "romdb.sqlite")
OUT = os.path.join(HERE, "cartdb.sqlite")
METADATA_URL = "https://gamesdb.launchbox-app.com/Metadata.zip"
IMAGE_BASE = "https://images.launchbox-app.com/"
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36"}

# LaunchBox platform name -> romdb platform code. SWITCH has no romdb side.
PLATFORMS = {
    "Nintendo Game Boy": "GB",
    "Nintendo Game Boy Color": "GBC",
    "Nintendo Game Boy Advance": "GBA",
    "Nintendo DS": "NDS",
    "Nintendo 3DS": "3DS",
    "Nintendo Switch": "SWITCH",
}
SYSTEMS = ("GB", "GBC", "GBA", "NDS", "3DS", "SWITCH")

# What the cart renderer can use, and how much to trust it.
#
# `Fanart - Cart - Front` is NOT a nice-to-have: surveyed over the real file, it
# holds 597 GBC fronts against the official 335, and 658 GB against 701. GBC is
# both the worst-covered system and the one with a working 3D model, so ignoring
# fanart there throws away most of the art that exists. It is tagged `fanart` and
# ranked below official so a consumer can prefer official and fall back, and so
# nobody reads a fanart label as a scan of the real cartridge.
#
# `Cart - Back` is 0 to 3 images PER PLATFORM -- it effectively does not exist
# anywhere. The plan wants models "front and back"; the backs have to come from
# Photography Dev's reference photos, not from a database.
CART_KINDS = {
    "Cart - Front": ("front", "official"),
    "Cart - Back": ("back", "official"),
    "Cart - 3D": ("3d", "official"),
    "Fanart - Cart - Front": ("front", "fanart"),
    "Fanart - Cart - Back": ("back", "fanart"),
}

SCHEMA = """
CREATE TABLE IF NOT EXISTS art (
    platform TEXT NOT NULL,        -- GB, GBC, GBA, NDS, 3DS, SWITCH
    game_id INTEGER,               -- romdb games.id, NULL when unmatched or Switch
    title TEXT NOT NULL,           -- the source's own title
    kind TEXT NOT NULL,            -- front, back, 3d
    quality TEXT NOT NULL,         -- official, fanart
    region TEXT,
    source TEXT NOT NULL,          -- launchbox, gametdb
    source_id TEXT,                -- LaunchBox DatabaseID, or the 4-char serial
    url TEXT NOT NULL,
    PRIMARY KEY (source, source_id, kind, quality, region, url)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS art_platform ON art(platform);
CREATE INDEX IF NOT EXISTS art_game ON art(game_id);
CREATE TABLE IF NOT EXISTS platform_games (
    -- The source's own game count per platform. Needed as the Switch
    -- denominator: romdb does not list Switch, and taking the denominator from
    -- the art table made coverage circular -- it read 99.8% when the real
    -- figure is 526 cart fronts out of LaunchBox's 6,576 Switch games.
    platform TEXT PRIMARY KEY,
    games INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS unmatched (
    platform TEXT NOT NULL,        -- art we have but could not tie to a romdb game
    title TEXT NOT NULL,
    norm TEXT NOT NULL,
    source_id TEXT
);
"""

# ---------------------------------------------------------------- title matching
# GB and GBC are the hard case: romdb has serials for 3 of 1,240 GB games and 31
# of 1,375 GBC, so for those the TITLE is the only join. Everything here is
# reversible and measured -- `--report-unmatched` prints what still misses, and
# each rule below was added because that list showed it.
ROMAN = {"i": "1", "ii": "2", "iii": "3", "iv": "4", "v": "5", "vi": "6", "vii": "7", "viii": "8", "ix": "9", "x": "10"}
ARTICLE = re.compile(r"^(?:the|a|an)\s+")
# No-Intro moves the article to a comma clause and keeps it there even when a
# subtitle follows: `Legend of Zelda, The - Link's Awakening`, where LaunchBox
# writes `The Legend of Zelda: Link's Awakening`. Anchoring this at end-of-string
# -- which is what it did first -- matches only the games with no subtitle, and
# misses every Zelda, Flintstones, Urbz and Fairly OddParents title. It has to
# fire anywhere in the string.
COMMA_ARTICLE = re.compile(r",\s*(?:the|a|an)\b")
# Licensor prefixes one database carries and the other drops: LaunchBox's
# `Disney's Aladdin` against No-Intro's `Aladdin`. Only used for the fallback
# pass, and only when the result is unique on that platform.
LICENSOR = re.compile(r"^(?:walt\s+)?(?:disney|disney s|nickelodeon|nickelodeon s|sega s|konami s"
                      r"|american mcgee s|tom clancy s|sid meier s|disney pixar|disney interactive)\s+")
SUBTITLE = re.compile(r"\s+[-:]\s+|:\s*")


def normalise(title: str) -> str:
    """A title reduced to what two databases can be expected to agree on."""
    t = (title or "").casefold()
    t = t.replace("é", "e").replace("è", "e").replace("ü", "u").replace("ö", "o")
    t = t.replace("&", " and ").replace("+", " plus ")
    t = COMMA_ARTICLE.sub("", t.strip())
    t = ARTICLE.sub("", t)
    t = re.sub(r"\(.*?\)|\[.*?\]", " ", t)          # parenthesised tags
    t = re.sub(r"[^a-z0-9]+", " ", t).strip()
    words = [ROMAN.get(w, w) for w in t.split()]
    # A trailing edition/version word is noise between the two databases.
    while words and words[-1] in ("edition", "version", "the"):
        words.pop()
    return " ".join(words)


def loose(title: str) -> str:
    """The primary title only, for the fallback pass: no subtitle, no licensor.

    `Pokemon Yellow Version` vs `Pokemon Yellow - Special Pikachu Edition`, or
    `Disney's Aladdin` vs `Aladdin`: one database carries a subtitle or a
    licensor the other drops, and no amount of character normalisation closes
    that. Matching on the primary title does -- but only where it is UNIQUE on
    the platform, because `Arcade Classic No. 3` and the annual sports titles
    collapse onto each other otherwise.
    """
    head = SUBTITLE.split((title or "").casefold(), 1)[0]
    head = LICENSOR.sub("", normalise(head))
    return head


def romdb_index(conn):
    """({platform: {norm: game_id}}, {platform: {loose: game_id or None}}).

    The loose index maps a primary title to a game id, or to None when more than
    one game on that platform shares it -- an ambiguous primary title must not
    match anything, or `Arcade Classic No. 3` art lands on `Arcade Classic No. 4`.
    """
    exact = {p: {} for p in SYSTEMS}
    # key -> {normalised title: game_id}. Ambiguity is judged on distinct
    # normalised TITLES, not on game ids: romdb lists every regional release
    # separately, so one game owns several ids, and comparing ids marked almost
    # every title as colliding with itself -- which left only 556 of GBA's 1,392
    # titles usable and made this pass worth 72 matches instead of thousands.
    loose_groups = {p: {} for p in SYSTEMS}
    for gid, platform, title in conn.execute(
        "SELECT id, platform, title FROM games WHERE kind = 'retail'"
    ):
        if platform not in exact:
            continue
        norm = normalise(title)
        # First writer wins, so the lowest id (earliest DAT entry) is kept and a
        # revision or regional duplicate does not displace it.
        exact[platform].setdefault(norm, gid)
        key = loose(title)
        if key:
            loose_groups[platform].setdefault(key, {}).setdefault(norm, gid)
    loose_hits = {}
    for platform in SYSTEMS:
        # One distinct title behind the key: safe. Two or more different games
        # sharing a primary title: refuse to guess, or `Arcade Classic No. 3`
        # art lands on No. 4.
        loose_hits[platform] = {k: next(iter(v.values())) for k, v in loose_groups[platform].items() if len(v) == 1}
    return exact, loose_hits


# ---------------------------------------------------------------- LaunchBox
def download(url, dest, note):
    print("  fetching %s" % note, flush=True)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=900) as r:
        data = r.read()
    open(dest, "wb").write(data)
    print("  %s: %.1f MB" % (note, len(data) / 1e6))


def launchbox_rows(zip_path):
    """(platform, launchbox_id, title, kind, region, url) for every cart image.

    Streamed with `iterparse`, clearing as it goes. `Metadata.zip` is 103 MB but
    the `Metadata.xml` inside it is **499 MB**, and `ET.fromstring` on that
    builds a DOM of several GB before any work starts. The cart images
    themselves are a rounding error, so they are buffered and resolved against
    the game table at the end -- that way the file is read once and it does not
    matter whether `GameImage` entries precede or follow their `Game`.
    """
    z = zipfile.ZipFile(zip_path)
    name = [n for n in z.namelist() if n.lower().endswith("metadata.xml")][0]
    games, pending = {}, []
    with z.open(name) as stream:
        for _event, el in ET.iterparse(stream, events=("end",)):
            if el.tag == "Game":
                platform = PLATFORMS.get(el.findtext("Platform") or "")
                if platform:
                    games[el.findtext("DatabaseID")] = (platform, el.findtext("Name") or "")
            elif el.tag == "GameImage":
                entry = CART_KINDS.get(el.findtext("Type") or "")
                filename = el.findtext("FileName") or ""
                if entry and filename:
                    kind, quality = entry
                    pending.append((el.findtext("DatabaseID"), kind, quality,
                                    el.findtext("Region") or "", filename))
            else:
                continue
            el.clear()          # without this the DOM is retained anyway
    counts = collections.Counter(p for p, _t in games.values())
    print("  LaunchBox games on our six platforms: %d  (%s)"
          % (len(games), ", ".join("%s %d" % (p, counts[p]) for p in SYSTEMS)))
    print("  cart images in the file (all platforms): %d" % len(pending))
    yield ("__counts__", counts)
    for gid, kind, quality, region, filename in pending:
        if gid in games:
            platform, title = games[gid]
            yield platform, gid, title, kind, quality, region, IMAGE_BASE + filename


# ---------------------------------------------------------------- build
def build(args):
    if not os.path.exists(ZIP):
        download(METADATA_URL, ZIP, "LaunchBox Metadata.zip")
    romdb = sqlite3.connect(os.path.realpath(ROMDB))
    index, loose_index = romdb_index(romdb)
    for platform in SYSTEMS:
        if platform != "SWITCH":
            print("  romdb retail titles on %-6s %d exact, %d unambiguous primary titles"
                  % (platform, len(index[platform]), len(loose_index[platform])))

    if os.path.exists(OUT):
        os.remove(OUT)
    out = sqlite3.connect(OUT)
    out.executescript(SCHEMA)

    rows, unmatched, seen_unmatched = [], [], set()
    by_pass = collections.Counter()
    source_counts = {}
    for row in launchbox_rows(ZIP):
        if row[0] == "__counts__":
            source_counts = row[1]
            continue
        platform, gid, title, kind, quality, region, url = row
        norm = normalise(title)
        game_id = None
        if platform != "SWITCH":
            game_id = index[platform].get(norm)
            if game_id is not None:
                by_pass["exact"] += 1
            else:
                game_id = loose_index[platform].get(loose(title))
                if game_id is not None:
                    by_pass["primary title"] += 1
        rows.append((platform, game_id, title, kind, quality, region, "launchbox", gid, url))
        if game_id is None and platform != "SWITCH" and (platform, norm) not in seen_unmatched:
            seen_unmatched.add((platform, norm))
            unmatched.append((platform, title, norm, gid))
    out.executemany("INSERT OR IGNORE INTO art VALUES (?,?,?,?,?,?,?,?,?)", rows)
    out.executemany("INSERT INTO unmatched VALUES (?,?,?,?)", unmatched)
    out.executemany("INSERT OR REPLACE INTO platform_games VALUES (?,?)",
                    [(p, source_counts.get(p, 0)) for p in SYSTEMS])
    out.commit()
    print("  cart images indexed: %d  (art titles with no romdb match: %d)" % (len(rows), len(unmatched)))
    print("  matched by: %s" % ", ".join("%s %d" % kv for kv in by_pass.most_common()))
    coverage(out, romdb)
    return 0


# ---------------------------------------------------------------- coverage
def coverage(out, romdb):
    """Coverage per system as a number, which is what leadership asked for.

    Every column below counts the SAME population -- distinct romdb titles --
    because the first version of this did not, and produced `front` larger than
    `with art` on every row: `with art` counted matched games while `front` fell
    back to the source's own id and so swept in art that matched nothing. Two
    denominators in one table is a wrong report, not a subtle one.

    The denominator is distinct **titles**, not romdb rows. romdb lists each
    regional release separately -- 1,240 GB rows are 971 titles -- and one label
    serves a game's regional copies (the renderer's only regional split is
    `_jp.png`). Counting rows would quietly divide by up to 1.5x too much.
    """
    print("\n%-8s %8s %9s %8s %8s   %s" % ("system", "titles", "official", "+fanart", "backs", "coverage"))
    total_titles = total_any = 0
    for platform in SYSTEMS:
        if platform == "SWITCH":
            # romdb does not list Switch, so LaunchBox's own game count is the
            # population. Counting distinct titles in the ART table instead --
            # which is what this did first -- asks "of the games with art, how
            # many have art", and duly answered 99.8%.
            titles = out.execute(
                "SELECT games FROM platform_games WHERE platform = 'SWITCH'").fetchone()[0]
            key, extra = "title", ""
        else:
            titles = len({normalise(t) for (t,) in romdb.execute(
                "SELECT title FROM games WHERE kind = 'retail' AND platform = ?", (platform,))})
            key, extra = "game_id", " AND game_id IS NOT NULL"
        official = out.execute(
            "SELECT COUNT(DISTINCT %s) FROM art WHERE platform = ? AND kind = 'front' "
            "AND quality = 'official'%s" % (key, extra), (platform,)).fetchone()[0]
        any_front = out.execute(
            "SELECT COUNT(DISTINCT %s) FROM art WHERE platform = ? AND kind = 'front'%s"
            % (key, extra), (platform,)).fetchone()[0]
        backs = out.execute(
            "SELECT COUNT(DISTINCT %s) FROM art WHERE platform = ? AND kind = 'back'%s"
            % (key, extra), (platform,)).fetchone()[0]
        pct = (100.0 * any_front / titles) if titles else 0.0
        print("%-8s %8d %9d %8d %8d   %5.1f%%" % (platform, titles, official, any_front, backs, pct))
        total_titles += titles
        total_any += any_front
    print("%-8s %8d %9s %8d %8s   %5.1f%%" % ("TOTAL", total_titles, "", total_any, "",
                                              100.0 * total_any / max(1, total_titles)))
    unmatched = out.execute("SELECT platform, COUNT(*) FROM unmatched GROUP BY platform").fetchall()
    print("\ntitles   = distinct romdb retail titles; for SWITCH, LaunchBox's own game count.")
    print("official = titles with a `Cart - Front` scan. +fanart adds `Fanart - Cart - Front`,")
    print("           which for GBC is most of the art that exists. coverage is the +fanart figure.")
    print("backs    = titles with ANY back image. It is near zero on every system: there is no")
    print("           back-of-cart source, so model backs need Photography Dev's references.")
    print("art LaunchBox has that matched no romdb title: %s"
          % (", ".join("%s %d" % r for r in unmatched) or "none"))
    print("~88% of those are Japanese-only releases, romhacks and demos -- romdb is")
    print("English-language retail by design, so that gap is intended, not a matching failure.")
    print()
    print("SWITCH's denominator is every game LaunchBox lists, and a large share of those are")
    print("eShop-only titles that never had a cartridge to photograph. 10.1% is therefore a floor,")
    print("not the achievable figure -- narrowing it needs a physical-release list we do not have.")


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--coverage", action="store_true", help="re-print the numbers from the built db")
    ap.add_argument("--report-unmatched", type=int, metavar="N", default=0,
                    help="print N art titles that matched no romdb game, per system")
    args = ap.parse_args(argv[1:])

    if args.coverage or args.report_unmatched:
        if not os.path.exists(OUT):
            print("no cartdb.sqlite yet -- run without --coverage first", file=sys.stderr)
            return 1
        out = sqlite3.connect(OUT)
        romdb = sqlite3.connect(os.path.realpath(ROMDB))
        if args.report_unmatched:
            for platform in SYSTEMS:
                rows = out.execute("SELECT title FROM unmatched WHERE platform = ? LIMIT ?",
                                   (platform, args.report_unmatched)).fetchall()
                if rows:
                    print("\n%s -- art with no romdb match:" % platform)
                    for (title,) in rows:
                        print("   %s   ->   %r" % (title, normalise(title)))
        if args.coverage:
            coverage(out, romdb)
        return 0
    return build(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
