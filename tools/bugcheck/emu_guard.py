"""Bug Checker Dev: Ben's hard rule - no emulator code is changed or altered.

    python tools/bugcheck/emu_guard.py            # from 3DSEmu/
    python tools/bugcheck/emu_guard.py --root <3DSEmu dir> --eden <eden dir>

Exit 1 on any FAIL. WARN means "a human must review", not "fine".

WHAT COUNTS AS EMULATOR CODE (the rule, as encoded):
  Azahar      everything EXCEPT src/android/** (the Android app = display, UI, wiring).
  melonDS     all of it. No patch may touch it; its checkout must be clean at the pin.
  SkyEmu      all of it. Same.
  Eden        all of it. Its clone must be clean at the baseline HEAD.

LAYERS
  static      always runs: pins in build.sh match the baseline; every patch hunk targets
              an allowed path; patch files match their recorded hashes (new/changed -> WARN);
              build.sh never writes into Azahar outside src/android.
  checkout    runs when build/azahar, build/melonds, build/skyemu exist (after build.sh):
              HEAD == pin and no tracked change in a protected path (includes submodules).
  eden        runs when the Eden clone exists: HEAD == baseline and clean.

The baseline (emu_guard_baseline.json) is Ben's pinned state. Changing it IS changing
which emulator code ships: never edit it to make this check pass - get Ben's word first.
Validate this script with test_emu_guard.py before trusting a run.
"""
import argparse, hashlib, json, os, re, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
PIN_RE = re.compile(r'^(AZAHAR|MELONDS|SKYEMU)_COMMIT="\$\{\1_COMMIT:-([0-9a-f]{40})\}"', re.M)
AZAHAR_ALLOWED = re.compile(r"^src/android/")


def git(repo, *args):
    r = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout.strip() if r.returncode == 0 else None


