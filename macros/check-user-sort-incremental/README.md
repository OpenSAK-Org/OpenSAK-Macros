# check-user-sort-incremental

Some GSASK users use the UserSort field to store a "find number" which can be used to 
sort a database of finds in the order in which they were found. GSAK provides the ability
to manually (direct edit) and semi-automatically (double click on field that then allocates
the next number) update this field. Currently OpenSAK does not allow such editing so the field
content is obtained by import of a GSAK database.

This macro checks that the find number in a database runs from sequentially and incrementally 
from 1 to the number of entries in the database. When the first gap or duplication occurs the macro
reports this to the user and stops.  

Until OpenSAK provides a method to edit the UserSort field, any errors will require correction
in GSAK and then reimport of the database into OpenSAK.

Note that any filter that is set prior to running the macro is removed. It is not restored so that
the erroneous cache can be shown as the selected one


## What it needs

- OpenSAK with macro API version 3 or newer
- Permissions: none

## How to use it

1. In OpenSAK select a database within which UserSort is to be checked (this database should be
   a database of Finds where the UserSort field stores the "find number").
2. Run the macro from **Macros → Macro manager…**.

## Changes

- 1.0 — first version
