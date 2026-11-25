-- OpenSAK Macro
-- Name: Update location (current cache)
-- Author: AgreeDK
-- Version: 0.1
-- Requires-API: 3
-- Description: Looks up country / state / county for the selected cache from every source (offline boundary data and OpenStreetMap), shows them side by side and lets you pick - can also replace or clear wrong values
-- Permissions: write
-- Network: nominatim.openstreetmap.org
--
-- How it works
--   1. Takes the cache selected in the grid.
--   2. If the cache has corrected coordinates, asks which coordinates
--      to look up.
--   3. Looks the point up offline (same data as Tools -> Update
--      location) and at OpenStreetMap's Nominatim service.
--   4. Shows a form with what the cache has now and what each source
--      found. For each field you pick a value, type your own, or pick
--      "(empty)" to clear it. Fields where the sources disagree are
--      marked with a warning.
--   5. Writes only the fields you changed.
--
-- Unlike "Fill missing location", this macro CAN overwrite and clear
-- values - that is the point: fixing wrong data on one cache.
--
-- Written so lookup() and the form are separate: a later version can
-- run lookup() over the whole filter with a fixed rule instead of the form.
-- The online part needs a beta build (opensak.get_url is beta-only).

---------------------------------------------------------------------
-- Settings you can change
---------------------------------------------------------------------

-- Language of the names Nominatim returns. "" = local names,
-- "en" = English names where OSM has them (default: matches the
-- English names in the offline data, e.g. "Switzerland").
local LANGUAGE = "en"

-- Which Nominatim address fields to try, in order, for each OpenSAK
-- field. The first one that has a value wins.
local STATE_KEYS  = { "state", "region", "province" }
local COUNTY_KEYS = { "county", "municipality", "state_district" }

-- Set to false to skip OpenStreetMap and only use the offline data.
local USE_ONLINE = true

---------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------

local LEVELS = { "country", "state", "county" }
local LABELS = { country = "Country", state = "State", county = "County" }
local EMPTY  = "(empty)"

-- true if a text field is nil or only whitespace
local function empty(v)
  return v == nil or tostring(v):match("^%s*$") ~= nil
end