def patch_targets(text):
    """Every path a patch touches, old and new side (a rename or delete counts too)."""
    out = set()
    for m in re.finditer(r"^(?:---|\+\+\+) (?:[ab]/)?(\S.*?)\s*$", text, re.M):
        if m.group(1) != "/dev/null":
            out.add(m.group(1))
    for m in re.finditer(r"^diff --git a/(\S+) b/(\S+)", text, re.M):
        out.update(m.groups())
    for m in re.finditer(r"^rename (?:from|to) (\S.*)$", text, re.M):
        out.add(m.group(1))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(HERE.parents[1]))
    ap.add_argument("--eden", default=None)
    ap.add_argument("--baseline", default=str(HERE / "emu_guard_baseline.json"))
    a = ap.parse_args()
    root = Path(a.root)
    eden = Path(a.eden) if a.eden else root.parent / "eden"
    base = json.loads(Path(a.baseline).read_text(encoding="utf-8"))
    rows = []  # (sev, area, message)

    # ---- static: pins
    build_sh = (root / "build.sh").read_text(encoding="utf-8", errors="replace")
    pins = {k.lower(): v for k, v in PIN_RE.findall(build_sh)}
    for emu, want in base["pins"].items():
        got = pins.get(emu)
        if got != want:
            rows.append(("FAIL", emu, f"pin in build.sh is {got} - baseline {want}"))

    # ---- static: patches
    for pdir, emu in (("azahar/patches", "azahar"), ("patches", "launcher")):
        for p in sorted((root / pdir).glob("*.patch")) if (root / pdir).is_dir() else []:
            rel = f"{pdir}/{p.name}"
            data = p.read_bytes()
            h = hashlib.sha256(data).hexdigest()
            known = base["patches"].get(rel)
            if known is None:
                rows.append(("WARN", rel, "new patch - not in baseline, review before it ships"))
            elif known != h:
                rows.append(("WARN", rel, "patch changed since baseline - review before it ships"))
            if emu == "azahar":
                for t in sorted(patch_targets(data.decode("utf-8", "replace"))):
                    if not AZAHAR_ALLOWED.match(t):
                        rows.append(("FAIL", rel, f"touches Azahar emulator code: {t}"))
    for rel in base["patches"]:
        if not (root / rel).is_file():
            rows.append(("WARN", rel, "baseline patch is missing"))
    for emu in ("melonds", "skyemu"):
        if re.search(rf'git -C "\$B/{emu}" apply|patch .*\$B/{emu}', build_sh):
            rows.append(("FAIL", emu, "build.sh applies a patch to it"))

    # ---- static: build.sh writes into Azahar outside src/android
    # A variable aimed into Azahar outside src/android is caught at its definition, since a later
    # `cp x "$VAR/..."` no longer mentions $A (APP and EMU are defined under src/android - allowed).
    for n, line in enumerate(build_sh.splitlines(), 1):
        m = re.match(r'\s*([A-Za-z_]\w*)="?\$(?:A|\{A\})(?![A-Za-z0-9_])/?([^"\s]*)', line)
        if m and not m.group(2).startswith("src/android"):
            rows.append(("FAIL", f"build.sh:{n}", f"${m.group(1)} points into Azahar outside src/android: {line.strip()[:90]}"))
    for n, line in enumerate(build_sh.splitlines(), 1):
        s = line.split("#", 1)[0]
        if not re.search(r"\b(cp|mv|ln|sed -i|git -C \"\$A\" apply|tee|cat >|>)\b|>", s):
            continue
        for m in re.finditer(r'"?\$(A|\{A\})(?![A-Za-z0-9_])"?(/[^\s"\']*)?', s):
            tail = (m.group(2) or "").lstrip("/")
            if m.group(1) and not tail.startswith("src/android"):
                if re.search(r"git -C \"\$A\" (submodule|apply)", s):
                    continue  # submodule fetch; patches are judged by their targets above
                rows.append(("FAIL", f"build.sh:{n}", f"writes into Azahar outside src/android: {line.strip()[:90]}"))
    for n, line in enumerate(build_sh.splitlines(), 1):
        s = line.split("#", 1)[0]
        if re.search(r'\$B/(melonds|skyemu)', s) and re.search(r"\b(cp|mv|sed -i|apply|tee)\b|>", s) and "checkout" not in s:
            rows.append(("FAIL", f"build.sh:{n}", f"writes into melonDS/SkyEmu: {line.strip()[:90]}"))

    # ---- checkout layer
    for emu in ("azahar", "melonds", "skyemu"):
        co = root / "build" / emu
        if not (co / ".git").exists():
            rows.append(("INFO", emu, "no checkout in build/ - checkout layer skipped"))
            continue
        head = git(co, "rev-parse", "HEAD")
        if head != base["pins"][emu]:
            rows.append(("FAIL", emu, f"checkout HEAD {head} != pin"))
        changed = (git(co, "status", "--porcelain", "--ignore-submodules=none") or "").splitlines()
        for c in changed:
            path = c[3:].strip().strip('"')
            if emu != "azahar" or not AZAHAR_ALLOWED.match(path):
                rows.append(("FAIL", emu, f"protected file changed in checkout: {c.strip()}"))
        subs = (git(co, "submodule", "status", "--recursive") or "").splitlines()
        for s in subs:
            if s[:1] in "+-U":
                rows.append(("FAIL", emu, f"submodule not at recorded commit: {s.strip()[:90]}"))

    # ---- eden
    if (eden / ".git").exists():
        head = git(eden, "rev-parse", "HEAD")
        if head != base["eden_head"]:
            rows.append(("FAIL", "eden", f"HEAD {head} != baseline {base['eden_head']}"))
        dirty = (git(eden, "status", "--porcelain", "--ignore-submodules=none") or "").splitlines()
        for c in dirty[:20]:
            rows.append(("FAIL", "eden", f"changed: {c.strip()}"))
    else:
        rows.append(("INFO", "eden", f"no clone at {eden} - skipped"))

    for sev, area, msg in rows:
        print(f"{sev:5} {area:34} {msg}")
    fails = sum(1 for r in rows if r[0] == "FAIL")
    warns = sum(1 for r in rows if r[0] == "WARN")
    print(f"\n{'FAIL' if fails else 'PASS'}: {fails} fail, {warns} warn")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
