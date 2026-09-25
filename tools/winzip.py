#!/usr/bin/env python3
"""Minimal `zip` for Windows builds (Git Bash ships unzip but not zip). build.sh puts a `zip`
wrapper that runs this first on PATH, Windows only.

Supports exactly what gen1recomp's scripts/build_android.sh uses:
    zip -q -9 -r ARCHIVE path... [-x PATTERN ...]    create/update, recursive, with excludes
    zip -q ARCHIVE file                              add/replace one entry in an existing archive
Entries are stored with forward slashes relative to the current directory, deflated at level 9.
`-x` patterns use fnmatch, where `*` also matches `/`, as Info-ZIP's wildcards do.
An existing archive is updated: replaced entries are rewritten, others kept.
"""
import fnmatch, os, shutil, sys, tempfile, zipfile


def main(argv):
    recurse, excludes, rest, i = False, [], [], 0
    while i < len(argv):
        a = argv[i]
        if a == "-x":
            i += 1
            while i < len(argv) and not argv[i].startswith("-"):
                excludes.append(argv[i]); i += 1
            continue
        if a.startswith("-") and len(a) > 1:
            if "r" in a[1:]:
                recurse = True          # -q and -0..-9 need no handling
        else:
            rest.append(a)
        i += 1
    if len(rest) < 2:
        print("winzip: need ARCHIVE and at least one path", file=sys.stderr); return 12
    archive, inputs = rest[0], rest[1:]

    files = []
    for p in inputs:
        if os.path.isdir(p):
            if not recurse:
                continue
            for dp, _, fs in os.walk(p):
                for f in fs:
                    files.append(os.path.join(dp, f))
        elif os.path.isfile(p):
            files.append(p)
        else:
            print(f"winzip: warning: name not matched: {p}", file=sys.stderr)
    names = {}
    for f in files:
        n = os.path.normpath(f).replace(os.sep, "/")
        if not any(fnmatch.fnmatch(n, x) for x in excludes):
            names[n] = f

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".zip", dir=os.path.dirname(os.path.abspath(archive)) or ".")
    tmp.close()
    with zipfile.ZipFile(tmp.name, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as out:
        if os.path.exists(archive):
            with zipfile.ZipFile(archive) as old:
                for info in old.infolist():
                    if info.filename not in names:
                        out.writestr(info, old.read(info.filename))
        for n, f in sorted(names.items()):
            out.write(f, n)
    shutil.move(tmp.name, archive)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
