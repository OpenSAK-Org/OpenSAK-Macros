"""
scripts/build_index.py — builds index.json, the list of macros OpenSAK's
Macro manager reads to browse, install and update macros.

Run by .github/workflows/index.yml after every push to main; the workflow
publishes the result on the "index" branch:

    https://raw.githubusercontent.com/OpenSAK-Org/OpenSAK-Macros/index/index.json

Like check_macro_pr.py it only reads git objects (git ls-tree / git show /
git log) and parses headers with OpenSAK's own src/opensak/macro/metadata.py
(--metadata). It never runs Lua code.

Everything comes from the git history of one commit (--ref, normally main),
so building twice from the same commit gives the same file:

  - macros: every folder under macros/ that has <folder>/<folder>.lua, with
    its header, every file in the folder (size, SHA-256 and a download URL
    pinned to the commit, so the bytes behind a URL never change), the
    versions it had on main (when each was published, the SHA-256 of the
    macro file) and the changelog from the "## Changes" section of its
    README.
  - withdrawn: folders that were on main once and are not any more, with
    their last version and the hashes of all their versions, so OpenSAK can
    tell a user that an installed macro was withdrawn.

Hashes are taken over the bytes git stores, which are the bytes
raw.githubusercontent.com serves (no CRLF conversion).

A macro whose header can't be read is still listed, with "error" set; the
pull request checks keep that from happening on main.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath
from types import ModuleType
from typing import Any

SCHEMA = 1
MACROS_DIR = "macros"
DEFAULT_REPOSITORY = "OpenSAK-Org/OpenSAK-Macros"
RAW_URL = "https://raw.githubusercontent.com/{repo}/{commit}/{path}"
PAGE_URL = "https://github.com/{repo}/tree/{ref}/{path}"
VERSION = re.compile(r"^\d+(?:\.\d+)*$")

# "## Changes" (also "## Changelog", "## Change log", "## History")
_CHANGES_HEADING = re.compile(r"^##\s+(?:changes|change\s*log|history)\s*$", re.I)
# "- 1.1 — text", also with "-", "–", ":" or "(date)" after the version
_CHANGE_ITEM = re.compile(
    r"^[-*]\s+v?(\d+(?:\.\d+)*)\b\s*(?:\([^)]*\))?\s*(?:—|–|-|:)?\s*(.*)$")


# --- git ---------------------------------------------------------------------

class Git:
    def __init__(self, repo: Path):
        self.repo = repo

    def _run(self, *args: str, check: bool = True) -> subprocess.CompletedProcess:
        return subprocess.run(["git", "-C", str(self.repo), *args],
                              capture_output=True, check=check)

    def rev_parse(self, rev: str) -> str:
        return self._run("rev-parse", "--verify", f"{rev}^{{commit}}"
                         ).stdout.decode().strip()

    def commit_date(self, rev: str) -> str:
        return utc(self._run("show", "-s", "--format=%ct", rev).stdout.decode())

    def ls_tree(self, rev: str, folder: str) -> list[tuple[str, int]]:
        """(path, size) of every file under *folder* at *rev*."""
        out = self._run("ls-tree", "-r", "-z", "--long", rev, "--",
                        folder + "/").stdout.decode("utf-8")
        files = []
        for entry in out.split("\0"):
            if not entry:
                continue
            meta, path = entry.split("\t", 1)
            kind, size = meta.split()[1], meta.split()[3]
            if kind == "blob":
                files.append((path, int(size)))
        return sorted(files)

    def read(self, rev: str, path: str) -> bytes | None:
        proc = self._run("show", f"{rev}:{path}", check=False)
        return proc.stdout if proc.returncode == 0 else None

    def folders_ever(self, rev: str) -> set[str]:
        """Names of all folders under macros/ that ever had a file on the
        first-parent history of *rev*."""
        out = self._run("log", "--first-parent", "--format=", "--name-only",
                        "-z", rev, "--", MACROS_DIR + "/").stdout.decode("utf-8")
        names = set()
        for path in out.replace("\n", "\0").split("\0"):
            parts = PurePosixPath(path).parts
            if len(parts) >= 3 and parts[0] == MACROS_DIR:
                names.add(parts[1])
        return names

    def history(self, rev: str, path: str) -> list[tuple[str, str]]:
        """(commit, date) of every commit on the first-parent history of
        *rev* that changed *path*, oldest first. On main these are the merge
        commits, i.e. when a change was published."""
        out = self._run("log", "--first-parent", "--format=%H %ct", rev,
                        "--", path).stdout.decode()
        found = []
        for line in reversed(out.splitlines()):
            if line:
                commit, stamp = line.split(" ", 1)
                found.append((commit, utc(stamp)))
        return found


# --- helpers -----------------------------------------------------------------

def load_metadata_module(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location("macro_metadata", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Cannot load the OpenSAK header parser from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["macro_metadata"] = module   # dataclasses look the module up
    spec.loader.exec_module(module)
    return module


def utc(stamp: str) -> str:
    """A git Unix timestamp as ISO 8601 in UTC, e.g. 2026-11-18T12:14:51Z."""
    when = datetime.fromtimestamp(int(stamp.strip()), timezone.utc)
    return when.strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def version_key(version: str) -> tuple[int, ...]:
    """Dot-separated numbers as a comparable tuple; trailing zeros dropped
    so that 1.0 and 1.0.0 are the same version."""
    parts = [int(x) for x in version.split(".")]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


def same_version(a: str, b: str) -> bool:
    if VERSION.match(a) and VERSION.match(b):
        return version_key(a) == version_key(b)
    return a == b


def header(md: ModuleType, data: bytes | None, path: str) -> dict[str, Any]:
    """The header fields OpenSAK's Macro manager shows, or {"error": ...}."""
    if data is None:
        return {"error": "missing"}
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return {"error": "not UTF-8 text"}
    info = md.parse_header(text, Path(path))
    api = getattr(info, "requires_api_number", None)
    return {
        "name": info.name,
        "author": info.author,
        "version": info.version,
        "description": info.description,
        "requires_api": api if api is not None else (info.requires_api or None),
        "permissions": list(info.permissions)
                       or ([md.NO_PERMISSIONS] if info.permissions_declared else []),
        "network": list(info.network),
        # null with a parser from before the Headless key (API 4)
        "headless": getattr(info, "runs_headless", None),
    }


