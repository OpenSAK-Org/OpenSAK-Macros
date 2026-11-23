-- OpenSAK Macro
-- Name: set-owner-id
-- Author: Ian Cole
-- Version: 1.0
-- Requires-API: 3
-- Description: Sets the Owner ID field of caches in the current database for a specified Owner name.
-- Permissions: write

local msg = ""
local values, button = opensak.form{
  title = "set-owner-id",
  layout = "absolute",
  width = 320,
  height = 160,
  remember = true,
  buttons = {},
  -- The form's own buttons close it,
  -- Update button is only enabled if both Owner ID and Owner Name are populated 
  validate = function(f, button)
  if button == "update" then
        if f:get("ownerName") == "" then
           return "Please enter Owner Name"
        elseif f:get("ownerID") == "" then
           return "Please enter Owner ID"
        end
    end
  end,
  
  fields = {
    { type = "text", id = "ownerName", x = 108, y = 8, w = 150, h = 24, on_change=function (f,v) f:set_enabled("update", f:get("ownerName")~="" and f:get("ownerID")~= "")end},
    { type = "text", id = "ownerID", x = 108, y = 48, w = 150, h = 24, on_change=function (f,v) f:set_enabled("update",  f:get("ownerName")~="" and f:get("ownerID")~= "")end},
    { type = "label", id = "label1", label = "Owner Name", x = 8, y = 8, w = 100, h = 16 },
    { type = "label", id = "label2", label = "Owner ID", x = 8, y = 48, w = 100, h = 16 },
    { type = "separator", x = 8, y = 100, w = 304, h = 8 },
    { type = "button", id = "update", label = "Update", default = true,
      x = 40, y = 110, w = 80, h = 28 , },
    { type = "button", id = "cancel", label = "Cancel", cancel = true,
      x = 150, y = 110, w = 80, h = 28 },
  },
  on_open = function(f) f:set("ownerName", "") f:set("ownerID", "") f:set_enabled ("update", false) end,  
}
if not values then return end  -- cancelled

-- Trim and check inputs
local name = (values.ownerName or ""):match("^%s*(.-)%s*$")
local id = (values.ownerID or ""):match("^%s*(.-)%s*$")
if not id:match("^%d+$") then
    opensak.message("Owner ID must be a number", "set-owner-id")
end 
--
-- Build SQL string to update owner_id for all rows with this owner_name where owner_id is not set
n=opensak.sql_write("UPDATE caches SET owner_id=? WHERE owner_name=? AND (owner_id IS NULL OR owner_id IN ('','0'))", {id, name})

msg=string.format("set-owner-id updated IDs for %d caches", n)
opensak.message(msg, "set-owner-id")



