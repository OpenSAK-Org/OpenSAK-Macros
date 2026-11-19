# fix-owner-ids

Sets the Owner ID field of caches, where it is currently null or zero, by looking for the owner name in a 
reference database. For the macro to work successfully that reference database should contain entries
(geocaches imported from geocaching.com) that contain populated OwnerName and OwnerId fields.

If the OwnerName is not found in the reference database then the OwnerID cannot currently be assigned. 
When the geocaching.com API becomes available it should be possible to obtain the OwnerID through the
API, but in the interim it can be set manually by anotyher macro.
 
I don't think that having invalid owner IDs causes any malfunction within OpenSAK, but it is good to keep things 
tidy.

It appears that Lab2GPX does not update the OwnerID, but this is not the only Issue I found.

Useful after importing lab caches from lab2gpx which does not populate Owner ID as part of the .gpx file.

This is inspired by the GSAK macro FixOwnerIDs by Gill & Tony

## What it needs

- OpenSAK with macro API version 3 or newer
- Permissions: none

## How to use it

1. In OpenSAK select a database within which OwnerIDs are to be updated
2. Run the macro from **Macros → Macro manager…**.
3. In the form that opens select the OpenSAK database which is likely to contain entries with populated
   OwnerName ane OwnerID fields.  

## Changes

- 1.0 — first version
