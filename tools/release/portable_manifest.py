#!/usr/bin/env python3
"""version.json for the portable Windows build, and its update folder.

  python tools/release/portable_manifest.py write <portable folder>
      Writes <portable folder>/version.json: the version, notes and update URL
      of the build's engine_boot.lua (SURVIVOR_ENGINE.version/notes/update, from
      src/) and every file of the folder (path, size, sha1). make_portable.ps1
      runs it.

  python tools/release/portable_manifest.py stage <portable folder> <update folder>
      Brings <update folder> (release/update/portable) to that build: its
      version.json plus files/<path> for every file. A file whose sha1 is
      unchanged since the last stage is left alone (same timestamp, so a
      WinSCP synchronize does not upload it again); new and changed ones are
      hard-linked (copied across drives), files gone from the build removed.
      The folder is served at SURVIVOR_ENGINE.update (download/portable/ on the
      site: stage_survivor_upload.py --portable-update).

The launcher (warcraft_survivors_launcher.cs) compares the local version.json
with the served one and downloads the files whose sha1 differs.
"""
import hashlib
import json
import os
import pathlib
import re
import shutil
import sys

# The build's copy of src/engine_boot.lua.
BOOT = "OpenRealm/share/warcraft-3/Scripts/Survivor/engine_boot.lua"
# Not part of a build: the manifest itself and the launcher's work folders.
SKIP_TOP = {"version.json", ".update", ".update-backup"}


def lua_field(text, name, source):
    match = re.search(r"^\s*" + name + r"\s*=\s*'((?:[^'\\]|\\.)*)'", text, re.M)
    if not match:
        raise SystemExit("SURVIVOR_ENGINE.%s not found in %s" % (name, source))
    return re.sub(r"\\(.)", r"\1", match.group(1))


def sha1(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def build_files(folder):
    files = []
    for path in sorted(folder.rglob("*")):
        rel = path.relative_to(folder)
        if rel.parts[0] in SKIP_TOP or not path.is_file():
            continue
        files.append({"path": rel.as_posix(), "size": path.stat().st_size, "sha1": sha1(path)})
    return files


def write(folder):
    boot = folder / BOOT
    text = boot.read_text(encoding="utf-8")
    manifest = {
        "version": lua_field(text, "version", boot),
        "notes": lua_field(text, "notes", boot),
        "update": lua_field(text, "update", boot),
        "files": build_files(folder),
    }
    for entry in manifest["files"]:
        entry["url"] = "files/" + entry["path"]
    (folder / "version.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    total = sum(f["size"] for f in manifest["files"])
    print("version.json: v%s, %d files, %.0f MB" % (manifest["version"], len(manifest["files"]), total / 1048576))


def place(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        target.unlink()
    try:
        os.link(source, target)
    except OSError:
        shutil.copy2(source, target)


def stage(folder, out):
    manifest_path = folder / "version.json"
    if not manifest_path.is_file():
        raise SystemExit("no version.json in %s (run write first)" % folder)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    previous = {}
    if (out / "version.json").is_file():
        for entry in json.loads((out / "version.json").read_text(encoding="utf-8")).get("files", []):
            previous[entry["path"]] = entry["sha1"]
    files = out / "files"
    wanted = set()
    kept = changed = 0
    for entry in manifest["files"]:
        target = files / entry["path"]
        wanted.add(target.resolve())
        if previous.get(entry["path"]) == entry["sha1"] and target.is_file() and target.stat().st_size == entry["size"]:
            kept += 1
            continue
        place(folder / entry["path"], target)
        changed += 1
    removed = 0
    if files.is_dir():
        for path in sorted(files.rglob("*"), reverse=True):
            if path.is_file() and path.resolve() not in wanted:
                path.unlink()
                removed += 1
            elif path.is_dir() and not any(path.iterdir()):
                path.rmdir()
    shutil.copy2(manifest_path, out / "version.json")
    print("%s: v%s, %d new or changed, %d unchanged, %d removed" % (out, manifest["version"], changed, kept, removed))


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "write":
        write(pathlib.Path(sys.argv[2]))
    elif len(sys.argv) == 4 and sys.argv[1] == "stage":
        stage(pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3]))
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
