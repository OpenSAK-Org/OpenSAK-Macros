# OptimizePQs

Scans your current DB of caches by hidden_date and returns a list of date ranges that you
use to revise your PQs on geocaching.com.  The revised dates will help you keep your total
number of PQs to the smallest set possible.

This is a port of the gsak PlacedPQ macro, originally written by 
Lil Devil, Kai Team, lignumaqua, Clyde.

## What it needs

- OpenSAK with macro API version 5 or newer
- Permissions: open

 Creates an .html page and opens it in your default web browser upon macro completion.  

## How to use it

1. Run the macro from **Macros → Macro manager…**.
2. Specify how many slots to reserve in each PQ as a buffer to be used by any caches not currently in your DB that might have been unarchived.  This seems reasonably rare, and a value of 10 is suggested as a safe default.  This means your PQs will have dates designed to return no more than 990 caches per PQ - while leaving some extra slots for those unexpected caches.
3. Dates will be formatted as either (e.g.) "November 11, 2026" if "Show dates in geocaching.com format" is checked, otherwise as "m/dd/yyyy".

## Example

A screencap of output can be found in `screenshots/`

## Changes

- 1.0 — first version
- 1.1 — fix typos in README.md
