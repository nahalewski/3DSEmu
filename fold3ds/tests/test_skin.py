"""Tests for skin.lua: model loading and the carousel, without drawing anything.

    python 3DSEmu/fold3ds/tests/test_skin.py

Ben's acceptance for the Switch skin is "it houses all the games". That is a
property of the carousel's paging, not of a screenshot, so it is answered here: for
libraries from 1 to 5000 games, walk the selection across the whole list and assert
every single index is on screen when it is the selected one. A screenshot shows one
page; this shows there is no game the shelf cannot reach.

love is absent under lupa, so only the pure parts run - load(), layout(), page(),
input(). The drawing is deliberately thin for exactly this reason.
"""
import os
import sys

try:
    import lupa
except ImportError:
    sys.exit("needs lupa:  python -m pip install lupa")

HERE = os.path.dirname(os.path.abspath(__file__))
FOLD = os.path.dirname(HERE)
EMU = os.path.dirname(FOLD)

PASS = FAIL = 0


def check(name, got, want):
    global PASS, FAIL
    if got == want:
        PASS += 1
    else:
        FAIL += 1
        print(f"  FAIL {name}\n       got  {got!r}\n       want {want!r}")


def main():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    # skin.lua requires "fold3ds.skinxml", so the search root is 3DSEmu/, and its
    # own paths are relative to that too - the same place the app runs from.
    lua.execute(f'package.path = [[{EMU.replace(os.sep, "/")}/?.lua;]] .. package.path')
    os.chdir(EMU)
    S = lua.eval('(require("fold3ds.skin"))')

    # ----------------------------------------------------------------- load ----
    m = S.load("switch")
    if m is None:
        print("  FAIL real skin did not load")
        return 1
    check("skin id", m.id, "switch")
    check("mode is full_screen", S.mode(), "full_screen")
    check("base resolution", (m.baseW, m.baseH), (1280, 720))
    check("filters read", len(m.filters), 5)
    check("system buttons read", len(m.system), 6)
    check("nav prompts read", len(m.prompts), 5)
    check("tile size from XML", (m.carousel.tileW, m.carousel.tileH), (230, 230))
    check("divider read", m.divider is not None, True)
    check("page dots read", m.pageDots is not None, True)
    # Colours must come from the file, not from anything written in skin.lua.
    check("primary is the XML cyan",
          tuple(round(m.color.primary[i], 3) for i in (1, 2, 3)), (0.039, 0.725, 0.902))

    # The skin declares light and dark variants and names one active. Both the set
    # and the choice come from the XML - nothing here knows what "dark" should be.
    check("both variants read", sorted(list(S.variants().values())), ["dark", "light"])
    check("active variant from ActiveVariant", m.variant, "dark")
    dark_text = tuple(round(m.color.text[i], 2) for i in (1, 2, 3))
    S.variant("light")
    light_text = tuple(round(S.model().color.text[i], 2) for i in (1, 2, 3))
    check("variant switch changes the palette", dark_text != light_text, True)
    check("dark text is light on dark", dark_text, (1.0, 1.0, 1.0))
    check("light text is dark on light", light_text, (0.17, 0.17, 0.17))
    check("variant carries its own background",
          S.model().bg.src != None, True)
    S.variant("dark")

    check("missing skin refused", S.load("no-such-skin")[0], None)

    # ------------------------------------ adapters for the wired draw path ----
    # homeswitch.lua had these as Lua literals, which is what Ben said not to do.
    # They must now come from skin.xml in exactly the shape that file expects.
    S.load("switch")
    btns = list(S.systemButtons().values())
    check("six system buttons from XML", len(btns), 6)
    check("ids from XML", [b.id for b in btns],
          ["news", "eshop", "album", "controllers", "settings", "sleep"])
    check("icon is a bare filename", btns[0].icon, "icon_news.png")
    check("colour converted to 0-255", list(btns[0].color.values()), [230, 0, 18])
    check("badge read from XML", btns[0].badge, 3)
    check("no badge where none declared", btns[1].badge, None)
    check("modal action split", btns[3].modal, "controllers")
    check("app action split", btns[1].action, "eshop")
    check("modal button has no plain action", btns[3].action, None)

    pills = list(S.filterPills().values())
    check("five pills from XML", len(pills), 5)
    check("pill labels from XML", [p.label for p in pills],
          ["All", "Games", "Apps", "Recent", "Favorites"])
    check("pill tex is a bare filename", pills[0].tex, "filter_all.png")

    # --------------------------------------------------------------- layout ----
    S.load("switch")
    L = S.layout(2560, 1440)
    check("uniform scale on 2x", round(L.scale, 4), 2.0)
    check("no letterbox at same aspect", (round(L.offX, 3), round(L.offY, 3)), (0.0, 0.0))
    # A taller panel must letterbox rather than stretch: proportions are the skin's.
    L2 = S.layout(1280, 1000)
    check("letterboxed vertically", round(L2.scale, 4), 1.0)
    check("centred vertically", round(L2.offY, 1), 140.0)

    # ------------------------------------------------- houses all the games ----
    for count in (1, 2, 5, 6, 7, 23, 100, 999, 5000):
        unreachable = []
        overfull = []
        for i in range(1, count + 1):
            p = S.page(count, i, None, 1280)
            if not (p.first <= i <= p.last):
                unreachable.append(i)
            if p.first < 1 or p.last > count:
                unreachable.append(("out of range", i, p.first, p.last))
            # perPage is how many tiles FIT on screen, which for a tiny library is
            # more than exist - so the invariant is about the window actually shown.
            if p.last - p.first + 1 > count:
                overfull.append((i, p.first, p.last))
        check(f"every game reachable at count={count}", unreachable, [])
        check(f"window never shows more than exist at count={count}", overfull, [])

    # Paging maths stays honest at the ends.
    p = S.page(100, 1, None, 1280)
    check("first selection starts at 1", p.first, 1)
    p = S.page(100, 100, None, 1280)
    check("last selection ends at the last game", p.last, 100)
    check("no empty slots at the end", p.last - p.first + 1, p.perPage)
    check("empty library is not a page", S.page(0, 1, None, 1280).last, -1)

    # ---------------------------------------------------------------- input ----
    S.games(lua.eval("{{name='a'},{name='b'},{name='c'}}"))
    check("count handed in", S.count(), 3)
    S.input("right")
    check("right moves", S.selected(), 2)
    S.input("left"); S.input("left")
    check("left wraps to the end", S.selected(), 3)
    S.input("right")
    check("right wraps to the start", S.selected(), 1)
    check("unknown action not consumed", S.input("jump"), False)

    # Handing in a shorter library must not leave the selection past the end.
    S.games(lua.eval("{{name='only'}}"))
    check("selection clamped on smaller library", S.selected(), 1)

    print(f"{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
