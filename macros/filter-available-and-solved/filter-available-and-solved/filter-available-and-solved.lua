-- OpenSAK Macro --
-- Name: Filter Available and Solved
-- Author: OokOok
-- Version: 1.1
-- Requires-API: 4
-- Description: Filter the current view for available, unfound, non-owned caches, excluding unsolved Mystery/Unknown caches.
-- Permissions: none

local matching_codes = {}

-- Loop over caches in the active filter (equivalent to GSAK's $_WHERE)
for c in opensak.caches{ fields = { "found", "available", "archived", "owned", "type", "corrected" } } do
    local is_mystery = (c.type == "Unknown Cache")
    local is_unsolved_mystery = is_mystery and (c.corrected == nil)

    if (not c.found) and c.available and (not c.archived) and (not c.owned) and (not is_unsolved_mystery) then
        table.insert(matching_codes, c.code)
    end
end

if #matching_codes == 0 then
    opensak.message("No caches in the current view matched the criteria.", "FilterAvailableAndSolved")
else
    opensak.message(opensak.filter{
        codes = matching_codes,
        label = "Available & Solved",
    }
	.. " caches matched.", "FilterAvailableAndSolved")
end
