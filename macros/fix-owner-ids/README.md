# fix-owner-ids

Sets the Owner ID field of caches, where it is currently null or zero, by looking for the owner name 
in a reference database. All such entries in the current database are updated where possible 
(irrespective of filter).

Useful after importing lab caches from lab2gpx which does not populate Owner ID as part 
of the .gpx file.

The reference database should contain caches with populated Owner ID fields, normally 
non-lab caches imported from geocaching.com. The reference database is chosen from a form and can be
the same as the current database.

Where no matching Owner Name is found in the reference database then the Owner ID field is not 
updated. When the geocaching.com API access becomes available it should be possible to obtain the
missing Owner IDs via the API, but until then manual correction will be needed.

Inspired by the GSAK macro FixOwnerIDs by Tony Rolfe (Gill & Tony) and shared with their
permission.

## What it needs

- OpenSAK with macro API version 3 or newer
- Permissions: write

## How to use it

1. In OpenSAK select a database within which OwnerIDs are to be updated
2. Run the macro from **Macros → Macro manager…**.
3. In the form that opens select the OpenSAK database which is likely to contain entries with populated
   OwnerName and OwnerID fields.  

## Changes

- 1.0 — first version
- 1.1 — Correct permissions
- 1.2 — Further permission correction and changes following review
