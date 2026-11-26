-- OpenSAK Macro
-- Name: Update elevation (current cache)
-- Author: AgreeDK
-- Version: 0.1
-- Requires-API: 5
-- Description: Looks up the elevation of the selected cache at Open Topo Data and Open-Meteo, shows the results side by side and lets you pick the value to save
-- Permissions: write
-- Network: api.opentopodata.org, api.open-meteo.com
--
-- How it works
--   1. Takes the cache selected in the grid.
--   2. If the cache has corrected coordinates, asks which coordinates
--      to look up (corrected is the default, see USE_CORRECTED).
--   3. Looks the point up at two free elevation services:
--        - Open Topo Data, trying the most detailed elevation model that
--          covers the point first (New Zealand 8 m, USA 10 m, Europe
--          25 m, then SRTM / ASTER 30 m worldwide)
--        - Open-Meteo (Copernicus GLO-90, 90 m, worldwide)
--   4. Shows a form with the elevation the cache has now and what each
--      service found. Pick a value, type your own, or pick "(empty)"
--      to clear it.
--   5. Writes the elevation only if it changed.
--
-- Written so lookup() and the form are separate: a later version can
-- run lookup() over the whole filter instead of asking per cache.
-- Needs a beta build (opensak.get_url is beta-only until 1.23.0).

---------------------------------------------------------------------
-- Settings you can change
---------------------------------------------------------------------

-- Which coordinates to pre-select when the cache has corrected
-- coordinates: true = corrected, false = posted.
local USE_CORRECTED = true

-- Open Topo Data elevation models, tried in this order for each point;
-- the first one that covers the point is used. Models that include the
-- sea floor (mapzen, gebco2020, etopo1) are left out on purpose: a cache
-- by the coast would get the depth of the sea bed.
local TOPO_DATASETS = { "nzdem8m", "ned10m", "eudem25m", "srtm30m", "aster30m" }

-- Set to false to skip one of the services.
local USE_OPENTOPODATA = true
local USE_OPENMETEO    = true

---------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------

local TITLE = "Update elevation"
local EMPTY = "(empty)"

-- Name and resolution (metres) of each elevation model.
local MODELS = {
  nzdem8m  = { "LINZ NZ DEM", 8 },
  ned10m   = { "USGS NED", 10 },
  eudem25m = { "EU-DEM", 25 },
  srtm30m  = { "SRTM", 30 },
  aster30m = { "ASTER GDEM", 30 },
  glo90    = { "Copernicus GLO-90", 90 },
}

-- Same range as the elevation field accepts.
local MIN_ELEVATION, MAX_ELEVATION = -1000, 10000

