# OpenSAK Macros

Community-shared Lua macros for [OpenSAK](https://github.com/OpenSAK-Org/OpenSAK),
the open source geocache manager.

Every macro lives in its own folder under [`macros/`](macros/), with the macro
itself, a README explaining what it does, and optionally example files or
screenshots. All macros are reviewed by a maintainer before they are first
published, and every change is checked automatically.

> Macros need an OpenSAK version with macro support (currently in beta).
> Each macro's header says which macro API version it needs (`Requires-API`).
> The Macro manager warns you if your OpenSAK is too old for a macro.

## Using a macro

1. Open the macro's folder under [`macros/`](macros/) and read its README.
2. Download the `.lua` file (on the file page: **Download raw file**).
   If the README mentions extra files, download those too.
3. In OpenSAK, open **Macros → Macro manager… → Open macros folder** and put
   the file(s) there.
4. The macro now shows up in the Macro manager. Select it to see what it
   declares, then run it.

To update a macro, download the new version and replace the old file.

## Before you run a macro: read its declarations

A macro is a small program. The top of every macro file has a header like this:

```lua
-- OpenSAK Macro
-- Name: Find easy traditionals
-- Author: Jane Doe
-- Version: 1.0
-- Requires-API: 3
-- Description: Filters for unfound traditional caches with low difficulty.
-- Permissions: none
```

`Permissions` and `Network` tell you up front what the macro does beyond
reading your caches:

| Permission | What it means |
|---|---|
| `none` | Only reads data and shows results |
| `write` | Changes data in a database |
| `read-files` | Reads files or folders outside the macros folder |
| `write-files` | Writes, moves or deletes files outside OpenSAK's temp folder (exports included) |
| `open` | Opens files in their default app |
| `run-macros` | Runs other macro files |

`Network` lists the web sites the macro contacts, if any.

The declarations are information, not approval. OpenSAK still asks you before
a macro writes to a database, touches a folder, or contacts a web site,
whether the macro declared it or not. If a macro asks for something it didn't
declare, don't approve it, and please report it (see below).

## Problems with a macro?

Open an issue with the **Macro problem** template and include the macro name,
the macro version and your OpenSAK version. Problems with OpenSAK itself
belong in the [OpenSAK repository](https://github.com/OpenSAK-Org/OpenSAK/issues).

Ideas, questions and requests for new macros are welcome in
[Discussions](https://github.com/OpenSAK-Org/OpenSAK-Macros/discussions).

## Sharing your own macro

See [CONTRIBUTING.md](CONTRIBUTING.md). In short: copy [`template/`](template/),
fill in the header and the README, and open a pull request.

## License

Everything in this repository is licensed under the [MIT License](LICENSE).
By contributing a macro you agree to publish it under that license.
