# New since last run

Shows the unfound caches that a GPX or pocket query import has added or
updated since you last ran the macro, so after loading your weekly pocket
queries you see the new ones straight away.

## What it needs

- OpenSAK with macro API version 3 or newer
- Permissions: none

The macro only reads caches and sets a filter. It remembers the time of its
last runs in its own macro settings, which OpenSAK keeps across restarts.

## How to use it

1. Run the macro once from **Macros → Macro manager…**. The first run only
   notes the current time.
2. Import your GPX files or pocket queries as usual.
3. Run the macro again. It filters the unfound caches updated since the
   previous run (the filter is labelled "New since … UTC") and prints how
   many there are.
4. Each run also lists the last 5 runs with their time and count.

Times are in UTC, like the import time OpenSAK stores for each cache.

To start over, open the macro, set `RESET = true` at the top, run it once,
and set it back to `false`. To keep more or fewer runs in the list, change
`RUNS_KEPT`.

## Changes

- 1.0 — first version
