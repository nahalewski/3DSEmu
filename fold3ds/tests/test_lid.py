"""Tests for lid.lua: the fold-to-close easter egg, driven by hinge angle.

    python 3DSEmu/fold3ds/tests/test_lid.py

The parts worth testing are the ones a device would show late and expensively:
that mute and standby fire ONCE at the latch and not every frame, that a hand
resting near the threshold does not chatter the game in and out of standby, and
that the animation follows the angle rather than a clock.
"""
import os
import sys

try:
    import lupa
except ImportError:
    sys.exit("needs lupa:  python -m pip install lupa")

HERE = os.path.dirname(os.path.abspath(__file__))
EMU = os.path.dirname(os.path.dirname(HERE))

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
    lua.execute(f'package.path = [[{EMU.replace(os.sep, "/")}/?.lua;]] .. package.path')
    L = lua.eval('(require("fold3ds.lid"))')

    log = []
    hooks = lua.table_from({
        "onClick": lambda which: log.append("click:" + which),
        "onMute": lambda on: log.append("mute:" + ("on" if on else "off")),
        "onStandby": lambda on: log.append("standby:" + ("on" if on else "off")),
        "onResume": lambda: log.append("resume"),
    })
    L.hooks(hooks)

    # -------------------------------------------------------- angle -> anim ----
    L.reset(180)
    check("flat open is progress 0", L.progress(180), 0)
    check("shut is progress 1", L.progress(10), 1)
    check("halfway is halfway", round(L.progress((170 + 15) / 2), 3), 0.5)
    check("progress is clamped open", L.progress(200), 0)
    check("progress is clamped shut", L.progress(-20), 1)
    # Driven by angle, not time: the same angle always gives the same frame.
    check("same angle, same frame", L.progress(92), L.progress(92))

    # ------------------------------------------------------ close sequence ----
    L.reset(180)
    log.clear()
    for deg in (180, 160, 120, 90, 60, 30, 14, 5):
        L.set(deg)
    check("shut after folding", L.state(), "closed")
    check("closed reported", L.closed(), True)
    check("close fired once, in order", log, ["click:close", "mute:on", "standby:on"])

    # Holding it shut must not fire anything again.
    log.clear()
    for _ in range(30):
        L.set(3)
    check("no repeat while held shut", log, [])

    # ------------------------------------------------------- open sequence ----
    log.clear()
    for deg in (5, 20, 40, 90, 140, 175, 180):
        L.set(deg)
    check("open after unfolding", L.state(), "open")
    check("open fired once, in order", log, ["click:open", "mute:off", "resume"])

    log.clear()
    for _ in range(30):
        L.set(180)
    check("no repeat while held open", log, [])

    # ----------------------------------------------------------- chatter ----
    # A hand resting at the threshold is the case that would flicker standby. The
    # latches are deliberately offset (shut at 15, reopen at 35) so wobbling
    # between them changes nothing.
    L.reset(180)
    for deg in (180, 100, 20, 10):
        L.set(deg)
    log.clear()
    for deg in (16, 20, 25, 30, 20, 16, 25, 18):
        L.set(deg)
    check("no chatter between the latches", log, [])
    check("still shut while wobbling", L.state(), "closed")

    # Past the reopen latch it does reopen, once.
    log.clear()
    L.set(40)
    check("reopening reported", L.state(), "opening")
    check("reopening is not the open latch yet", log, [])
    L.set(175)
    check("open latch on the way up", log, ["click:open", "mute:off", "resume"])

    # ---------------------------------------------------------- injection ----
    # The angle source is injectable, which is what lets any of this run here.
    L.reset(180)
    L.source(lua.eval("function() return 0 end"))
    L.update()
    check("update reads the source", L.state(), "closed")

    # A source that returns nothing must not move the lid or crash the frame.
    L.reset(180)
    L.source(lua.eval("function() return nil end"))
    L.update()
    check("no angle leaves it open", L.state(), "open")
    L.source(lua.eval('function() return "not a number" end'))
    L.update()
    check("junk angle ignored", L.state(), "open")

    check("covering only once moving", L.covering(), False)
    L.set(90)
    check("covering while closing", L.covering(), True)

    print(f"{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
