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

If you don't use git, [Sharing a macro with the GitHub website](docs/github-website-guide.md)
shows how to submit and update a macro entirely in the browser.

## The header

The first comment lines of the macro file are its header. All of these are
required in this repository:

| Key | Rule |
|---|---|
| `Name` | Human-readable name |
| `Author` | Your name or nickname |
| `Version` | Numbers separated by dots, e.g. `1.0` or `1.2.3`. Must be higher than the version already in the repository |
| `Description` | One line saying what the macro does |
| `Requires-API` | The lowest macro API version the macro needs, e.g. `4` (in OpenSAK: `opensak.api_version()`) — see [Which OpenSAK version](#which-opensak-version) |
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
Geocaching HQ's sites — `geocaching.com`, `coord.info`, `groundspeak.com`,
`waymarking.com`, `wherigo.com` and related domains — and their
subdomains are not allowed: the Geocaching.com terms of use don't permit
automated access outside their API,
so OpenSAK will never let a macro contact them.

### Which OpenSAK version

Macros in this repository should run on the **stable** OpenSAK release
people have installed, not only on a beta. Each API version needs:

| `Requires-API` | OpenSAK |
|---|---|
| `4` or lower | 1.22.0 or newer — the first stable release with macros |
| `5` | 1.23.0 or newer (in beta until 1.23.0 is released) |

Later API versions only add to the API, so a macro written for API 4 keeps
working in later releases. Declare the **lowest** version your macro really
needs: if it only uses functions API 4 has, write `4` even if you wrote it
on a newer OpenSAK. The Lua API reference (F1 in OpenSAK's macro editor,
or [docs/macros/api.md](https://github.com/OpenSAK-Org/OpenSAK/blob/main/docs/macros/api.md))
says which API version added each function.

Some functions are only in beta builds until a stable release has them;
until v1.23.0 that is `opensak.get_url()` (and so the `Network` header). A
macro that uses one works only for people running a beta.

## Automatic checks

Every pull request is checked automatically. The check fails if:

- a required header key is missing
- `Permissions` contains a word not in the list above
- `Network` contains something that isn't a host name, or a blocked host
- `Version` isn't higher than the version already in the repository
- a `.lua` file isn't valid Lua 5.4
- the pull request changes more than one macro folder
- `Requires-API` is higher than the newest stable OpenSAK release has
  (right now only a warning, until OpenSAK 1.23.0 is released)

It also warns, without failing, when the macro uses a function that is only
in beta builds, or declares `Network` while `opensak.get_url()` is beta-only.

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

## Porting a GSAK macro

Many good OpenSAK macros will start life as a GSAK macro. Macros posted in the
GSAK macro library are public domain, so porting them is allowed — but the
GSAK community has always asked the original author and given them credit, and
we follow that tradition here:

1. **Ask the original author first**, where possible (GSAK forum, Facebook,
   e-mail). Some authors have already given permission for all their macros —
   see [GSAK authors' permissions](docs/gsak-author-permissions.md).
   If you can't reach the author, say so in your pull request.
2. **Credit the original author(s) in the macro's README**, with a line like:

   > This is a port of the GSAK macro *PlacedPQ*, originally written by
   > Lil Devil, Kai Team, lignumaqua and Clyde.

   Link to the original macro on the GSAK forum if you can. A comment line in
   the `.lua` header is a nice extra, but the README is where credit belongs.
3. **`Author` is you** — the person who wrote the OpenSAK version and will
   maintain it.

Your port is published under the MIT License like everything else in this
repository.

## No GitHub account?

Post your macro in the OpenSAK Facebook group or in the OpenSAK thread on
the GSAK forum, and a maintainer can submit it for you. Your name (for
example your geocaching name) goes in the `Author` line. A macro submitted
this way has no GitHub owner, so every later update is reviewed by a
maintainer too.

## Bumping the version

Every change to the `.lua` file needs a higher `Version`. A change to only the
README or example files doesn't — but if in doubt, bump it.

Add a line for the new version to the `## Changes` section of the README,
starting with the version:

```markdown
## Changes

- 1.1 — lists the last 10 runs instead of 5
- 1.0 — first version
```

OpenSAK's Macro manager shows these lines when it offers the update (see
[The macro index](MAINTAINERS.md#the-macro-index)).

## License

By opening a pull request you agree that your contribution is published under
the repository's [MIT License](LICENSE). Only submit code you wrote yourself or
are allowed to publish under that license. For ports of GSAK macros, see
[Porting a GSAK macro](#porting-a-gsak-macro).
