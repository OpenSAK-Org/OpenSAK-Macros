# Jasmer Challenge

Filters one database down to the caches you still need for a Jasmer challenge
(one found cache for every month since May 2000, by placed date).

## What it does

1. Reads the placed months of all caches in your **found** database (B).
2. Looks in your **candidate** database (A) for caches placed in months not
   covered by B (not found, not archived, not disabled).
3. Switches to A and filters to just those caches.

By default it shows only the first (oldest) candidate per missing month.
Untick the checkbox in the form to see all candidates.

## Using it

When you run the macro, a form opens with dropdown menus where you pick:

- the database with all caches (A)
- the database with your finds (B)
- the first month of the challenge (default `2000-05`)
- whether to show only the first candidate per missing month

## Permissions

None. The macro only reads the databases and applies a filter.

## Notes

The macro looks for the placed date column automatically (`placed_date`,
`hidden`, ...). 
