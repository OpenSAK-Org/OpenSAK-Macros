# Export to GDAK

Writes the active OpenSAK database as a database the Android app
GDAK can open, so you can take your caches offline on your phone: logs,
waypoints, corrected coordinates, user notes and attributes included.

GDAK is deprecated and no longer developed, but a number of people still
use it, which is why this export exists.

GDAK has no online functions any more. It works offline on databases copied
from GSAK: one folder per database, holding a `sqlite.db3` in GSAK's
layout. This macro writes that layout (GSAK's table definitions) and fills
only the columns GDAK uses. When GDAK opens the database for the first
time, it adds the few columns of its own.

## What it needs

- OpenSAK with macro API version 4 or newer
- Permissions: `write-files`

The export is the macro's own database (`opensak.macro_db()`), a file
`gdak-export.db3` written next to the macro file. That is outside OpenSAK's
temp folder unless you run the macro from there, so the macro needs
`write-files`. The active database is only read; nothing in it is changed.

The macro's folder must be writable for macros (**Settings → Folder
permissions**, or allow it when OpenSAK asks).

## How to use it

1. Open the database you want to export.
2. Run the macro from **Macros → Macro manager…**.
3. Choose the settings (remembered for the next run):
   - **Only the caches of the active filter**: off exports every cache of
     the database; on exports only the caches the active filter shows.
   - **Logs per cache**: the newest logs to keep per cache. `0` keeps all
     of them. A lower number makes the file a lot smaller.
4. When it is done, the macro output shows the path of `gdak-export.db3`
   and how many rows went into each table.
5. On the phone, create a folder named after the database (for example
   `My caches`) in the folder GDAK uses for databases. Copy the file into
   it and **rename it to `sqlite.db3`**, so you get
   `…/My caches/sqlite.db3`. This is the same layout as a database copied
   from GSAK.
6. Choose the database in GDAK.

Every run replaces the contents of `gdak-export.db3`. To update the copy
on the phone, replace its `sqlite.db3` with the new file. Changes you made
in GDAK to that copy (such as field notes and corrected coordinates) are
lost when you do.

**Keeping the file out of the macros folder:** the file always lands next to
the macro file. To write the export to OpenSAK's temp folder instead, copy
the macro into the temp folder and run it from there. Otherwise the macro
prints a note saying where the file went.

**Without the GUI:** the macro is marked `Headless: yes`, so OpenSAK
versions that can run macros headless can run it from the command line.
Give the settings with `--arg`. With `--yes`, a setting you leave out takes
its remembered value or the default:

```
opensak run gdak-export.lua --db "My database" --arg active_filter=no --arg max_logs=20 --yes
```

- `active_filter`: `no` (default) exports every cache of the database;
  `yes` exports only the caches of the active filter
- `max_logs`: the newest logs kept per cache; `0` (default) keeps all of
  them

**Large databases:** the caches are exported in batches of 2000, with a
progress bar you can cancel. A cancelled export is incomplete, so run the
macro again.

## What is exported

| GSAK table | Filled from |
|---|---|
| `Caches` | cache data, found/DNF/FTF, status, favourite points, user-note flag |
| `CacheMemo` | descriptions, URL, hints, user note |
| `Corrected` | corrected coordinates from the user note |
| `Attributes` | attributes |
| `Logs`, `LogMemo` | logs (all, or the newest *n* per cache) |
| `Waypoints`, `WayMemo` | additional waypoints |
| `CacheImages`, `LogImages` | created, left empty |

Corrected coordinates are stored the way GSAK and GDAK store them. The
cache's coordinates are the corrected ones, with *HasCorrected* set. The
posted coordinates are kept in *LatOriginal*/*LonOriginal* and in the
`Corrected` table.

Not exported: trackables, images, and GSAK-only columns (macro flags, user
sort, user data, colours, lock …). Those columns keep GSAK's defaults.

## How it differs from the GCDroid export

The data is the same. GDAK reads GSAK's original layout, with coordinates
stored as text and no *UserTagColor* column. GCDroid's variant of the layout
stores coordinates as numbers. GDAK also needs the file named `sqlite.db3`
inside a folder named after the database. GCDroid takes any `*.db3` name.

## Changes

- 1.0: first version
