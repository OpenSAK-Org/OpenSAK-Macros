-- Name: Jasmer Challenge
-- Author: HJGT
-- Version: 1.4
-- Description: Filters a database to caches placed in months you have not yet found a cache for, based on a second database with your finds.
-- Requires-API: 3
-- Permissions: none

local function has_column(list, name)
  for _, c in ipairs(list) do
    local n = type(c) == "table" and (c.name or c[1]) or c
    if n == name then return true end
  end
  return false
end

local function first_column(list, names)
  for _, n in ipairs(names) do
    if has_column(list, n) then return n end
  end
  return nil
end

-- Database names for the dropdowns (works whether databases() returns
-- plain names or tables with a name field)
local names = {}
for _, d in ipairs(opensak.databases()) do
  names[#names + 1] = type(d) == "table" and (d.name or d[1]) or d
end
if #names < 2 then
  opensak.message("You need at least two databases: one with all caches and one with your finds.", "Jasmer Challenge")
  return
end

-- Default for the "found" dropdown: a database with "found" in its name
local default_found = names[2]
for _, n in ipairs(names) do
  if n:lower():find("found", 1, true) then default_found = n break end
end
local default_all = names[1]
if default_all == default_found then default_all = names[2] end

-- ---------------------------------------------------------------
-- Choose databases and options
-- ---------------------------------------------------------------
local values = opensak.form{
  title = "Jasmer Challenge",
  fields = {
    { id = "db_all",   type = "choice", label = "Database with all caches (A)",
      options = names, default = default_all },
    { id = "db_found", type = "choice", label = "Database with your finds (B)",
      options = names, default = default_found },
    { id = "start",    type = "text",   label = "First month (YYYY-MM)",
      default = "2000-05" },
    { id = "one",      type = "checkbox", label = "Only the first candidate per missing month",
      default = true },
  },
}
if not values then return end  -- cancelled

local DB_ALL        = values.db_all
local DB_FOUND      = values.db_found
local START_MONTH   = values.start
local ONE_PER_MONTH = values.one

if DB_ALL == DB_FOUND then
  opensak.message("Database A and B must be two different databases.", "Jasmer Challenge")
  return
end
local start_year, start_month = tostring(START_MONTH):match("^(%d%d%d%d)%-(%d%d)$")
start_year = tonumber(start_year)
start_month = tonumber(start_month)
if not start_year or not start_month or start_month < 1 or start_month > 12 then
  opensak.message("First month must look like 2000-05.", "Jasmer Challenge")
  return
end
local current_month = os.date("%Y-%m")

-- ---------------------------------------------------------------
-- The placed date column is looked up so the macro does not depend on one
-- exact column name. If none matches, run opensak.columns("caches") and
-- add the right name to the list below.
local cols = opensak.columns("caches", { database = DB_ALL })
local placed = first_column(cols, { "placed_date", "hidden", "hidden_date", "placed" })
if not placed then
  error("Could not find the placed date column in the caches table")
end

-- Step 1: months already covered by your finds (Database B)
local covered = {}
local n_covered = 0
for _, r in ipairs(opensak.sql(
  "SELECT DISTINCT substr(" .. placed .. ", 1, 7) AS ym FROM caches " ..
  "WHERE " .. placed .. " IS NOT NULL",
  nil, { database = DB_FOUND })) do
  if r.ym then
    covered[r.ym] = true
    n_covered = n_covered + 1
  end
end

-- Step 2: candidates in Database A (not found, not archived, in a missing month)
local where = { placed .. " IS NOT NULL", "substr(" .. placed .. ", 1, 7) >= ?" }
if has_column(cols, "found")     then where[#where + 1] = "found = 0" end
if has_column(cols, "archived")  then where[#where + 1] = "archived = 0" end
if has_column(cols, "available") then where[#where + 1] = "available = 1" end

local rows = opensak.sql(
  "SELECT gc_code, substr(" .. placed .. ", 1, 7) AS ym FROM caches WHERE " ..
  table.concat(where, " AND ") .. " ORDER BY ym, " .. placed .. ", gc_code",
  { START_MONTH }, { database = DB_ALL })

local codes, seen, missing_with_cache = {}, {}, 0
for _, r in ipairs(rows) do
  if r.ym and not covered[r.ym] then
    if not ONE_PER_MONTH or not seen[r.ym] then
      codes[#codes + 1] = r.gc_code
    end
    if not seen[r.ym] then
      seen[r.ym] = true
      missing_with_cache = missing_with_cache + 1
    end
  end
end

local missing_months = {}
local current_year, current_month_number = current_month:match("^(%d%d%d%d)%-(%d%d)$")
local first_index = start_year * 12 + start_month - 1
local last_index = tonumber(current_year) * 12 + tonumber(current_month_number) - 1
for index = first_index, last_index do
  local year = math.floor(index / 12)
  local month = index % 12 + 1
  local ym = string.format("%04d-%02d", year, month)
  if not covered[ym] then
    missing_months[#missing_months + 1] = ym
  end
end
local missing_month_text = #missing_months > 0 and table.concat(missing_months, ", ") or "None"

-- Step 3: show only those caches in Database A
if opensak.database() ~= DB_ALL then
  opensak.switch_database(DB_ALL)
end

if #codes == 0 then
  opensak.message("No candidate caches found.\nUncovered months from " .. START_MONTH ..
        " through " .. current_month .. ": " .. missing_month_text, "Jasmer Challenge")
  return
end

opensak.filter{ codes = codes }

opensak.message(string.format(
  "Months covered by %s: %d.\nMissing months with a cache in %s: %d.\nUncovered months from %s through %s: %s.\nCaches shown: %d.",
  DB_FOUND, n_covered, DB_ALL, missing_with_cache,
  START_MONTH, current_month, missing_month_text, #codes), "Jasmer Challenge")
