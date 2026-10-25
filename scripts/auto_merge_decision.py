"""
scripts/auto_merge_decision.py — decides whether a pull request may be
merged without a maintainer.

Run by .github/workflows/auto-merge.yml after scripts/check_macro_pr.py has
checked the pull request with the checker from main. A pull request is
eligible only if all of these hold:

  - the check passed
  - it updates an existing macro (not a new or removed one)
  - the update declares nothing beyond the current version (no new
    permission, no new host)
  - its author owns the macro in .github/macro-owners.json on main
  - it is not a draft

The checker already makes sure the pull request changes nothing outside the
macro folder. The owners file is read from main, so a pull request can't
make its author an owner.

Prints the decision, writes it to the job summary, and sets
eligible=true|false in $GITHUB_OUTPUT. The exit code is 0 either way; a
pull request that isn't eligible simply waits for a maintainer.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

OWNERS_FILE = ".github/macro-owners.json"


@dataclass
class Decision:
    eligible: bool = False
    reasons: list[str] = field(default_factory=list)


def load_owners(path: Path) -> dict[str, list[str]]:
    """Macro folder name -> GitHub logins (lower-cased). A missing file
    means nobody owns anything."""
    if not path.is_file():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise TypeError(f"{path} must be a JSON object")
    owners: dict[str, list[str]] = {}
    for folder, logins in data.items():
        if not isinstance(logins, list) or not all(isinstance(x, str) for x in logins):
            raise TypeError(f"{path}: \"{folder}\" must map to a list of GitHub logins")
        owners[folder] = [x.lower() for x in logins]
    return owners


def decide(check: dict, owners: dict[str, list[str]], author: str,
           draft: bool) -> Decision:
    d = Decision()
    folder = check.get("folder") or ""
    name = folder.split("/", 1)[1] if folder.startswith("macros/") else ""

    if not check.get("ok"):
        d.reasons.append("The check found problems.")
    if check.get("status") != "update":
        d.reasons.append({"new": "New macros are always reviewed.",
                          "removed": "Removing a macro is always reviewed.",
                          }.get(check.get("status", ""), "No macro folder changed."))
    elif check.get("added_permissions"):
        d.reasons.append("The update declares more than the current version: "
                         + ", ".join(check["added_permissions"]) + ".")
    if name and author.lower() not in [x.lower() for x in owners.get(name, [])]:
        if name in owners:
            d.reasons.append(f"@{author} is not an owner of {folder}.")
        else:
            d.reasons.append(f"{folder} has no owner in {OWNERS_FILE}.")
    if draft:
        d.reasons.append("The pull request is a draft.")

    d.eligible = not d.reasons
    return d


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", type=Path, required=True,
                        help="JSON result of check_macro_pr.py")
    parser.add_argument("--owners", type=Path, default=Path(OWNERS_FILE))
    parser.add_argument("--author", required=True, help="pull request author login")
    parser.add_argument("--draft", default="false", help="true if the pull request is a draft")
    args = parser.parse_args(argv)

    try:
        check = json.loads(args.check.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        check = {"ok": False}
    d = decide(check, load_owners(args.owners), args.author,
               args.draft.lower() == "true")

    if d.eligible:
        text = "🤖 **Automatic merge:** the owner's update passed all checks and " \
               "declares nothing new. It is merged as soon as the required checks are green."
    else:
        text = "👀 **Waiting for a maintainer:**\n" + "\n".join(f"- {r}" for r in d.reasons)
    print(text)

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("\n" + text + "\n")
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as f:
            f.write(f"eligible={'true' if d.eligible else 'false'}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
