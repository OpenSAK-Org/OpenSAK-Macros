"""
Tests for scripts/check_macro_pr.py.

They need OpenSAK's header parser. In CI the workflow fetches the whole
src/opensak folder of the pinned commit (the stable-release check uses
OpenSAK's runtime); locally:

    ref=$(grep -v '^#' .github/opensak-ref | head -n 1 | tr -d '[:space:]')
    git init -q /tmp/opensak-src && cd /tmp/opensak-src
    git remote add origin https://github.com/OpenSAK-Org/OpenSAK
    git sparse-checkout set --no-cone /src/opensak/
    git fetch -q --depth 1 --filter=blob:none origin "$ref" && git checkout -q FETCH_HEAD
    cd - && mkdir -p .tools && cp -r /tmp/opensak-src/src/opensak .tools/opensak
    pip install "lupa>=2.0,<3" "sqlalchemy>=2.0,<2.2" "lxml>=5.0,<7" certifi pytest
    pytest -v tests/

With only metadata.py and deprecation.py in .tools/opensak/macro, the test
of OpenSAK's real stable-release helpers is skipped. Set MACRO_METADATA to
use a parser somewhere else (e.g. an OpenSAK checkout's
src/opensak/macro/metadata.py).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import check_macro_pr as cm

METADATA = Path(os.environ.get("MACRO_METADATA", ROOT / ".tools" / "opensak" / "macro" / "metadata.py"))
if not METADATA.is_file():
    pytest.skip(f"OpenSAK header parser not found at {METADATA} (see module docstring)",
                allow_module_level=True)

MD = cm.load_metadata_module(METADATA)
LUA = cm.LuaChecker()


def macro(version="1.0", permissions="none", network=None, body='opensak.log("hi")\n',
          drop=(), api="3"):
    header = {
        "Name": "Test macro", "Author": "Tester", "Version": version,
        "Requires-API": api, "Description": "Does a test.", "Permissions": permissions,
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

    def pr(self, files: dict[str, str | None], **kw) -> cm.Result:
        """Commit *files* on a branch off main and check it against main;
        *kw* goes to check() (stable, stable_mode)."""
        self.git("checkout", "-q", "-B", "pr", "main")
        self.write(files)
        head = self.commit("pr")
        self.git("checkout", "-q", "main")
        return cm.check(self.path, "main", head, MD, LUA, **kw)

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


# --- removals and the owners file ----------------------------------------------

OWNERS = ".github/macro-owners.json"


def owners(entries: dict[str, list[str]]) -> str:
    return json.dumps(entries, indent=2) + "\n"


REMOVE = {"macros/test-macro/test-macro.lua": None, "macros/test-macro/README.md": None}


def test_removal_with_owner_entry_still_there_fails(repo):
    repo.merge_to_main(new_macro() | {OWNERS: owners({"test-macro": ["a"], "other": ["b"]})})
    r = repo.pr(REMOVE)
    assert r.status == "removed" and not r.ok
    assert 'Also remove the line for "test-macro" from .github/macro-owners.json' in messages(r)


def test_removal_that_removes_its_owner_entry_passes(repo):
    repo.merge_to_main(new_macro() | {OWNERS: owners({"other": ["b"], "test-macro": ["a"]})})
    r = repo.pr(REMOVE | {OWNERS: owners({"other": ["b"]})})
    assert r.ok, messages(r)
    assert r.status == "removed" and r.requires_review
    assert any(OWNERS in reason for reason in r.review_reasons)


def test_removal_of_last_owner_entry_passes(repo):
    repo.merge_to_main(new_macro() | {OWNERS: owners({"test-macro": ["a"]})})
    r = repo.pr(REMOVE | {OWNERS: owners({})})
    assert r.ok, messages(r)


def test_removal_may_not_change_other_owner_entries(repo):
    repo.merge_to_main(new_macro() | {OWNERS: owners({"other": ["b"], "test-macro": ["a"]})})
    r = repo.pr(REMOVE | {OWNERS: owners({"other": ["me"]})})
    assert not r.ok and "this also changes: other" in messages(r)
    r = repo.pr(REMOVE | {OWNERS: owners({"other": ["b"], "mine": ["me"]})})
    assert not r.ok and "this also changes: mine" in messages(r)


def test_removal_editing_owners_but_keeping_its_entry_fails(repo):
    repo.merge_to_main(new_macro() | {OWNERS: owners({"other": ["b"], "test-macro": ["a"]})})
    r = repo.pr(REMOVE | {OWNERS: owners({"test-macro": ["a"]})})
    assert not r.ok and 'Also remove the line for "test-macro"' in messages(r)


def test_removal_without_owner_entry_may_not_touch_owners(repo):
    repo.merge_to_main(new_macro() | {OWNERS: owners({"other": ["b"]})})
    assert repo.pr(REMOVE).ok
    r = repo.pr(REMOVE | {OWNERS: owners({})})
    assert not r.ok and 'no entry for "test-macro"' in messages(r)


def test_removal_with_broken_owners_json_fails(repo):
    repo.merge_to_main(new_macro() | {OWNERS: owners({"test-macro": ["a"]})})
    r = repo.pr(REMOVE | {OWNERS: "{\n"})
    assert not r.ok and "Not valid JSON" in messages(r)


def test_removal_ignores_owner_entries_added_to_main_since(repo):
    repo.merge_to_main(new_macro() | {OWNERS: owners({"test-macro": ["a"]})})
    repo.git("checkout", "-q", "-b", "removal")
    repo.write(REMOVE | {OWNERS: owners({})})
    head = repo.commit("removal")
    repo.git("checkout", "-q", "main")
    repo.merge_to_main({OWNERS: owners({"test-macro": ["a"], "newer": ["c"]})})
    r = cm.check(repo.path, "main", head, MD, LUA)
    assert r.ok, messages(r)


def removal_branch_then_owner_added_to_main(repo, files):
    """A removal branched off main before the macro's owner line was added
    to main (as maintainers do after merging a new macro)."""
    repo.merge_to_main(new_macro() | {OWNERS: owners({"other": ["b"]})})
    repo.git("checkout", "-q", "-b", "removal")
    repo.write(REMOVE | files)
    head = repo.commit("removal")
    repo.git("checkout", "-q", "main")
    repo.merge_to_main({OWNERS: owners({"other": ["b"], "test-macro": ["a"]})})
    return cm.check(repo.path, "main", head, MD, LUA)


def test_removal_of_entry_added_to_main_since_says_update_branch(repo):
    r = removal_branch_then_owner_added_to_main(repo, {})
    assert not r.ok
    assert "Update the branch from main first" in messages(r)
    assert "Also remove the line" not in messages(r)


def test_removal_touching_owners_with_entry_added_to_main_since(repo):
    r = removal_branch_then_owner_added_to_main(
        repo, {OWNERS: owners({"other": ["b"], "mine": ["me"]})})
    assert not r.ok
    assert "Update the branch from main first" in messages(r)


def test_removal_after_updating_branch_from_main_passes(repo):
    repo.merge_to_main(new_macro() | {OWNERS: owners({"other": ["b"]})})
    repo.git("checkout", "-q", "-b", "removal")
    repo.write(REMOVE)
    repo.commit("removal")
    repo.git("checkout", "-q", "main")
    repo.merge_to_main({OWNERS: owners({"other": ["b"], "test-macro": ["a"]})})
    repo.git("checkout", "-q", "removal")
    repo.git("merge", "-q", "--no-edit", "main")
    repo.write({OWNERS: owners({"other": ["b"]})})
    head = repo.commit("remove owner line")
    repo.git("checkout", "-q", "main")
    r = cm.check(repo.path, "main", head, MD, LUA)
    assert r.ok, messages(r)


def test_update_may_not_touch_owners(repo):
    repo.merge_to_main(new_macro() | {OWNERS: owners({"test-macro": ["a"]})})
    r = repo.pr({"macros/test-macro/README.md": "# Better\n",
                 OWNERS: owners({"test-macro": ["a", "me"]})})
    assert "outside its folder" in messages(r)


def test_new_macro_may_not_add_its_owner(repo):
    r = repo.pr(new_macro() | {OWNERS: owners({"test-macro": ["me"]})})
    assert "outside its folder" in messages(r)


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


# --- against the stable release ------------------------------------------------
#
# With a Stable made here, as OpenSAK v1.22.0's helpers report it: API 4, and
# opensak.get_url() beta-only. The real helpers need OpenSAK's runtime; the
# last test uses them when a whole src/opensak tree is around the parser.

def _find_get_url(text):
    return [(n, "opensak.get_url is only available in beta builds (feature "
                "flag lua-macro-net), not in stable releases")
            for n, line in enumerate(text.splitlines(), 1)
            if "opensak.get_url" in line.split("--", 1)[0]]


V1_22 = cm.Stable(api=4, opensak_version="1.22.0",
                  beta_only_names=("opensak.get_url",), find_beta_only=_find_get_url)
V1_23 = cm.Stable(api=5, opensak_version="1.23.0", beta_only_names=(),
                  find_beta_only=lambda text: [])


def warnings(result):
    return " | ".join(p.message for p in result.warnings)


def test_stable_checks_off_by_default(repo):
    r = repo.pr(new_macro(api="9"), stable=V1_22)
    assert r.ok and not r.warnings and r.stable_api is None


def test_requires_api_above_stable_fails_in_error_mode(repo):
    r = repo.pr(new_macro(api="5"), stable=V1_22, stable_mode="error")
    assert not r.ok
    assert "Requires-API is 5" in messages(r)
    assert "macro API 4 (OpenSAK 1.22.0)" in messages(r)
    assert r.stable_api == 4


def test_requires_api_above_stable_is_a_warning_in_warn_mode(repo):
    r = repo.pr(new_macro(api="5"), stable=V1_22, stable_mode="warn")
    assert r.ok, messages(r)
    assert "Requires-API is 5" in warnings(r)
    assert "becomes an error" in warnings(r)


@pytest.mark.parametrize("api", ["3", "4"])
def test_requires_api_up_to_stable_passes(repo, api):
    r = repo.pr(new_macro(api=api), stable=V1_22, stable_mode="error")
    assert r.ok and not r.warnings, messages(r) + warnings(r)


def test_get_url_is_flagged_as_beta_only(repo):
    body = 'local page = opensak.get_url("https://example.com/")\n-- opensak.get_url in a comment\n'
    r = repo.pr(new_macro(body=body, network="example.com"),
                stable=V1_22, stable_mode="error")
    assert r.ok, messages(r)      # a warning, not an error
    flagged = [p for p in r.warnings if "get_url" in p.message and p.line]
    assert [(p.file, p.line) for p in flagged] == [("macros/test-macro/test-macro.lua", 10)]
    assert "Network declares web sites" in warnings(r)
    assert r.beta_only == ["opensak.get_url", "Network"]


def test_nothing_beta_only_once_get_url_is_stable(repo):
    body = 'local page = opensak.get_url("https://example.com/")\n'
    r = repo.pr(new_macro(api="5", body=body, network="example.com"),
                stable=V1_23, stable_mode="error")
    assert r.ok and not r.warnings, messages(r) + warnings(r)
    assert r.beta_only == []


def test_stable_check_that_cannot_load(repo, monkeypatch):
    def broken(md):
        raise ModuleNotFoundError("No module named 'sqlalchemy'")
    monkeypatch.setattr(cm, "load_stable", broken)
    r = repo.pr(new_macro(), stable_mode="warn")
    assert r.ok and "sqlalchemy" in warnings(r)
    r = repo.pr(new_macro(), stable_mode="error")
    assert not r.ok and "sqlalchemy" in messages(r)


def test_report_and_json_show_warnings(repo):
    r = repo.pr(new_macro(api="5"), stable=V1_22, stable_mode="warn")
    text = cm.report(r)
    assert "Checked against the stable release: macro API 4" in text
    assert "⚠️ Warnings" in text and "Requires-API is 5" in text
    data = r.as_json()
    assert data["ok"] and data["stable_api"] == 4 and data["warnings"]


def test_real_helpers_of_the_pinned_opensak():
    """OpenSAK's own helpers, when the whole src/opensak tree of the pinned
    commit is around the parser and its dependencies are installed (as in
    the Check macro job)."""
    if not (METADATA.parent / "runtime.py").is_file():
        pytest.skip("only metadata.py is here, not OpenSAK's whole src/opensak tree")
    stable = cm.load_stable(MD)
    assert stable.api >= 4
    assert stable.opensak_version != "?"
