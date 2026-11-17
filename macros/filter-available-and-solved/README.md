# filter-available-and-solved

Filter the current view for available, unfound, non-owned caches, excluding unsolved Mystery/Unknown caches.

This is a port of the GSAK FilterAvailableAndSolved macro, originally written by 
Kai Team.  Porting was done via Google Gemini AI.

## What it needs

- OpenSAK with macro API version 4 or newer
- Permissions: none

## How to use it

1. Run the macro from **Macros → Macro manager…**.

## Example

This macro will narrow your current filter (i.e. it adds additional criteria to your current filter).  If you want it to operate across the entire database, clear any active filter first.

## Changes

- 1.0 — first version
- 1.1 — remove unnecessary reference to "Mystery Cache" when evaluating a cache.
		provide popup feedback of # of caches matched.