def changelog(readme: bytes | None) -> list[dict[str, str]]:
    """The entries of the "## Changes" section of a macro README: one per
    list item starting with a version ("- 1.1 — what changed"), newest
    first. Indented lines below an item continue it."""
    if not readme:
        return []
    try:
        text = readme.decode("utf-8")
    except UnicodeDecodeError:
        return []
    entries: list[dict[str, str]] = []
    inside = False
    for raw in text.splitlines():
        line = raw.strip()
        if raw.startswith("#"):
            inside = bool(_CHANGES_HEADING.match(line))
            continue
        if not inside or not line:
            continue
        m = _CHANGE_ITEM.match(line)
        if m:
            entries.append({"version": m.group(1), "text": m.group(2).strip()})
        elif entries and raw[:1] in (" ", "\t"):
            entries[-1]["text"] = (entries[-1]["text"] + " " + line).strip()
    good = [e for e in entries if VERSION.match(e["version"])]
    good.sort(key=lambda e: version_key(e["version"]), reverse=True)
    return good


def versions(git: Git, md: ModuleType, ref: str, main: str,
             repository: str) -> list[dict[str, Any]]:
    """Every version of the macro file *main* on the history of *ref*,
    newest first: when it was first published and the file of its last
    commit (a version republished without a bump keeps the newest bytes)."""
    found: list[dict[str, Any]] = []
    for commit, date in git.history(ref, main):
        data = git.read(commit, main)
        if data is None:           # the file was removed in this commit
            continue
        h = header(md, data, main)
        version = h.get("version", "")
        entry = {
            "version": version,
            "published": date,
            "commit": commit,
            "requires_api": h.get("requires_api"),
            "permissions": h.get("permissions", []),
            "network": h.get("network", []),
            "size": len(data),
            "sha256": sha256(data),
            "url": RAW_URL.format(repo=repository, commit=commit, path=main),
        }
        if found and same_version(found[-1]["version"], version):
            entry["published"] = found[-1]["published"]
            found[-1] = entry
        else:
            found.append(entry)
    return list(reversed(found))


