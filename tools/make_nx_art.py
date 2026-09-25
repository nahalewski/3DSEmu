#!/usr/bin/env python3
"""Switch game art for the HOME menu: fold3ds/emudb/nx.tsv from blawar/titledb.

One line per base game with art: <title id>\t<icon hash>\t<banner hash>, the
hashes being the file names under https://img-eshop.cdn.nintendo.net/i/
(<hash>.jpg).  fold3ds/eden.lua looks a game's title id up in it and
fetches the pictures on the phone once.  Run by build.sh (it needs the
network); the file is generated, not kept in git.  With no network the
build goes on without it and the games show Eden's own icons.
"""
import json, os, sys, urllib.request

URL = "https://raw.githubusercontent.com/blawar/titledb/%s/US.en.json"
PREFIX = "https://img-eshop.cdn.nintendo.net/i/"


def main():
    ref = os.environ.get("TITLEDB_REF", "master")
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "..", "fold3ds", "emudb", "nx.tsv")
    try:
        doc = json.loads(urllib.request.urlopen(URL % ref, timeout=120).read())
    except Exception as e:
        print("nx art: skipped (%s)" % e)
        return

    def tail(u):
        if u and u.startswith(PREFIX) and u.endswith(".jpg"):
            return u[len(PREFIX):-4]
        return ""

    rows = {}
    for e in doc.values():
        tid = (e.get("id") or "").upper()
        if len(tid) != 16 or not tid.endswith("000"):
            continue
        icon, banner = tail(e.get("iconUrl")), tail(e.get("bannerUrl"))
        if icon or banner:
            rows[tid] = "%s\t%s\t%s" % (tid, icon, banner)
    with open(out, "w") as f:
        for tid in sorted(rows):
            f.write(rows[tid] + "\n")
    print("nx art: %d games" % len(rows))


if __name__ == "__main__":
    main()
