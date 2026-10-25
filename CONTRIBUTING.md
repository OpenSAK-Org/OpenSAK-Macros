# Contributing a macro

Thanks for sharing your work! This page explains how a macro is laid out, what
the automatic checks look for, and how review works.

## Folder layout

One macro = one folder under `macros/`:

```
macros/
└── find-easy-traditionals/
    ├── find-easy-traditionals.lua   ← the macro (required)
    ├── README.md                    ← what it does, how to use it (required)
    ├── examples/                    ← example input/output files (optional)
    └── screenshots/                 ← images used by the README (optional)
```

- The folder name uses lowercase letters, digits and hyphens only
  (`find-easy-traditionals`, not `Find Easy Traditionals`).
- The macro file has the same name as the folder, plus `.lua`.
- Other `.lua` files in the folder are allowed (e.g. a helper the macro runs
  with `opensak.run_macro()`); they must also be valid Lua.
- Keep example files small, and never include real personal data — no
  account names, home coordinates, log texts or databases of your own.

The quickest start is to copy [`template/my-macro/`](template/my-macro/),
rename the folder and the `.lua` file, and fill them in.

## The header

The first comment lines of the macro file are its header. All of these are
required in this repository:

| Key | Rule |
|---|---|
| `Name` | Human-readable name |
| `Author` | Your name or nickname |
| `Version` | Numbers separated by dots, e.g. `1.0` or `1.2.3`. Must be higher than the version already in the repository |
| `Description` | One line saying what the macro does |
| `Requires-API` | The macro API version the macro needs, e.g. `3` (in OpenSAK: `opensak.api_version()`) |
| `Permissions` | What the macro does beyond reading — see below. Write `none` if it needs nothing |
| `Network` | Only if the macro contacts web sites: the host names, comma-separated |

### Permissions

Use only these words, separated by commas or spaces:

| Word | Declare it when the macro… |
|---|---|
| `write` | changes data in a database (write API, `create_database()`, `copy_caches()`, `move_caches()`) |
| `read-files` | reads files or folders outside the macros folder and OpenSAK's temp folder (a file the user picks in `choose_file()` doesn't count) |
| `write-files` | writes, copies, moves or deletes files or folders outside OpenSAK's temp folder, exports included |
| `open` | opens files in their default app with `opensak.open()` |
| `run-macros` | runs other macro files with `opensak.run_macro()` |
| `none` | needs none of the above |

Declare everything the macro can do, not just what it usually does.

### Network

List plain host names (or IP addresses): `api.example.com`, not
`https://api.example.com/path`, no ports and no wildcards.
`geocaching.com`, `coord.info` and their subdomains are not allowed — the
Geocaching.com terms of use don't permit automated access outside their API,
so OpenSAK will never let a macro contact them.

## Automatic checks

Every pull request is checked automatically. The check fails if:

- a required header key is missing
- `Permissions` contains a word not in the list above
- `Network` contains something that isn't a host name, or a blocked host
- `Version` isn't higher than the version already in the repository
- a `.lua` file isn't valid Lua 5.4
- the pull request changes more than one macro folder

One macro per pull request keeps review simple. To submit two macros, open two
pull requests.

## Review and merging

**A new macro** is always reviewed by a maintainer before it is merged. The
review checks that the macro does what its README says, that the declarations
match what the code does, and that nothing in it is harmful.

**An update to your own macro** is merged automatically when the checks are
green and the update doesn't declare anything new — no new permission and no
new host. The GitHub account that opened the pull request adding the macro
becomes its owner; a maintainer records this in `.github/macro-owners.json`
when the macro is merged. You can't add yourself there in your own pull
request.

**An update that declares more** (a new permission or a new host), or a
change to someone else's macro, is reviewed by a maintainer.

If you want to improve someone else's macro, it's good practice to talk to the
owner first in an issue or in Discussions.

## No GitHub account?

Post your macro in the OpenSAK Facebook group or in the OpenSAK thread on
the GSAK forum, and a maintainer can submit it for you. Your name (for
example your geocaching name) goes in the `Author` line. A macro submitted
this way has no GitHub owner, so every later update is reviewed by a
maintainer too.

## Bumping the version

Every change to the `.lua` file needs a higher `Version`. A change to only the
README or example files doesn't — but if in doubt, bump it.

## License

By opening a pull request you agree that your contribution is published under
the repository's [MIT License](LICENSE). Only submit code you wrote yourself or
are allowed to publish under that license.
