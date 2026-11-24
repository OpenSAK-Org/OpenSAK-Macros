-- OpenSAK Macro
-- Name: check-user-sort-incremental
-- Author: Ian Cole
-- Version: 1.0
-- Requires-API: 3
-- Description: Checks that user_sort field is sequential starting at 1
-- Permissions: none
--
-- Remove filter and sort by user_sort in ascending order
opensak.clear_filter()
opensak.sort("user_sort")

local expected = 1
local msg

-- Run through each cache in order
for c in opensak.caches{ fields = {"user_sort"} } do   -- fields only: still active filter + grid order
    if c.user_sort == nil then
        msg=string.format("Missing user_sort for %s", c.code)
        opensak.message(msg, "check-user-sort")
        opensak.select(c.code)
        return
    elseif c.user_sort ~= expected then
        msg=string.format("%s has user_sort %d, expected %d", c.code, c.user_sort, expected)
        opensak.message(msg, "check-user-sort")
        opensak.select(c.code)
        return
    end
    expected = expected + 1
end

msg=string.format("UserSort is continuous 1..%d", expected-1)
opensak.message(msg, "check-user-sort")
