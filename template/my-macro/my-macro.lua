-- OpenSAK Macro
-- Name: My macro
-- Author: Your Name
-- Version: 1.0
-- Requires-API: 3
-- Description: One line saying what the macro does.
-- Permissions: none

-- Rename this folder and this file (lowercase letters, digits and hyphens,
-- e.g. find-easy-traditionals/find-easy-traditionals.lua), fill in the
-- header above, and replace the code below with your own.

local caches = opensak.get_caches()
opensak.show_message("The active database has " .. #caches .. " caches.")
