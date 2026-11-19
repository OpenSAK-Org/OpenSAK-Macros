-- OpenSAK Macro
-- Name: fix-owner-ids
-- Author: Ian Cole
-- Version: 1.0
-- Requires-API: 3
-- Description: Sets the Owner ID field of caches, where it is currently null or zero, by looking for the owner name 
--              in a  reference database. All such entries in the current datanase are updated where possible 
--              (irrespective of filter).
--              Useful after importing lab caches from lab2gpx which does not populate Owner ID as part 
--              of the .gpx file.
--              The reference database should contain caches with populated Owner ID fields, normally 
--              non-lab caches imported from geocaching.com. The reference database is chosen from a form and can be
--              the same as the current database.
--              Where no matching Owner Name in found in the reference database then the Owner ID field is not 
--              updated. When the geocaching.com API access becomes available it should be possible to obtain the
--              missing Owner IDs via the API, but until then manual correction will be needed.

--              Inspired by the GSAK macro FixOwnerIDs by Tony Rolfe (Gill & Tony) and shared with their
--              permission.
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

local num=0
local msg = ""
local sqlstr=""

-- Get owner name and ID table from the reference database
local owner_rows = opensak.sql("SELECT owner_name, owner_id, COUNT (*) AS n FROM caches GROUP by owner_name",nil,{database=values.db})

-- Find the Lab caches with blank owner_id (one row per owner_name)
-- Originally datanase update was restricted to lab caches chosen by the GC Code prefix. However to make it independent of lab cache prefix
-- used that check is removed (because only lab caches should have an empty Owner ID anyway so the check is redunddant).
--local blank_rows = opensak.sql("SELECT owner_name, owner_id FROM caches WHERE (owner_id IS NULL or owner_id IS 0)AND gc_code LIKE 'LB%' GROUP by owner_name")
local blank_rows = opensak.sql("SELECT owner_name, owner_id FROM caches WHERE owner_id IS NULL or owner_id IS 0 GROUP by owner_name")

for _, r in ipairs(blank_rows) do 
    num = num + 1

    -- Check owner_id is null (it should be)
    if r.owner_id == nil then

       -- Look for this owner name in Owner name/ID table 
       for _, rr in ipairs(owner_rows) do 

           if rr.owner_name==r.owner_name then
              -- print (r.owner_name)
              -- Check there is a defined owner_id for this owner_name
              if rr.owner_id ~= nil then

                  -- Build SQL string to update owner_id for all rows with this owner_name
                  sqlstr=string.format("UPDATE caches SET owner_id=%s WHERE owner_name=\"%s\"", rr.owner_id, r.owner_name)
                  opensak.sql_write(sqlstr)
              else
                  print("Failed to find owner_id for owner_name ", r.owner_name)
              end
              break
           end
       end
    end
end

msg=string.format("fix-owner-ids updated IDs for %d different owner_names", num)
opensak.message(msg, "fix-owner-ids")
