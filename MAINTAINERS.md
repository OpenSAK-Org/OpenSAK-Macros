# Maintainer notes

How pull requests to this repository are handled. Contributor-facing rules
are in [CONTRIBUTING.md](CONTRIBUTING.md).

## How a pull request flows

1. **Check** (`.github/workflows/check.yml`) checks the macro against the
   rules. "Check macro" and "Test checker" are required status checks on
   `main`.
2. **Auto-merge** (`.github/workflows/auto-merge.yml`) decides whether the
   pull request may merge without a maintainer, and labels it:
   - `auto-merge` — the owner's update passed and declares nothing new;
     GitHub merges it when the required checks are green.
   - `needs review` — everything else: new macros, removals, updates that
     declare more, changes by someone who isn't the owner, and changes to
     repository files.

The job summary of both workflows says why.

## Reviewing a new macro

- Does the code do what the README says?
- Do `Permissions` and `Network` match what the code actually does? Look
  for writes, file access, `opensak.open()`, `opensak.run_macro()` and
  `opensak.get_url()`.
- Nothing harmful, obfuscated or unrelated to geocaching.
- No personal data in example files or screenshots.
- Ideally run it once in OpenSAK.

Merge with **Create a merge commit**.

## After merging a new macro: record the owner

Add the macro folder and the GitHub login of the pull request's author to
`.github/macro-owners.json`:

```json
{
  "find-easy-traditionals": ["their-github-login"]
}
```

Commit it to `main` (as a small pull request, or directly with the admin
bypass). Without an entry, every update to the macro waits for review. A
macro you submitted on behalf of someone without a GitHub account gets no
entry.

To hand a macro over to someone else, change its entry.

## Reviewing an update that declares more

The checker's summary lists what is new (e.g. `write` or
`network:api.example.com`). Check that the code really needs it and that
the README explains why.

## Changing the header rules

The checks parse headers with OpenSAK's `src/opensak/macro/metadata.py` from
the commit in `.github/opensak-ref`, together with the `deprecation.py` it
imports (from v1.22.0; OpenSAK keeps that module free of other OpenSAK
imports for this repository's sake). When OpenSAK changes the header rules
(new permission words, new keys, new blocked hosts):

1. Put the new OpenSAK commit (ideally a tagged release) in
   `.github/opensak-ref`, with the tag in the comment above it.
2. Open a pull request — "Test checker" runs the tests against the new
   parser.
3. Update the permission table in README.md and CONTRIBUTING.md if words
   were added.

The checker also uses two internal helpers of the parser (`_header_lines`,
`_KEY_LINE`) to see which keys are actually written. If "Test checker"
fails after a bump, look there first. If it fails with `ModuleNotFoundError`,
`metadata.py` has gained another top-level import: add that file to
`PARSER_FILES` in `check.yml` and `index.yml` (and to the download in
`tests/test_check_macro_pr.py`).

## The macro index

After every push to `main`, **Index** (`.github/workflows/index.yml`) runs
`scripts/build_index.py` and publishes `index.json` on the `index` branch:

    https://raw.githubusercontent.com/OpenSAK-Org/OpenSAK-Macros/index/index.json

OpenSAK's Macro manager reads it to list, install and update macros, so it
doesn't have to walk the repository through the GitHub API. Everything in it
comes from `main`'s git history, so the same commit always gives the same
file; a push that changes nothing in it (e.g. to MAINTAINERS.md) leaves the
`index` branch alone. Run it by hand from the Actions tab ("Run workflow")
after changing the script or `.github/opensak-ref`.

Locally (with the header parser in `.tools/`, see `tests/`):

    python scripts/build_index.py --metadata .tools/opensak/macro/metadata.py --ref main

Format (`schema` 1; fields are only ever added, a breaking change raises
`schema`):

| Field | |
|---|---|
| `schema`, `commit`, `generated` | format version; the `main` commit indexed and its date (UTC) |
| `macros[]` | one entry per folder under `macros/` that has `<folder>/<folder>.lua` |
| `.id`, `.folder`, `.file`, `.readme`, `.page` | folder name, paths in the repository, link to the folder on GitHub |
| `.name`, `.author`, `.version`, `.description`, `.requires_api`, `.permissions`, `.network`, `.headless` | the header, read with OpenSAK's parser (`headless` stays null until OpenSAK's parser has a Headless key; v1.22.0 doesn't) |
| `.files[]` | every file in the folder: `path`, `size`, `sha256`, and a download `url` pinned to `commit` |
| `.versions[]` | every version that was on `main`, newest first: `version`, `published` (date it first reached `main`), `commit`, `requires_api`, `permissions`, `network`, and `size`, `sha256`, `url` of the macro file |
| `.published`, `.updated` | when the first and the current version reached `main` |
| `.changelog[]` | `version` and `text` from the `## Changes` list in the README, newest first |
| `.error` | only when the header couldn't be read |
| `withdrawn[]` | macros that were on `main` and were removed: `id`, `folder`, `name`, `last_version`, `withdrawn` (date), and `versions[]` with the `sha256` of each, so OpenSAK can recognise an installed copy |

Hashes are SHA-256 of the bytes in git, which are the bytes the `url`s
serve. A macro is identified by its folder name, so renaming a folder lists
the old name as withdrawn and the new one as a new macro.

The `index` branch must stay writable by GitHub Actions: don't put it under
the "Protect main" ruleset or any other ruleset that blocks pushes.

## Repository settings this relies on

- Ruleset "Protect main" on the default branch: pull request required (0
  approvals, merge commits only), required checks "Check macro" and "Test
  checker", no force pushes or deletion, Organization admin in the bypass
  list.
- Settings → General → Pull Requests → **Allow auto-merge** on.
- Labels `macro problem`, `auto-merge` and `needs review`.
- Discussions on.
- The `index` branch is created by the first **Index** run and left
  unprotected (see [The macro index](#the-macro-index)).