# --- the index ---------------------------------------------------------------

def macro_entry(git: Git, md: ModuleType, commit: str, name: str,
                repository: str) -> dict[str, Any] | None:
    folder = f"{MACROS_DIR}/{name}"
    main = f"{folder}/{name}.lua"
    files = git.ls_tree(commit, folder)
    if main not in {p for p, _ in files}:
        return None
    entry: dict[str, Any] = {"id": name, "folder": folder}
    entry.update(header(md, git.read(commit, main), main))
    entry["file"] = main
    entry["readme"] = f"{folder}/README.md" if any(
        p == f"{folder}/README.md" for p, _ in files) else None
    entry["page"] = PAGE_URL.format(repo=repository, ref="main", path=folder)
    entry["files"] = [
        {"path": p, "size": size, "sha256": sha256(git.read(commit, p) or b""),
         "url": RAW_URL.format(repo=repository, commit=commit, path=p)}
        for p, size in files
    ]
    entry["versions"] = versions(git, md, commit, main, repository)
    if entry["versions"]:
        entry["published"] = entry["versions"][-1]["published"]
        entry["updated"] = entry["versions"][0]["published"]
    entry["changelog"] = changelog(
        git.read(commit, entry["readme"]) if entry["readme"] else None)
    return entry


def withdrawn_entry(git: Git, md: ModuleType, commit: str, name: str,
                    repository: str) -> dict[str, Any] | None:
    main = f"{MACROS_DIR}/{name}/{name}.lua"
    history = versions(git, md, commit, main, repository)
    if not history:
        return None                # never had a macro file (e.g. a typo folder)
    removed = git.history(commit, main)[-1]
    last = history[0]
    return {
        "id": name,
        "folder": f"{MACROS_DIR}/{name}",
        "name": header(md, git.read(last["commit"], main), main).get("name", name),
        "last_version": last["version"],
        "withdrawn": removed[1],
        "versions": [{"version": v["version"], "sha256": v["sha256"]}
                     for v in history],
    }


def build(repo: Path, ref: str, md: ModuleType,
          repository: str = DEFAULT_REPOSITORY) -> dict[str, Any]:
    git = Git(repo)
    commit = git.rev_parse(ref)
    current = {p.split("/")[1] for p, _ in git.ls_tree(commit, MACROS_DIR)
               if len(PurePosixPath(p).parts) >= 3}
    macros = [e for name in sorted(current)
              if (e := macro_entry(git, md, commit, name, repository))]
    listed = {m["id"] for m in macros}
    withdrawn = [e for name in sorted(git.folders_ever(commit) - listed)
                 if (e := withdrawn_entry(git, md, commit, name, repository))]
    return {
        "schema": SCHEMA,
        "repository": f"https://github.com/{repository}",
        "commit": commit,
        "generated": git.commit_date(commit),
        "macros": macros,
        "withdrawn": withdrawn,
    }


def dumps(index: dict[str, Any]) -> str:
    return json.dumps(index, indent=2, ensure_ascii=False) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--repo", type=Path, default=Path("."))
    parser.add_argument("--ref", default="HEAD", help="commit to index (main)")
    parser.add_argument("--metadata", type=Path, required=True,
                        help="path to OpenSAK's src/opensak/macro/metadata.py")
    parser.add_argument("--repository", default=DEFAULT_REPOSITORY,
                        help="owner/name on GitHub, for the download URLs")
    parser.add_argument("--output", type=Path, help="write here (default: stdout)")
    args = parser.parse_args(argv)

    index = build(args.repo, args.ref, load_metadata_module(args.metadata),
                  args.repository)
    text = dumps(index)
    if args.output:
        args.output.write_text(text, encoding="utf-8", newline="\n")
        print(f"{len(index['macros'])} macro(s), {len(index['withdrawn'])} "
              f"withdrawn, from {index['commit']}")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