local function trim(v)
  return (tostring(v):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Text safe to put inside HTML
local function esc(v)
  if empty(v) then return "<i>-</i>" end
  return (tostring(v):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Turns JSON escapes such as æ and \" into real characters.
local function unescape(s)
  s = s:gsub("\\u(%x%x%x%x)", function(hex)
    return utf8.char(tonumber(hex, 16))
  end)
  return (s:gsub('\\(["\\/])', "%1"))
end

-- Picks one field out of Nominatim's JSON answer, e.g. "county".
local function json_field(body, key)
  local _, value = opensak.re.find(body, '"' .. key .. [["\s*:\s*"((?:[^"\\]|\\.)*)"]])
  if value then return unescape(value) end
  return nil
end

-- First key in `keys` that has a value in the answer.
local function first_field(body, keys)
  for _, key in ipairs(keys) do
    local v = json_field(body, key)
    if not empty(v) then return v end
  end
  return nil
end

---------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------

-- Offline boundary data. Returns {country=, state=, county=} or nil
-- and an error text.
local function offline_lookup(lat, lon)
  local loc = opensak.coords.location(lat, lon)
  if loc == nil then
    return nil, "boundary data not installed (Tools -> Update location)"
  end
  return { country = loc.country, state = loc.state, county = loc.county }
end

-- OpenStreetMap Nominatim. Returns {country=, state=, county=} or nil
-- and an error text.
local function osm_lookup(lat, lon)
  if not USE_ONLINE then return nil, "switched off (USE_ONLINE)" end
  if not opensak.get_url then return nil, "needs a beta build" end

  local url = string.format(
    "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&lat=%.6f&lon=%.6f",
    lat, lon)
  if LANGUAGE ~= "" then url = url .. "&accept-language=" .. LANGUAGE end

  -- pcall catches network errors (no answer, refused, user said Deny)
  local ok, body, info = pcall(opensak.get_url, url, { timeout = 20 })
  if not ok then return nil, tostring(body) end
  if info.status ~= 200 then return nil, "HTTP " .. info.status end
  if json_field(body, "error") then return nil, json_field(body, "error") end

  return {
    country = json_field(body, "country"),
    state   = first_field(body, STATE_KEYS),
    county  = first_field(body, COUNTY_KEYS),
  }
end

-- All sources for one point. No user interaction, so a later version
-- can call it in a loop over the filter.
local function lookup(lat, lon)
  local r = {}
  r.offline, r.offline_err = offline_lookup(lat, lon)
  r.osm, r.osm_err = osm_lookup(lat, lon)
  return r
end

-- true if both sources have a value for `f` and the values differ
local function disagree(r, f)
  local a = r.offline and r.offline[f]
  local b = r.osm and r.osm[f]
  return not empty(a) and not empty(b) and trim(a) ~= trim(b)
end

-- What to pre-select: the offline value (same naming as the rest of
-- the database), else OpenStreetMap, else what the cache has now.
local function suggestion(c, r, f)
  if r.offline and not empty(r.offline[f]) then return trim(r.offline[f]) end
  if r.osm and not empty(r.osm[f]) then return trim(r.osm[f]) end
  if not empty(c[f]) then return trim(c[f]) end
  return EMPTY
end

---------------------------------------------------------------------
-- 1. The selected cache and the coordinates to use
---------------------------------------------------------------------

if not opensak.update then
  opensak.message("This macro needs a build where macros may change caches.")
  return
end

local c = opensak.current()
if not c then
  opensak.message("Select a cache in the list first.", "Update location")
  return
end

local lat, lon, basis = c.lat, c.lon, "posted"
if c.corrected and c.corrected.lat and c.corrected.lon then
  local which = opensak.choose(
    c.code .. " has corrected coordinates. Which coordinates should be looked up?",
    { "Posted", "Corrected" }, "Posted", "Update location")
  if not which then return end
  if which == "Corrected" then
    lat, lon, basis = c.corrected.lat, c.corrected.lon, "corrected"
  end
end
if not lat or not lon then
  opensak.message(c.code .. " has no coordinates.", "Update location")
  return
end

---------------------------------------------------------------------
-- 2. Look up
---------------------------------------------------------------------

local p = opensak.progress("Looking up " .. c.code)
local r = lookup(lat, lon)
p:close()

---------------------------------------------------------------------
-- 3. Show the sources and let the user pick
---------------------------------------------------------------------

local rows = {}
for _, f in ipairs(LEVELS) do
  rows[#rows + 1] = string.format(
    "<tr><td><b>%s</b></td><td>%s</td><td>%s</td><td>%s</td></tr>",
    LABELS[f], esc(c[f]),
    r.offline and esc(r.offline[f]) or "",
    r.osm and esc(r.osm[f]) or "")
end

local notes = {}
if not r.offline then notes[#notes + 1] = "Offline: " .. esc(r.offline_err) end
if not r.osm then notes[#notes + 1] = "OpenStreetMap: " .. esc(r.osm_err) end

local html = string.format(
  "<p><b>%s</b> %s<br>%s coordinates: %.5f, %.5f</p>"
    .. "<table border='1' cellspacing='0' cellpadding='4'>"
    .. "<tr><th></th><th>Now</th><th>Offline</th><th>OpenStreetMap</th></tr>%s</table>"
    .. "%s",
  esc(c.code), esc(c.name), basis == "corrected" and "Corrected" or "Posted",
  lat, lon, table.concat(rows),
  #notes > 0 and ("<p><i>" .. table.concat(notes, "<br>") .. "</i></p>") or "")

local fields = { { type = "html", html = html } }
for _, f in ipairs(LEVELS) do
  -- every distinct value any source has, plus (empty)
  local options, seen = {}, {}
  local function add(v)
    if empty(v) then return end
    v = trim(v)
    if not seen[v] then seen[v] = true; options[#options + 1] = v end
  end
  add(c[f])
  if r.offline then add(r.offline[f]) end
  if r.osm then add(r.osm[f]) end
  options[#options + 1] = EMPTY

  local label = LABELS[f]
  if disagree(r, f) then label = label .. "  \u{26A0} sources disagree" end

  fields[#fields + 1] = {
    type = "choice", id = f, label = label, editable = true,
    options = options, default = suggestion(c, r, f),
  }
end

local v = opensak.form{
  title = "Update location - " .. c.code,
  fields = fields,
}
if not v then return end   -- cancelled

---------------------------------------------------------------------
-- 4. Write only what changed
---------------------------------------------------------------------

local changes, parts = {}, {}
for _, f in ipairs(LEVELS) do
  local new = v[f]
  if empty(new) or trim(new) == EMPTY then new = nil else new = trim(new) end
  local old = (not empty(c[f])) and trim(c[f]) or nil
  if new ~= old then
    changes[f] = new or false            -- false clears the field
    parts[#parts + 1] = string.format("%s: %s -> %s", f, old or "-", new or "-")
  end
end

if #parts == 0 then
  print(c.code .. ": nothing changed")
  return
end

opensak.update(c.code, changes)
print(c.code .. " updated (" .. basis .. " coordinates)")
for _, line in ipairs(parts) do print("  " .. line) end
