-- OpenSAK Macro
-- Name: fix-owner-ids
-- Author: Ian Cole
-- Version: 1.3
-- Requires-API: 3
-- Description: Sets the Owner ID field of caches, where it is currently null or zero
-- Permissions: write

local names, current = {}, nil
for _, db in ipairs(opensak.databases()) do
    names[#names + 1] = db.name
    if db.active then current = db.name end
end

local values = opensak.form{
  title = "fix-owner-ids",
  remember = true,
  fields = {
    { type = "choice", id = "db", label = "<b>Reference database?</b>", options = names, default = current },
  },
}
if not values then return end -- cancelled

local num_blanks=0
local num_updates=0
local msg = ""
local n

-- Get owner name and ID table from the reference database, ensuring that the entries chosen do have a populated ID
local owner_rows = opensak.sql("SELECT owner_name, MAX(owner_id) AS owner_id FROM caches WHERE owner_id IS NOT NULL AND owner_id NOT IN ('','0') GROUP by owner_name",nil,{database=values.db})

-- Find the Lab caches with blank owner_id (one row per owner_name)
-- Originally database update was restricted to lab caches chosen by the GC Code prefix. However to make it independent of lab cache prefix
-- used that check is removed (because only lab caches should have an empty Owner ID anyway so the check is redundant).
--local blank_rows = opensak.sql("SELECT owner_name, owner_id FROM caches WHERE (owner_id IS NULL or owner_id IS 0)AND gc_code LIKE 'LB%' GROUP by owner_name")
local blank_rows = opensak.sql("SELECT owner_name, owner_id FROM caches WHERE owner_id IS NULL or owner_id IS 0 GROUP by owner_name")

for _, r in ipairs(blank_rows) do 

    -- Check owner_id is null (it should be)
    if r.owner_id == nil then

       -- Look for this owner name in Owner name/ID table 
       for _, rr in ipairs(owner_rows) do 
           if rr.owner_name==r.owner_name then
              -- print (r.owner_name)
              -- Check there is a defined owner_id for this owner_name
              if rr.owner_id ~= nil then
                  num_blanks = num_blanks + 1
				  n=opensak.sql_write("UPDATE caches SET owner_id = ? WHERE owner_name = ? AND (owner_id IS NULL OR owner_id IN ('','0'))", {rr.owner_id, r.owner_name})
                  num_updates = num_updates + n;
              else
                  print("Failed to find owner_id for owner_name ", r.owner_name)
              end
              break
           end
       end
    end
end

msg=string.format("fix-owner-ids updated %d entries for %d owners without owner_id", num_updates, num_blanks)
opensak.message(msg, "fix-owner-ids")
