"""Tests for scripts/auto_merge_decision.py and .github/macro-owners.json."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import auto_merge_decision as am

OWNERS = {"test-macro": ["alice"]}


def update(**kw):
    check = {"ok": True, "status": "update", "folder": "macros/test-macro",
             "added_permissions": []}
    check.update(kw)
    return check


def test_owner_update_is_eligible():
    assert am.decide(update(), OWNERS, "alice", draft=False).eligible


def test_owner_login_is_case_insensitive():
    assert am.decide(update(), {"test-macro": ["Alice"]}, "ALICE", draft=False).eligible


def test_other_author_not_eligible():
    d = am.decide(update(), OWNERS, "mallory", draft=False)
    assert not d.eligible and "not an owner" in d.reasons[0]


def test_macro_without_owner_not_eligible():
    d = am.decide(update(), {}, "alice", draft=False)
    assert not d.eligible and "no owner" in d.reasons[0]


@pytest.mark.parametrize("status", ["new", "removed", "none"])
def test_only_updates_are_eligible(status):
    assert not am.decide(update(status=status), OWNERS, "alice", draft=False).eligible


def test_added_permissions_not_eligible():
    d = am.decide(update(added_permissions=["write"]), OWNERS, "alice", draft=False)
    assert not d.eligible and "write" in d.reasons[0]


def test_failed_check_not_eligible():
    assert not am.decide(update(ok=False), OWNERS, "alice", draft=False).eligible


def test_draft_not_eligible():
    assert not am.decide(update(), OWNERS, "alice", draft=True).eligible


def test_cli_writes_github_output(tmp_path, monkeypatch):
    check = tmp_path / "check.json"
    check.write_text(json.dumps(update()))
    owners = tmp_path / "owners.json"
    owners.write_text(json.dumps(OWNERS))
    out = tmp_path / "out"
    monkeypatch.setenv("GITHUB_OUTPUT", str(out))
    monkeypatch.delenv("GITHUB_STEP_SUMMARY", raising=False)
    am.main(["--check", str(check), "--owners", str(owners), "--author", "alice"])
    assert out.read_text() == "eligible=true\n"


def test_cli_missing_check_result_is_not_eligible(tmp_path, monkeypatch):
    out = tmp_path / "out"
    monkeypatch.setenv("GITHUB_OUTPUT", str(out))
    monkeypatch.delenv("GITHUB_STEP_SUMMARY", raising=False)
    am.main(["--check", str(tmp_path / "missing.json"),
             "--owners", str(tmp_path / "none.json"), "--author", "alice"])
    assert out.read_text() == "eligible=false\n"


# --- the owners file in the repository ---------------------------------------

LOGIN = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$")


def test_owners_file_is_valid():
    owners = am.load_owners(ROOT / am.OWNERS_FILE)
    tracked = subprocess.run(["git", "-C", str(ROOT), "ls-files", "macros"],
                             capture_output=True, text=True, check=False).stdout.split()
    folders = {Path(p).parts[1] for p in tracked if len(Path(p).parts) >= 3}
    for folder, logins in owners.items():
        assert folder in folders or not tracked, f"owner entry for missing macro {folder}"
        assert logins, f"{folder} has an empty owner list"
        for login in logins:
            assert LOGIN.match(login), f"{folder}: \"{login}\" is not a GitHub login"
