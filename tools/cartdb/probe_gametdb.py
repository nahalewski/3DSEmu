#!/usr/bin/env python3
"""Measure GameTDB's DS cart coverage against romdb's own serials.

    python3 probe_gametdb.py --sample 60      # estimate, polite
    python3 probe_gametdb.py --all --into-db  # every code, write hits into cartdb.sqlite

GameTDB keys art by the 4-character game code that `tools/romdb` already stores
as `serial`, so unlike LaunchBox this needs no title matching -- where the art
exists, the join is exact.

**404 and "could not tell" are counted separately, and that is the whole point.**
GameTDB throttles: after a burst it stops answering with `SSL: UNEXPECTED_EOF`
rather than a status code. A probe that treats any exception as "no art" reports
a confident low number that is simply wrong, which is how the first run of this
measurement went. Absent means a 404 from a server that was talking to us.
Anything else is `unknown`, retried, and if it stays unknown it is reported as
unknown rather than folded into either column.

Only DS is worth probing: `3ds/cart/US/ECLP.png` is 404 (only `box` exists for
3DS), `art.gametdb.com/switch/` does not exist, and GameTDB has no GB/GBC/GBA
database at all. The team plan's "GameTDB carts already used for 3DS" does not
hold -- see build_cartdb.py's docstring.
"""
import argparse
import collections
import os
import random
import sqlite3
import ssl
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROMDB = os.path.realpath(os.path.join(HERE, "..", "romdb", "romdb.sqlite"))
CARTDB = os.path.join(HERE, "cartdb.sqlite")
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126.0 Safari/537.36"}

# The 4th character of a Nintendo game code is its region, and GameTDB files art
# under the matching directory. Trying the right one first keeps the request
# count down, which is the difference between a measurement and a scrape.
REGIONS = {
    "E": ["US"], "N": ["US"], "P": ["EN", "FR", "DE", "ES", "IT", "NL"], "X": ["EN"], "Y": ["EN"],
    "J": ["JA"], "K": ["KO"], "W": ["KO"], "F": ["FR"], "D": ["DE"], "S": ["ES"], "I": ["IT"],
    "H": ["NL"], "U": ["EN"], "A": ["US", "EN", "JA"],
}
FALLBACK = ["US", "EN"]

FOUND, ABSENT, UNKNOWN = "found", "absent", "unknown"


def look(url, timeout=20):
    """(FOUND|ABSENT|UNKNOWN, detail). ABSENT only on a real 404."""
    try:
        r = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout)
        if r.status == 200 and (r.headers.get("Content-Type") or "").startswith("image"):
            return FOUND, r.headers.get("Content-Length") or "?"
        return UNKNOWN, "status %s type %s" % (r.status, r.headers.get("Content-Type"))
    except urllib.error.HTTPError as e:
        return (ABSENT, "404") if e.code == 404 else (UNKNOWN, "http %d" % e.code)
    except (ssl.SSLError, urllib.error.URLError, TimeoutError, OSError) as e:
        # This is the throttle. Never let it read as "no art".
        return UNKNOWN, type(e).__name__


def probe_code(code, platform="ds", tries=3, pause=1.0):
    """Look for a cart image for one game code across its plausible regions."""
    regions = REGIONS.get(code[3].upper(), list(FALLBACK))
    for region in list(dict.fromkeys(regions + FALLBACK)):
        url = "https://art.gametdb.com/%s/cart/%s/%s.png" % (platform, region, code)
        for attempt in range(tries):
            state, detail = look(url)
            if state == FOUND:
                return FOUND, region, url, detail
            if state == ABSENT:
                break                                  # this region really has none
            time.sleep(pause * (attempt + 1) * 3)      # backing off, not hammering
        else:
            return UNKNOWN, region, url, detail        # never got a clear answer
        time.sleep(pause)
    return ABSENT, None, None, "404 in every region tried"


def codes_for(platform_code):
    conn = sqlite3.connect(ROMDB)
    rows = conn.execute(
        "SELECT serial FROM games WHERE kind = 'retail' AND platform = ? "
        "AND serial IS NOT NULL AND serial <> ''", (platform_code,))
    out = set()
    for (serial,) in rows:
        tail = serial.split("-")[-1].strip().upper()   # 3DS is CTR-P-XXXX
        if len(tail) == 4 and tail.isalnum():
            out.add(tail)
    return sorted(out)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--platform", default="NDS", choices=["NDS", "3DS"])
    ap.add_argument("--sample", type=int, default=60, help="how many codes to probe (0 with --all)")
    ap.add_argument("--all", action="store_true", help="probe every code -- thousands of requests, be sure")
    ap.add_argument("--pause", type=float, default=1.0, help="seconds between requests")
    ap.add_argument("--into-db", action="store_true", help="write found art into cartdb.sqlite")
    args = ap.parse_args(argv[1:])

    codes = codes_for(args.platform)
    print("%s: %d distinct 4-character codes in romdb" % (args.platform, len(codes)))
    if not args.all:
        random.seed(7)                                  # same sample every run, so runs compare
        codes = random.sample(codes, min(args.sample, len(codes)))
    print("probing %d, pausing %.1fs between requests\n" % (len(codes), args.pause))

    gametdb_platform = "ds" if args.platform == "NDS" else "3ds"
    tally = collections.Counter()
    found = []
    for i, code in enumerate(codes, 1):
        state, region, url, detail = probe_code(code, gametdb_platform, pause=args.pause)
        tally[state] += 1
        if state == FOUND:
            found.append((code, region, url))
        print("  %4d/%-4d %s  %-7s %s" % (i, len(codes), code, state, detail), flush=True)
        time.sleep(args.pause)

    clear = tally[FOUND] + tally[ABSENT]
    print("\n%-8s found %d, absent %d, unknown %d" % (args.platform, tally[FOUND], tally[ABSENT], tally[UNKNOWN]))
    if clear:
        print("cart art on %d of %d codes that answered clearly: %.0f%%" % (tally[FOUND], clear, 100.0 * tally[FOUND] / clear))
    if tally[UNKNOWN]:
        print("%d gave no clear answer (throttling) -- they are NOT counted as absent." % tally[UNKNOWN])

    if args.into_db and found:
        if not os.path.exists(CARTDB):
            print("no cartdb.sqlite -- run build_cartdb.py first", file=sys.stderr)
            return 1
        out = sqlite3.connect(CARTDB)
        romdb = sqlite3.connect(ROMDB)
        rows = []
        for code, region, url in found:
            hit = romdb.execute(
                "SELECT id, title FROM games WHERE kind = 'retail' AND platform = ? "
                "AND (serial = ? OR serial LIKE ?) LIMIT 1", (args.platform, code, "%-" + code)).fetchone()
            if hit:
                rows.append((args.platform, hit[0], hit[1], "front", region, "gametdb", code, url))
        out.executemany("INSERT OR IGNORE INTO art VALUES (?,?,?,?,?,?,?,?)", rows)
        out.commit()
        print("wrote %d GameTDB rows into cartdb.sqlite" % len(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
