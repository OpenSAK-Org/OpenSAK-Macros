"""
Tests for scripts/check_macro_pr.py.

They need OpenSAK's header parser. In CI the workflow downloads it; locally:

    mkdir -p .tools && curl -fsSL -o .tools/macro_metadata.py \
      https://raw.githubusercontent.com/OpenSAK-Org/OpenSAK/<OPENSAK_REF>/src/opensak/macro/metadata.py
    pip install "lupa>=2.0,<3" pytest
    pytest -v tests/

(<OPENSAK_REF> is the commit in .github/workflows/check.yml.) Set
MACRO_METADATA to use a parser somewhere else.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import check_macro_pr as cm

METADATA = Path(os.environ.get("MACRO_METADATA", ROOT / ".tools" / "macro_metadata.py"))
if not METADATA.is_file():
    pytest.skip(f"OpenSAK header parser not found at {METADATA} (see module docstring)",
                allow_module_level=True)

MD = cm.load_metadata_module(METADATA)
LUA = cm.LuaChecker()


def macro(version="1.0", permissions="none", network=None, body='opensak.log("hi")\n',
          drop=()):
    header = {
        "Name": "Test macro", "Author": "Tester", "Version": version,
        "Requires-API": "3", "Description": "Does a test.", "Permissions": permissions,
    }
    if network is not None:
        header["Network"] = network
    lines = ["-- OpenSAK Macro"] + [f"-- {k}: {v}" for k, v in header.items() if k not in drop]
    return "\n".join(lines) + "\n\n" + body


class Repo:
    def __init__(self, path: Path):
        self.path = path
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "t")
        self.write({"README.md": "repo\n"})
        self.base = self.commit("base")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.path), *args], check=True,
                              capture_output=True, text=True).stdout.strip()

    def write(self, files: dict[str, str | None]):
        for name, content in files.items():
            p = self.path / name
            if content is None:
                p.unlink()
                continue
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content, encoding="utf-8")

    def commit(self, msg="c") -> str:
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", msg)
        return self.git("rev-parse", "HEAD")

    def pr(self, files: dict[str, str | None]) -> cm.Result:
        """Commit *files* on a branch off main and check it against main."""
        self.git("checkout", "-q", "-B", "pr", "main")
        self.write(files)
        head = self.commit("pr")
        self.git("checkout", "-q", "main")
        return cm.check(self.path, "main", head, MD, LUA)

    def merge_to_main(self, files: dict[str, str | None]):
        self.write(files)
        self.commit("main")


@pytest.fixture
def repo(tmp_path):
    return Repo(tmp_path)


def new_macro(name="test-macro", **kw):
    return {f"macros/{name}/{name}.lua": macro(**kw), f"macros/{name}/README.md": "# Test\n"}


def messages(result):
    return " | ".join(p.message for p in result.errors)


# --- new macros --------------------------------------------------------------

def test_valid_new_macro_passes_but_needs_review(repo):
    r = repo.pr(new_macro())
    assert r.ok, messages(r)
    assert r.status == "new"
    assert r.requires_review
    assert r.folder == "macros/test-macro"


def test_missing_header_keys(repo):
    r = repo.pr(new_macro(drop=("Author", "Permissions")))
    assert "Author" in messages(r) and "Permissions" in messages(r)


def test_missing_name_is_caught_although_parser_defaults_it(repo):
    r = repo.pr(new_macro(drop=("Name",)))
    assert "Name" in messages(r)


def test_unknown_permission(repo):
    r = repo.pr(new_macro(permissions="write, internet"))
    assert "internet" in messages(r)


def test_none_with_other_words(repo):
    r = repo.pr(new_macro(permissions="none write"))
    assert "none" in messages(r)


@pytest.mark.parametrize("host", ["geocaching.com", "www.geocaching.com", "coord.info"])
def test_blocked_host(repo, host):
    r = repo.pr(new_macro(network=host))
    assert "Blocked host" in messages(r)


def test_invalid_host(repo):
    r = repo.pr(new_macro(network="https://api.example.com/x"))
    assert "Not a host name" in messages(r)


def test_bad_version_format(repo):
    r = repo.pr(new_macro(version="1.0 beta"))
    assert "numbers separated by dots" in messages(r)


def test_lua_syntax_error_has_line(repo):
    r = repo.pr(new_macro(body="local x = \nif then\n"))
    syntax = [p for p in r.errors if "syntax" in p.message]
    assert syntax and syntax[0].line > 0
    assert syntax[0].file == "macros/test-macro/test-macro.lua"


def test_extra_lua_file_is_syntax_checked(repo):
    files = new_macro()
    files["macros/test-macro/helper.lua"] = "return {\n"
    r = repo.pr(files)
    assert any(p.file.endswith("helper.lua") for p in r.errors)


def test_bad_folder_name(repo):
    r = repo.pr(new_macro(name="Test_Macro"))
    assert "Folder name" in messages(r)


def test_main_file_named_after_folder(repo):
    r = repo.pr({"macros/test-macro/main.lua": macro(),
                 "macros/test-macro/README.md": "x\n"})
    assert "named after its folder" in messages(r)


def test_readme_required(repo):
    r = repo.pr({"macros/test-macro/test-macro.lua": macro()})
    assert "README" in messages(r)


# --- scope -------------------------------------------------------------------

def test_two_folders_rejected(repo):
    files = new_macro("one") | new_macro("two")
    r = repo.pr(files)
    assert "only one macro folder" in messages(r)


def test_macro_plus_repo_file_rejected(repo):
    files = new_macro() | {"README.md": "changed\n"}
    r = repo.pr(files)
    assert "outside its folder" in messages(r)


def test_repo_files_only_needs_review(repo):
    r = repo.pr({"CONTRIBUTING.md": "x\n"})
    assert r.ok and r.status == "none" and r.requires_review


# --- updates -----------------------------------------------------------------

def test_update_without_new_permissions_is_auto_mergeable(repo):
    repo.merge_to_main(new_macro(permissions="write"))
    r = repo.pr({"macros/test-macro/test-macro.lua":
                 macro(version="1.1", permissions="write", body="-- better\n")})
    assert r.ok, messages(r)
    assert r.status == "update"
    assert not r.requires_review
    assert r.added_permissions == []


def test_update_adding_permission_needs_review(repo):
    repo.merge_to_main(new_macro())
    r = repo.pr({"macros/test-macro/test-macro.lua": macro(version="1.1", permissions="write")})
    assert r.ok and r.requires_review
    assert r.added_permissions == ["write"]


def test_update_adding_host_needs_review(repo):
    repo.merge_to_main(new_macro(network="api.example.com"))
    r = repo.pr({"macros/test-macro/test-macro.lua":
                 macro(version="2", network="api.example.com, other.example.org")})
    assert r.ok and r.requires_review
    assert r.added_permissions == ["network:other.example.org"]


@pytest.mark.parametrize("version", ["1.0", "1.0.0", "0.9"])
def test_version_must_increase(repo, version):
    repo.merge_to_main(new_macro())
    r = repo.pr({"macros/test-macro/test-macro.lua": macro(version=version, body="-- x\n")})
    assert "must be higher" in messages(r)


def test_readme_only_change_needs_no_bump(repo):
    repo.merge_to_main(new_macro())
    r = repo.pr({"macros/test-macro/README.md": "# Better docs\n"})
    assert r.ok, messages(r)
    assert not r.requires_review


def test_removed_macro_needs_review(repo):
    repo.merge_to_main(new_macro())
    r = repo.pr({"macros/test-macro/test-macro.lua": None,
                 "macros/test-macro/README.md": None})
    assert r.ok and r.status == "removed" and r.requires_review


def test_version_compares_with_current_main_not_fork_point(repo):
    repo.merge_to_main(new_macro())
    repo.git("checkout", "-q", "-b", "old-fork")
    repo.git("checkout", "-q", "main")
    repo.merge_to_main({"macros/test-macro/test-macro.lua": macro(version="1.5", body="-- y\n")})
    repo.git("checkout", "-q", "old-fork")
    repo.write({"macros/test-macro/test-macro.lua": macro(version="1.2", body="-- z\n")})
    head = repo.commit("stale pr")
    repo.git("checkout", "-q", "main")
    r = cm.check(repo.path, "main", head, MD, LUA)
    assert "higher than 1.5" in messages(r)


def test_template_passes_header_and_syntax():
    text = (ROOT / "template/my-macro/my-macro.lua").read_text(encoding="utf-8")
    result = cm.Result()
    cm.check_header(MD, text, "template/my-macro/my-macro.lua", result)
    result.errors.extend(LUA.errors(text, "my-macro.lua"))
    assert result.ok, messages(result)
