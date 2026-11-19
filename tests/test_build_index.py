"""
Tests for scripts/build_index.py.

They need OpenSAK's header parser, like tests/test_check_macro_pr.py (see
there how to get it locally). Set MACRO_METADATA to use one somewhere else.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import build_index as bi

METADATA = Path(os.environ.get("MACRO_METADATA", ROOT / ".tools" / "macro_metadata.py"))
if not METADATA.is_file():
    pytest.skip(f"OpenSAK header parser not found at {METADATA} (see "
                "tests/test_check_macro_pr.py)", allow_module_level=True)

MD = bi.load_metadata_module(METADATA)
REPO = "Example/Macros"


def macro(version="1.0", permissions="none", network=None, api="3", name="Test macro",
          body='opensak.log("hi")\n'):
    header = {"Name": name, "Author": "Tester", "Version": version,
              "Requires-API": api, "Description": "Does a test.",
              "Permissions": permissions}
    if network is not None:
        header["Network"] = network
    lines = ["-- OpenSAK Macro"] + [f"-- {k}: {v}" for k, v in header.items()]
    return "\n".join(lines) + "\n\n" + body


def readme(*changes: str) -> str:
    return "# Test\n\nWhat it does.\n\n## Changes\n\n" + "".join(
        f"{c}\n" for c in changes) + "\n## License\n\n- 9.9 — not a change\n"


class Repo:
    """A repository whose main gets one merge commit per publish(), like
    pull requests merged with "Create a merge commit"."""

    def __init__(self, path: Path):
        self.path = path
        self.n = 0
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "t")
        self.git("config", "core.autocrlf", "false")
        self.write({"README.md": "repo\n"})
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "base")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.path), *args], check=True,
                              capture_output=True, text=True).stdout.strip()

    def write(self, files: dict[str, str | bytes | None]):
        for name, content in files.items():
            p = self.path / name
            if content is None:
                p.unlink()
                continue
            p.parent.mkdir(parents=True, exist_ok=True)
            if isinstance(content, bytes):
                p.write_bytes(content)
            else:
                p.write_bytes(content.encode("utf-8"))

    def publish(self, files: dict[str, str | bytes | None]) -> str:
        """Commit *files* on a branch and merge it into main with --no-ff;
        returns the merge commit."""
        self.n += 1
        when = f"2026-01-{self.n:02d}T12:00:00+01:00"
        env = {**os.environ, "GIT_AUTHOR_DATE": when, "GIT_COMMITTER_DATE": when}
        self.git("checkout", "-q", "-B", "pr", "main")
        self.write(files)
        self.git("add", "-A")
        subprocess.run(["git", "-C", str(self.path), "commit", "-q", "-m", "pr"],
                       check=True, capture_output=True, env=env)
        self.git("checkout", "-q", "main")
        subprocess.run(["git", "-C", str(self.path), "merge", "-q", "--no-ff",
                        "-m", f"Merge {self.n}", "pr"],
                       check=True, capture_output=True, env=env)
        return self.git("rev-parse", "HEAD")

    def index(self) -> dict:
        return bi.build(self.path, "main", MD, REPO)


@pytest.fixture
def repo(tmp_path):
    return Repo(tmp_path)


def by_id(index: dict) -> dict[str, dict]:
    return {m["id"]: m for m in index["macros"]}


def test_lists_header_files_and_hashes(repo):
    lua = macro(permissions="write-files", network="api.example.com")
    head = repo.publish({"macros/a/a.lua": lua, "macros/a/README.md": readme(),
                         "macros/a/screenshots/x.png": b"\x89PNG\r\n\0"})
    index = repo.index()
    assert index["schema"] == bi.SCHEMA
    assert index["commit"] == head
    assert index["repository"] == f"https://github.com/{REPO}"
    m = by_id(index)["a"]
    assert (m["name"], m["author"], m["version"], m["requires_api"]) == \
        ("Test macro", "Tester", "1.0", 3)
    assert m["permissions"] == ["write-files"]
    assert m["network"] == ["api.example.com"]
    assert m["file"] == "macros/a/a.lua"
    assert m["readme"] == "macros/a/README.md"
    files = {f["path"]: f for f in m["files"]}
    assert set(files) == {"macros/a/a.lua", "macros/a/README.md",
                          "macros/a/screenshots/x.png"}
    png = files["macros/a/screenshots/x.png"]
    assert png["size"] == 7
    assert png["sha256"] == hashlib.sha256(b"\x89PNG\r\n\0").hexdigest()
    assert png["url"] == (f"https://raw.githubusercontent.com/{REPO}/{head}/"
                          "macros/a/screenshots/x.png")


def test_hash_is_of_the_bytes_in_git(repo):
    lua = macro().replace("\n", "\r\n")
    repo.publish({"macros/a/a.lua": lua, "macros/a/README.md": readme()})
    f = by_id(repo.index())["a"]["files"]
    main = next(x for x in f if x["path"] == "macros/a/a.lua")
    assert main["sha256"] == hashlib.sha256(lua.encode()).hexdigest()
    assert main["size"] == len(lua.encode())


def test_permissions_none(repo):
    repo.publish({"macros/a/a.lua": macro(), "macros/a/README.md": readme()})
    assert by_id(repo.index())["a"]["permissions"] == ["none"]


def test_versions_newest_first_with_publish_dates(repo):
    first = repo.publish({"macros/a/a.lua": macro("1.0"), "macros/a/README.md": readme()})
    repo.publish({"macros/a/README.md": readme("- 1.0 — first")})   # README only
    second = repo.publish({"macros/a/a.lua": macro("1.1", api="4")})
    m = by_id(repo.index())["a"]
    assert [v["version"] for v in m["versions"]] == ["1.1", "1.0"]
    new, old = m["versions"]
    assert new["commit"] == second and old["commit"] == first
    assert new["requires_api"] == 4 and old["requires_api"] == 3
    assert old["sha256"] == hashlib.sha256(macro("1.0").encode()).hexdigest()
    assert old["url"].endswith(f"/{first}/macros/a/a.lua")
    assert old["published"] == "2026-01-01T11:00:00Z"
    assert new["published"] == "2026-01-03T11:00:00Z"
    assert (m["published"], m["updated"]) == (old["published"], new["published"])


def test_same_version_republished_keeps_first_date_and_newest_bytes(repo):
    repo.publish({"macros/a/a.lua": macro("1.0"), "macros/a/README.md": readme()})
    fix = macro("1.0.0", body="-- fixed\n")
    last = repo.publish({"macros/a/a.lua": fix})
    (only,) = by_id(repo.index())["a"]["versions"]
    assert only["commit"] == last
    assert only["sha256"] == hashlib.sha256(fix.encode()).hexdigest()
    assert only["published"] == "2026-01-01T11:00:00Z"


def test_changelog_from_readme(repo):
    text = readme("- 1.0 — first version",
                  "- 1.10 – longer list",
                  "\t\tand a second line",
                  "- 1.2: fix",
                  "- not a version",
                  "* v2.0 (2026-02-01) - big one")
    repo.publish({"macros/a/a.lua": macro(), "macros/a/README.md": text})
    assert by_id(repo.index())["a"]["changelog"] == [
        {"version": "2.0", "text": "big one"},
        {"version": "1.10", "text": "longer list and a second line"},
        {"version": "1.2", "text": "fix"},
        {"version": "1.0", "text": "first version"},
    ]


def test_no_changes_section(repo):
    repo.publish({"macros/a/a.lua": macro(), "macros/a/README.md": "# A\n\n- 1.0 — x\n"})
    assert by_id(repo.index())["a"]["changelog"] == []


def test_folder_without_macro_file_is_skipped(repo):
    repo.publish({"macros/a/other.lua": macro(), "macros/a/README.md": readme()})
    index = repo.index()
    assert index["macros"] == [] and index["withdrawn"] == []


def test_withdrawn_macro(repo):
    repo.publish({"macros/a/a.lua": macro("1.0", name="Old one"),
                  "macros/a/README.md": readme()})
    repo.publish({"macros/a/a.lua": macro("1.1", name="Old one")})
    repo.publish({"macros/b/b.lua": macro(), "macros/b/README.md": readme()})
    repo.publish({"macros/a/a.lua": None, "macros/a/README.md": None})
    index = repo.index()
    assert [m["id"] for m in index["macros"]] == ["b"]
    (w,) = index["withdrawn"]
    assert (w["id"], w["name"], w["last_version"]) == ("a", "Old one", "1.1")
    assert w["withdrawn"] == "2026-01-04T11:00:00Z"
    assert [v["version"] for v in w["versions"]] == ["1.1", "1.0"]
    assert w["versions"][1]["sha256"] == hashlib.sha256(
        macro("1.0", name="Old one").encode()).hexdigest()


def test_macro_back_after_withdrawal_is_listed_not_withdrawn(repo):
    repo.publish({"macros/a/a.lua": macro("1.0"), "macros/a/README.md": readme()})
    repo.publish({"macros/a/a.lua": None, "macros/a/README.md": None})
    repo.publish({"macros/a/a.lua": macro("2.0"), "macros/a/README.md": readme()})
    index = repo.index()
    assert index["withdrawn"] == []
    assert [v["version"] for v in by_id(index)["a"]["versions"]] == ["2.0", "1.0"]


def test_unreadable_header_is_listed_with_error(repo):
    repo.publish({"macros/a/a.lua": b"\xff\xfe-- broken\n", "macros/a/README.md": readme()})
    assert by_id(repo.index())["a"]["error"] == "not UTF-8 text"


def test_same_commit_gives_same_file(repo, tmp_path):
    repo.publish({"macros/a/a.lua": macro(), "macros/a/README.md": readme()})
    out1, out2 = tmp_path / "1.json", tmp_path / "2.json"
    for out in (out1, out2):
        assert bi.main(["--repo", str(repo.path), "--ref", "main", "--metadata",
                        str(METADATA), "--repository", REPO,
                        "--output", str(out)]) == 0
    assert out1.read_bytes() == out2.read_bytes()
    assert json.loads(out1.read_text(encoding="utf-8"))["macros"][0]["id"] == "a"


def test_this_repository(tmp_path):
    """The real repository builds, and every listed file hashes to what git
    stores."""
    if not (ROOT / ".git").exists():
        pytest.skip("not a git checkout")
    index = bi.build(ROOT, "HEAD", MD)
    git = bi.Git(ROOT)
    for m in index["macros"]:
        assert "error" not in m, m["id"]
        assert m["versions"], m["id"]
        for f in m["files"]:
            data = git.read(index["commit"], f["path"])
            assert data is not None
            assert hashlib.sha256(data).hexdigest() == f["sha256"]
