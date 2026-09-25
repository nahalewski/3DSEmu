"""Tests for skinxml.lua, run against the real Switch skin.

    python 3DSEmu/fold3ds/tests/test_skinxml.py

Lua runs here through lupa, so the parser is exercised on this machine rather than
discovered to be broken by a build on felix. The malformed cases matter as much as
the good one: a skin file people are meant to customise will be edited by hand, and
a parser that silently accepts a mismatched tag hands the renderer a half-built tree
that fails somewhere else entirely.
"""
import os
import sys

try:
    import lupa
except ImportError:
    sys.exit("needs lupa:  python -m pip install lupa")

HERE = os.path.dirname(os.path.abspath(__file__))
FOLD = os.path.dirname(HERE)
SKIN = os.path.join(os.path.dirname(os.path.dirname(FOLD)), "SKINS", "switch", "skin.xml")

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
    lua.execute(f'package.path = [[{FOLD.replace(os.sep, "/")}/?.lua;]] .. package.path')
    # Parenthesised: require returns two values and unpack_returned_tuples is on.
    X = lua.eval('(require("skinxml"))')

    # ------------------------------------------------------------- malformed ----
    check("empty refused", X.parse("")[1], "empty document")
    check("mismatched tag refused", X.parse("<a><b></a>")[1], "</a> closes <b>")
    check("unclosed refused", X.parse("<a><b></b>")[1], "<a> is never closed")
    check("stray close refused", X.parse("</a>")[1], "closing </a> with nothing open")
    check("two roots refused", X.parse("<a/><b/>")[1], "second root element <b>")
    check("text only refused", X.parse("hello")[1], "no elements found")

    # ----------------------------------------------------------------- shape ----
    n = X.parse('<r a="1" b="two"><k/><k/><t>  hi  </t></r>')
    check("root tag", n.tag, "r")
    check("attrs read", (n.attr.a, n.attr.b), ("1", "two"))
    check("self-closing children counted", len(X.children(n, "k")), 2)
    check("text trimmed", X.text(n, "t"), "hi")
    check("single quotes", X.parse("<r a='x'/>").attr.a, "x")
    check("entities decoded", X.parse("<r>a &amp; b &lt;c&gt;</r>").text, "a & b <c>")
    check("comment ignored", X.parse("<r><!-- <fake/> --><k/></r>").kids[1].tag, "k")
    check("declaration ignored", X.parse('<?xml version="1.0"?><r/>').tag, "r")
    # A comment holding angle brackets must not end the scan early.
    check("comment with tags inside", len(X.parse("<r><!-- </r> --><k/></r>").kids), 1)

    # ---------------------------------------------------------------- colour ----
    check("hex colour", tuple(round(v, 3) for v in X.color("#0AB9E6")), (0.039, 0.725, 0.902, 1.0))
    check("hex with alpha", round(X.color("#00000080")[3], 2), 0.5)
    check("named colour refused", X.color("cyan"), None)
    check("short hex refused", X.color("#FFF"), None)
    check("non-string refused", X.color(None), None)

    # ------------------------------------------------- the real Switch skin ----
    if not os.path.exists(SKIN):
        print(f"  SKIP real skin, not found at {SKIN}")
    else:
        with open(SKIN, encoding="utf-8") as fh:
            root = X.parse(fh.read())
        check("real skin parses", root is not None and root.tag, "Skin")
        check("skin id", root.attr.id, "switch")
        check("display mode", X.text(X.find(root, "Display"), "Mode"), "full_screen")

        res = X.find(root, "Display", "TargetResolution")
        check("target resolution", (X.num(res, "width", 0), X.num(res, "height", 0)), (1280, 720))

        # Colours moved under Theme/Variant when the skin gained light and dark.
        # Asserting the CURRENT path on purpose: skin.xml is the spec, so a schema
        # change should fail here loudly rather than be absorbed by a lenient test.
        variants = X.children(X.child(root, "Theme"), "Variant")
        check("two variants", len(variants), 2)
        colors = X.child(variants[1], "Colors")
        check("primary colour present", X.color(X.text(colors, "Primary")) is not None, True)

        check("five filters", len(X.children(X.child(root, "FilterBar"), "Filter")), 5)
        check("six system buttons", len(X.children(X.child(root, "SystemRow"), "Button")), 6)

        tile = X.find(root, "Carousel", "Tile")
        check("tile size", (int(X.text(tile, "Width")), int(X.text(tile, "Height"))), (230, 230))
        check("selected scale", X.text(tile, "SelectedScale"), "1.08")

        check("statusbar enabled", X.bool(X.child(root, "StatusBar"), "enabled", False), True)
        check("sounds present", X.find(root, "Sounds", "CursorMove") is not None, True)

    print(f"{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
