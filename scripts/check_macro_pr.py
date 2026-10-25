"""
scripts/check_macro_pr.py — checks the macro a pull request adds or changes.

Run by .github/workflows/check.yml on every pull request. It only reads git
objects (git diff / git show) between two commits; it never runs the Lua
code — the syntax check compiles it without executing it.

The header is parsed with OpenSAK's own parser, src/opensak/macro/metadata.py,
loaded from a file path (--metadata) rather than imported from an installed
OpenSAK: the module uses only the standard library, while importing it as
opensak.macro.metadata would pull in the whole macro runtime (SQLAlchemy,
lupa, ...). The workflow downloads it from a pinned OpenSAK commit.

Rules (see CONTRIBUTING.md):
  - only one folder under macros/ may change, and a pull request that
    changes a macro folder may not change anything else
  - folder name: lowercase letters, digits and hyphens; the folder holds
    <folder>.lua and README.md
  - header: Name, Author, Version, Description, Requires-API and
    Permissions present; Version is dot-separated numbers; Requires-API is
    a number; Permissions has no unknown words and doesn't combine "none"
    with other words; Network has no invalid or blocked hosts
  - Version is higher than on the base branch when a .lua file changed
  - every .lua file in the folder is valid Lua 5.4 source (text, not bytecode)

The result is printed, written to the job summary ($GITHUB_STEP_SUMMARY) and,
with --json, saved for the auto-merge workflow: the folder, whether it is a
new macro, what the update declares beyond the base version
(added_permissions() in metadata.py), and whether a maintainer must review.
Exit code 1 if any rule fails.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path, PurePosixPath
from types import ModuleType

MACROS_DIR = "macros"
FOLDER_NAME = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
VERSION = re.compile(r"^\d+(?:\.\d+)*$")
REQUIRED_KEYS = ("name", "author", "version", "description", "requires-api",
                 "permissions")
KEY_TITLES = {"name": "Name", "author": "Author", "version": "Version",
              "description": "Description", "requires-api": "Requires-API",
              "permissions": "Permissions"}


@dataclass
class Problem:
    message: str
    file: str = ""
    line: int = 0


@dataclass
class Result:
    folder: str = ""
    # "new", "update", "removed", or "none" when no macro folder changed
    status: str = "none"
    version_old: str = ""
    version_new: str = ""
    added_permissions: list[str] = field(default_factory=list)
    review_reasons: list[str] = field(default_factory=list)
    errors: list[Problem] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors

    @property
    def requires_review(self) -> bool:
        return bool(self.review_reasons)

    def error(self, message: str, file: str = "", line: int = 0) -> None:
        self.errors.append(Problem(message, file, line))

    def as_json(self) -> dict:
        data = asdict(self)
        data["ok"] = self.ok
        data["requires_review"] = self.requires_review
        return data


# --- git ---------------------------------------------------------------------

class Git:
    def __init__(self, repo: Path):
        self.repo = repo

    def _run(self, *args: str, check: bool = True) -> subprocess.CompletedProcess:
        return subprocess.run(["git", "-C", str(self.repo), *args],
                              capture_output=True, check=check)

    def changed_paths(self, base: str, head: str) -> list[str]:
        """Paths the pull request changes: head against its merge base with
        *base*. Renames count as a delete plus an add, so moving a file
        between folders touches both."""
        out = self._run("diff", "--name-only", "--no-renames", "-z",
                        f"{base}...{head}").stdout
        return [p for p in out.decode("utf-8").split("\0") if p]

    def files_in(self, rev: str, folder: str) -> list[str]:
        out = self._run("ls-tree", "-r", "-z", "--name-only", rev, "--",
                        folder + "/").stdout
        return sorted(p for p in out.decode("utf-8").split("\0") if p)

    def read(self, rev: str, path: str) -> bytes | None:
        proc = self._run("show", f"{rev}:{path}", check=False)
        return proc.stdout if proc.returncode == 0 else None


# --- helpers -----------------------------------------------------------------

def load_metadata_module(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location("macro_metadata", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Cannot load the OpenSAK header parser from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["macro_metadata"] = module   # dataclasses look the module up
    spec.loader.exec_module(module)
    return module


def header_keys(md: ModuleType, text: str) -> dict[str, list[str]]:
    """The keys written in the header of *text*, lower-cased, with their
    values. The parser itself fills in defaults (a missing Name becomes the
    file name), so it can't tell us which keys are actually there; this uses
    its own line rules (_header_lines, _KEY_LINE) to find out."""
    keys: dict[str, list[str]] = {}
    for line in md._header_lines(text.lstrip("﻿")):
        m = md._KEY_LINE.match(line)
        if m and m.group(2):
            keys.setdefault(m.group(1).lower(), []).append(m.group(2))
    return keys


def version_key(version: str) -> tuple[int, ...]:
    """Dot-separated numbers as a comparable tuple; trailing zeros dropped
    so that 1.0 and 1.0.0 are the same version."""
    parts = [int(x) for x in version.split(".")]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


def decode(data: bytes, path: str, result: Result) -> str | None:
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        result.error("Not UTF-8 text.", path)
        return None


class LuaChecker:
    """Compiles Lua source with the Lua 5.4 that lupa bundles (the same one
    OpenSAK runs macros with). load() with mode "t" only compiles, and
    refuses precompiled bytecode."""

    _LINE = re.compile(r"^.*?:(\d+): (.*)$", re.DOTALL)

    def __init__(self) -> None:
        from lupa.lua54 import LuaRuntime
        lua = LuaRuntime(register_eval=False, register_builtins=False)
        self._check = lua.eval(
            "function(src, name) local f, err = load(src, '=' .. name, 't') "
            "if f then return nil end return err end")

    def errors(self, source: str, path: str) -> list[Problem]:
        err = self._check(source, path)
        if err is None:
            return []
        message = str(err)
        m = self._LINE.match(message)
        if m:
            return [Problem(f"Lua syntax error: {m.group(2)}", path, int(m.group(1)))]
        return [Problem(f"Lua syntax error: {message}", path)]


# --- the check ---------------------------------------------------------------

def check_header(md: ModuleType, text: str, path: str, result: Result):
    """Checks the header of the main macro file; returns the parsed
    MacroInfo."""
    info = md.parse_header(text, Path(path))
    keys = header_keys(md, text)

    missing = [KEY_TITLES[k] for k in REQUIRED_KEYS if k not in keys]
    if missing:
        result.error("Header is missing: " + ", ".join(missing)
                     + " (Permissions may be \"none\").", path)

    if "version" in keys and not VERSION.match(info.version):
        result.error(f"Version \"{info.version}\" must be numbers separated "
                     "by dots, e.g. 1.0 or 1.2.3.", path)
    if "requires-api" in keys and info.requires_api_number is None:
        result.error(f"Requires-API \"{info.requires_api}\" must be a number, "
                     "e.g. 3.", path)

    if info.unknown_permissions:
        result.error("Unknown word(s) in Permissions: "
                     + ", ".join(info.unknown_permissions)
                     + ". Allowed: " + ", ".join([*md.PERMISSIONS, md.NO_PERMISSIONS])
                     + ".", path)
    words = {w.lower() for v in keys.get("permissions", [])
             for w in md._LIST_SEPARATOR.split(v) if w}
    if md.NO_PERMISSIONS in words and len(words) > 1:
        result.error("Permissions says \"none\" together with other words; "
                     "use either \"none\" or the words that apply.", path)

    if info.invalid_hosts:
        result.error("Not a host name in Network: " + ", ".join(info.invalid_hosts)
                     + " (write only the host, e.g. api.example.com — no "
                     "https://, path, port or wildcard).", path)
    if info.blocked_hosts:
        result.error("Blocked host in Network: " + ", ".join(info.blocked_hosts)
                     + ". Macros may never contact "
                     + " or ".join(md.BLOCKED_DOMAINS) + ".", path)
    return info


def check(repo: Path, base: str, head: str, md: ModuleType,
          lua: LuaChecker | None = None) -> Result:
    git = Git(repo)
    result = Result()
    changed = git.changed_paths(base, head)

    folders: dict[str, list[str]] = {}
    other: list[str] = []
    for path in changed:
        parts = PurePosixPath(path).parts
        if len(parts) >= 3 and parts[0] == MACROS_DIR:
            folders.setdefault(parts[1], []).append(path)
        else:
            other.append(path)

    if not folders:
        result.review_reasons.append("No macro folder changed (repository files only).")
        return result
    if len(folders) > 1:
        result.error("A pull request may change only one macro folder; this one "
                     "changes " + ", ".join(f"macros/{f}" for f in sorted(folders))
                     + ". Please open one pull request per macro.")
        return result
    if other:
        result.error("A pull request that changes a macro may not change files "
                     "outside its folder: " + ", ".join(sorted(other)) + ".")

    name, folder_changes = next(iter(folders.items()))
    folder = f"{MACROS_DIR}/{name}"
    result.folder = folder
    main = f"{folder}/{name}.lua"

    head_files = git.files_in(head, folder)
    base_files = git.files_in(base, folder)

    if not head_files:
        result.status = "removed"
        result.review_reasons.append("The macro is removed.")
        return result

    result.status = "update" if base_files else "new"
    if result.status == "new":
        result.review_reasons.append("New macro.")

    if not FOLDER_NAME.match(name):
        result.error(f"Folder name \"{name}\" may only contain lowercase "
                     "letters, digits and hyphens, e.g. find-easy-traditionals.",
                     folder)
    if main not in head_files:
        result.error(f"The macro file must be named after its folder: {main}.",
                     folder)
    if f"{folder}/README.md" not in head_files:
        result.error(f"The macro needs a README: {folder}/README.md.", folder)

    if lua is None:
        lua = LuaChecker()
    for path in head_files:
        if not path.lower().endswith(".lua"):
            continue
        data = git.read(head, path)
        text = decode(data or b"", path, result)
        if text is not None:
            result.errors.extend(lua.errors(text, path))

    if main not in head_files:
        return result
    text = decode(git.read(head, main) or b"", main, result)
    if text is None:
        return result
    info = check_header(md, text, main, result)
    result.version_new = info.version

    old_data = git.read(base, main)
    old = None
    if old_data is not None:
        try:
            old = md.parse_header(old_data.decode("utf-8"), Path(main))
        except UnicodeDecodeError:
            old = None
    if old is not None:
        result.version_old = old.version

    lua_changed = any(p.lower().endswith(".lua") for p in folder_changes)
    if (lua_changed and old is not None and VERSION.match(old.version)
            and VERSION.match(info.version)
            and version_key(info.version) <= version_key(old.version)):
        result.error(f"Version must be higher than {old.version} (the version "
                     f"on {MACROS_DIR}/ now) when a .lua file changes; it is "
                     f"{info.version}.", main)

    added = md.added_permissions(old, info) if old is not None else info.declared
    result.added_permissions = list(added)
    if result.status == "update" and added:
        result.review_reasons.append("The update declares more than the current "
                                     "version: " + ", ".join(added) + ".")
    return result


# --- output ------------------------------------------------------------------

def report(result: Result) -> str:
    lines = []
    if result.folder:
        title = {"new": "New macro", "update": "Update", "removed": "Removed"}[result.status]
        lines.append(f"### {title}: `{result.folder}`")
        if result.version_old or result.version_new:
            lines.append(f"Version: {result.version_old or '—'} → {result.version_new or '—'}")
        if result.added_permissions:
            lines.append("Declares beyond the current version: "
                         + ", ".join(f"`{p}`" for p in result.added_permissions))
    else:
        lines.append("### No macro folder changed")
    lines.append("")
    if result.ok:
        lines.append("✅ All checks passed.")
    else:
        lines.append("❌ Problems found:")
        for p in result.errors:
            where = f"`{p.file}{':' + str(p.line) if p.line else ''}`: " if p.file else ""
            lines.append(f"- {where}{p.message}")
    lines.append("")
    if result.requires_review:
        lines.append("👀 Needs review by a maintainer:")
        lines.extend(f"- {r}" for r in result.review_reasons)
    elif result.ok:
        lines.append("🤖 Eligible for automatic merge if the author owns this macro.")
    return "\n".join(lines)


def annotate(result: Result) -> None:
    """GitHub Actions annotations, shown on the pull request's files."""
    for p in result.errors:
        loc = ""
        if p.file:
            loc = f" file={p.file}" + (f",line={p.line}" if p.line else "")
        message = p.message.replace("%", "%25").replace("\n", "%0A")
        print(f"::error{loc}::{message}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--repo", type=Path, default=Path("."))
    parser.add_argument("--base", required=True, help="base commit (main)")
    parser.add_argument("--head", required=True, help="pull request head commit")
    parser.add_argument("--metadata", type=Path, required=True,
                        help="path to OpenSAK's src/opensak/macro/metadata.py")
    parser.add_argument("--json", type=Path, help="write the result here")
    args = parser.parse_args(argv)

    md = load_metadata_module(args.metadata)
    result = check(args.repo, args.base, args.head, md)

    text = report(result)
    print(text)
    if os.environ.get("GITHUB_ACTIONS") == "true":
        annotate(result)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text + "\n")
    if args.json:
        args.json.write_text(json.dumps(result.as_json(), indent=2) + "\n",
                             encoding="utf-8")
    return 0 if result.ok else 1


if __name__ == "__main__":
    sys.exit(main())
