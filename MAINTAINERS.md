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
the commit in `.github/opensak-ref`. When OpenSAK changes the header rules
(new permission words, new keys, new blocked hosts):

1. Put the new OpenSAK commit (ideally a tagged release) in
   `.github/opensak-ref`, with the tag in the comment above it.
2. Open a pull request — "Test checker" runs the tests against the new
   parser.
3. Update the permission table in README.md and CONTRIBUTING.md if words
   were added.

The checker also uses two internal helpers of the parser (`_header_lines`,
`_KEY_LINE`) to see which keys are actually written. If "Test checker"
fails after a bump, look there first.

## Repository settings this relies on

- Ruleset "Protect main" on the default branch: pull request required (0
  approvals, merge commits only), required checks "Check macro" and "Test
  checker", no force pushes or deletion, Organization admin in the bypass
  list.
- Settings → General → Pull Requests → **Allow auto-merge** on.
- Labels `macro problem`, `auto-merge` and `needs review`.
- Discussions on.