-- Text safe to put inside HTML
local function esc(v)
  if v == nil or v == "" then return "<i>-</i>" end
  return (tostring(v):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- 12.0 -> "12", 12.25 -> "12.3"
local function fmt(v)
  if v == nil then return nil end
  local s = string.format("%.1f", v)
  return (s:gsub("%.0$", ""))
end

-- A real elevation in the range the field accepts, or nil.
local function valid(v)
  if type(v) ~= "number" or v ~= v then return nil end   -- v ~= v: NaN
  if v < MIN_ELEVATION or v > MAX_ELEVATION then return nil end
  return v
end

-- Calls a JSON web service. Returns the decoded answer, or nil and an
-- error text.
local function get_json(url)
  local ok, body, info = pcall(opensak.get_url, url, { timeout = 20 })
  if not ok then return nil, tostring(body) end
  local okj, data = pcall(opensak.json.decode, body)
  if info.status ~= 200 then
    -- both services explain what went wrong in the JSON body
    local why = okj and type(data) == "table" and (data.error or data.reason)
    if type(why) ~= "string" then why = nil end
    return nil, "HTTP " .. info.status .. (why and (": " .. why) or "")
  end
  if not okj or type(data) ~= "table" then return nil, "unreadable answer" end
  return data
end

---------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------

-- Each returns {elevation=, model=, resolution=} or nil and an error.

-- Open Topo Data (api.opentopodata.org). Free public API: max 1 call
-- per second and 1000 calls per day, so one cache per run is no problem.
local function topo_lookup(lat, lon)
  if not USE_OPENTOPODATA then return nil, "switched off (USE_OPENTOPODATA)" end
  local url = string.format(
    "https://api.opentopodata.org/v1/%s?locations=%.6f,%.6f",
    table.concat(TOPO_DATASETS, ","), lat, lon)
  local data, err = get_json(url)
  if not data then return nil, err end
  if data.status ~= "OK" then return nil, tostring(data.error or data.status) end
  local r = data.results and data.results[1]
  local elevation = r and valid(r.elevation)
  if not elevation then return nil, "no elevation data for this point" end
  local model = MODELS[r.dataset] or { tostring(r.dataset), nil }
  return { elevation = elevation, model = model[1], resolution = model[2] }
end

-- Open-Meteo (api.open-meteo.com), Copernicus GLO-90. Free for
-- non-commercial use; data CC BY 4.0, attribution required (shown in
-- the form).
local function meteo_lookup(lat, lon)
  if not USE_OPENMETEO then return nil, "switched off (USE_OPENMETEO)" end
  local url = string.format(
    "https://api.open-meteo.com/v1/elevation?latitude=%.6f&longitude=%.6f",
    lat, lon)
  local data, err = get_json(url)
  if not data then return nil, err end
  local elevation = valid(data.elevation and data.elevation[1])
  if not elevation then return nil, "no elevation data for this point" end
  return { elevation = elevation, model = MODELS.glo90[1], resolution = MODELS.glo90[2] }
end

-- All sources for one point. No user interaction, so a later version
-- can call it in a loop over the filter.
local function lookup(lat, lon)
  local r = {}
  r.topo, r.topo_err = topo_lookup(lat, lon)
  r.meteo, r.meteo_err = meteo_lookup(lat, lon)
  return r
end

-- The text of a form option for a result, e.g.
-- "38.4 m - EU-DEM, 25 m (Open Topo Data)". The number comes first so
-- it can be read back (see parse()).
local function option(res, service)
  local where = res.model
  if res.resolution then where = where .. ", " .. res.resolution .. " m" end
  return string.format("%s m - %s (%s)", fmt(res.elevation), where, service)
end

-- Reads the elevation back from a picked or typed option: the first
-- number in the text ("38.4 m - ...", "38,4" or "38"). nil = empty.
local function parse(text)
  if text == nil then return nil end
  text = tostring(text)
  if text:match("^%s*$") or text:match("^%s*%(empty%)%s*$") then return nil end
  local num = text:match("^%s*(-?%d+[.,]?%d*)")
  if not num then return false end
  return tonumber((num:gsub(",", ".")))
end

---------------------------------------------------------------------
-- 1. The selected cache and the coordinates to use
---------------------------------------------------------------------

if not opensak.update or not opensak.get_url then
  opensak.message("This macro needs a beta build of OpenSAK 1.23.0 or newer.", TITLE)
  return
end

local c = opensak.current()
if not c then
  opensak.message("Select a cache in the list first.", TITLE)
  return
end

local lat, lon, basis = c.lat, c.lon, "posted"
if c.corrected and c.corrected.lat and c.corrected.lon then
  local which = opensak.choose(
    c.code .. " has corrected coordinates. Which coordinates should be looked up?",
    { "Corrected", "Posted" }, USE_CORRECTED and "Corrected" or "Posted", TITLE)
  if not which then return end
  if which == "Corrected" then
    lat, lon, basis = c.corrected.lat, c.corrected.lon, "corrected"
  end
end
if not lat or not lon then
  opensak.message(c.code .. " has no coordinates.", TITLE)
  return
end

---------------------------------------------------------------------
-- 2. Look up
---------------------------------------------------------------------

local p = opensak.progress("Looking up the elevation of " .. c.code)
local r = lookup(lat, lon)
p:close()

if not r.topo and not r.meteo then
  opensak.message(string.format(
    "No elevation found for %s.\n\nOpen Topo Data: %s\nOpen-Meteo: %s",
    c.code, r.topo_err, r.meteo_err), TITLE)
  return
end

---------------------------------------------------------------------
-- 3. Show the sources and let the user pick
---------------------------------------------------------------------

local function cell(res)
  if not res then return "" end
  local s = esc(fmt(res.elevation)) .. " m"
  if res.resolution then
    s = s .. "<br><small>" .. esc(res.model) .. ", " .. res.resolution .. " m</small>"
  end
  return s
end

local notes = {}
if not r.topo then notes[#notes + 1] = "Open Topo Data: " .. esc(r.topo_err) end
if not r.meteo then notes[#notes + 1] = "Open-Meteo: " .. esc(r.meteo_err) end

-- Warn when the two services are far apart (steep terrain, trees or
-- buildings in one model, or a wrong coordinate).
local warning = ""
if r.topo and r.meteo and math.abs(r.topo.elevation - r.meteo.elevation) >= 20 then
  warning = string.format(
    "<p>\u{26A0} The services differ by %s m - check the value before saving.</p>",
    fmt(math.abs(r.topo.elevation - r.meteo.elevation)))
end

local html = string.format(
  "<p><b>%s</b> %s<br>%s coordinates: %.5f, %.5f</p>"
    .. "<table border='1' cellspacing='0' cellpadding='4'>"
    .. "<tr><th>Now</th><th>Open Topo Data</th><th>Open-Meteo</th></tr>"
    .. "<tr><td>%s</td><td>%s</td><td>%s</td></tr></table>"
    .. "%s%s"
    .. "<p><small>Elevation data: Open Topo Data (opentopodata.org); "
    .. "Open-Meteo (open-meteo.com), Copernicus DEM GLO-90 "
    .. "&copy; DLR e.V. 2010-2014 and &copy; Airbus Defence and Space "
    .. "GmbH 2014-2018, provided under COPERNICUS by the European Union "
    .. "and ESA, CC BY 4.0.</small></p>",
  esc(c.code), esc(c.name), basis == "corrected" and "Corrected" or "Posted",
  lat, lon,
  c.elevation and (esc(fmt(c.elevation)) .. " m") or "<i>-</i>",
  cell(r.topo), cell(r.meteo),
  warning,
  #notes > 0 and ("<p><i>" .. table.concat(notes, "<br>") .. "</i></p>") or "")

-- Pre-select the most detailed model that answered.
local options = {}
if r.topo then options[#options + 1] = option(r.topo, "Open Topo Data") end
if r.meteo then options[#options + 1] = option(r.meteo, "Open-Meteo") end
if c.elevation then options[#options + 1] = fmt(c.elevation) .. " m - now" end
options[#options + 1] = EMPTY

local v
while true do
  v = opensak.form{
    title = TITLE .. " - " .. c.code,
    fields = {
      { type = "html", html = html },
      { type = "choice", id = "elevation", label = "Elevation (metres)",
        editable = true, options = options, default = options[1] },
    },
  }
  if not v then return end   -- cancelled
  local value = parse(v.elevation)
  if value == false or (value ~= nil and not valid(value)) then
    opensak.message(string.format(
      "\"%s\" is not an elevation between %d and %d metres.",
      tostring(v.elevation), MIN_ELEVATION, MAX_ELEVATION), TITLE)
  else
    v = value
    break
  end
end

---------------------------------------------------------------------
-- 4. Write only if it changed
---------------------------------------------------------------------

-- Compare at the precision the form shows (one decimal).
local old = c.elevation
local new = v and tonumber(fmt(v)) or nil
if (old and tonumber(fmt(old))) == new then
  print(c.code .. ": nothing changed")
  return
end

opensak.update(c.code, { elevation = new or false })   -- false clears
print(string.format("%s: elevation %s -> %s (%s coordinates)",
  c.code, old and (fmt(old) .. " m") or "-", new and (fmt(new) .. " m") or "-", basis))
