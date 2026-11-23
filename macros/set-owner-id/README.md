# set-owner-id

Sets the Owner ID field of caches, where it is currently null or zero.
The Owner Name and associated Owner ID is manually input by a form.
Normally used to set up OwnerID of lab caches imported from lab2gpx, where then
OwnerID information is not provided within the .gpx file.

Where possible the macro fix-owner-ids should be used to set the OwnerID field
(this works by copying the OwnerID from non-lab caches in the OpenSAK databases, where
this field is already populated). This macro set-owner-id can then be used for
those lab caches where there are no other caches for that same owner and with a
defined OwnerID. 

To obtain the Owner ID for a given Owner Name, use the geocaching.com website
and open the profile for a user. Then click on the entry "View Forum Posts".
The page that opens has a URL that contains the required numeric owner ID.

Care should be taken when using this macro. If a mistake is made the wrong OwnerID
could be assigned. If this happens then the macro can not be re-used to correct the
problem as by now an OwnerID is assigned. To correct this the entry should be deleted
from the OpenSAK database and re-imported from lab2gpx data. 

## What it needs

- OpenSAK with macro API version 3 or newer
- Permissions: write

## How to use it

1. In OpenSAK select a database within which OwnerIDs are to be updated
2. Run the macro from **Macros → Macro manager…**.
3. In the form that opens enter the required Owner Name and associated OwnerID, 
   and click Update.

## Changes

- 1.0 — first version
