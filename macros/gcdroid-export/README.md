# Export to GCDroid

Writes the active OpenSAK database as a database that the Android app
GCDroid can open
or merge, so you can take your caches offline on your phone — logs,
waypoints, corrected coordinates, user notes and attributes included.

GCDroid has no database format of its own: it reads GSAK's `sqlite.db3`.
This macro builds that layout (GCDroid 2.3.1's table definitions, which are
GSAK's with a few small differences) and fills only the columns GCDroid uses.

## What it needs

- OpenSAK with macro API version 3 or newer
- Permissions: `write-files`

The export is the macro's own database (`opensak.macro_db()`), a file
`gcdroid-export.db3` written next to the macro file — outside OpenSAK's temp
folder unless you run the macro from there, hence `write-files`. The active
database is only read; nothing in it is changed.

The macro's folder must be writable for macros (**Settings → Folder
permissions**, or allow it when OpenSAK asks).

## How to use it

1. Open the database you want to export.
2. Run the macro from **Macros → Macro manager…**.
3. Choose the settings (remembered for the next run):
   - **Only the caches of the active filter** — off: every cache of the
     database; on: only the caches the active filter shows.
   - **Logs per cache** — the newest logs to keep per cache; `0` keeps all
     of them. A lower number makes the file a lot smaller.
4. When it is done, the macro output shows the path of `gcdroid-export.db3`
   and how many rows went into each table.
5. Copy the file to your phone into one of GCDroid's database folders (or
   let GCDroid merge it into an existing database). You may rename it;
   GCDroid accepts any `*.db3` name.

Every run replaces the contents of `gcdroid-export.db3`.

**Keeping the file out of the macros folder:** the file always lands next to
the macro file. Copy the macro into OpenSAK's temp folder and run it from
there to write the export to the temp folder instead; otherwise the macro
prints a note saying where the file went.

**Without the GUI:** the macro is marked `Headless: yes` and can run from
OpenSAK's command line, in OpenSAK versions that support running macros
headless. Give the settings with `--arg` (with `--yes`, a setting not given
takes its remembered value or the default):

```
opensak run gcdroid-export.lua --db "My database" --arg active_filter=no --arg max_logs=20 --yes
```

- `active_filter` — `no` (default): every cache of the database; `yes`: only
  the caches of the active filter
- `max_logs` — newest logs kept per cache; `0` (default) keeps all of them

For a scheduled export that stays out of the macros folder, copy the macro
to OpenSAK's temp folder and run that copy; then copy
`gcdroid-export.db3` from the temp folder to wherever you sync your phone.

**Large databases:** the caches are exported in batches of 2000, with a
progress bar you can cancel. A cancelled export is incomplete — run the
macro again.

## What is exported

| GCDroid / GSAK table | Filled from |
|---|---|
| `Caches` | cache data, found/DNF/FTF, status, favourite points, user-note flag |
| `CacheMemo` | descriptions, URL, hints, user note |
| `Corrected` | corrected coordinates from the user note |
| `Attributes` | attributes |
| `Logs`, `LogMemo` | logs (all, or the newest *n* per cache) |
| `Waypoints`, `WayMemo` | additional waypoints |
| `CacheImages`, `LogImages` | created, left empty |

Corrected coordinates are stored the GSAK way: the cache's coordinates are
the corrected ones with *HasCorrected* set, and the posted coordinates are
kept in the `Corrected` table.

Not exported: trackables, images, and GSAK-only columns (macro flags, user
sort, user data, colours, lock …), which keep GSAK's defaults.

## Changes

- 1.0 — first version
