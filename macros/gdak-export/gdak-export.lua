-- OpenSAK Macro
-- Name: Export to GDAK
-- Author: nagisml
-- Version: 1.0
-- Requires-API: 4
-- Description: Writes the active database as a GSAK sqlite.db3 database that the Android app GDAK can open
-- Permissions: write-files
-- Headless: yes

--[[
GDAK (nl.wlsoft.tfnxDroid) works offline on databases copied from GSAK:
a folder per database holding a sqlite.db3 in GSAK's layout (tables
Caches, CacheMemo, Logs, LogMemo, Waypoints, WayMemo, Attributes,
Corrected, CacheImages, LogImages). When it opens one, GDAK adds the
columns it needs on top of GSAK's (IsLite, NumTravelBug, LastGDAKDate,
lUploaded, proximity, …) itself, with ALTER TABLE. So this macro writes
exactly GSAK's layout, the one GDAK is made to read. The table
definitions are GSAK's; checked against GDAK 5.1.1578's APK, whose own
tables are a subset of these with the same names and types.

GDAK differs from GCDroid (see the gcdroid-export macro) in what it
expects: coordinates are text, as in GSAK (Latitude text default '0.0'),
and there is no UserTagColor column.

The file is opensak.macro_db(): <macro file name>.db3, always next to the
macro (OpenSAK has no way to put it elsewhere, and copy_file() refuses
.db3). GDAK needs it as sqlite.db3 inside a folder named after the
database, so it has to be renamed when copied to the phone. Every run
replaces the tables in it. The active database is only read; the write
approval is not needed. The macro's folder must be writable for macros
(Settings → Folder permissions, or approve when asked).

To keep the export out of the macros folder, copy the macro to OpenSAK's
temp folder (opensak.temp_dir()) and run it from there; the database is
then written to the temp folder. Run from anywhere else, a note in the
output says where the file went.

Only filled: the columns GDAK reads (list, map, details, logs,
waypoints, corrected coordinates, notes) plus the cheap personal and
status columns. GSAK-only columns (macro flags, user sort, user data,
colours, lock, …) keep GSAK's defaults; trackables and images are left
out (the image tables exist but stay empty).

Corrected coordinates are stored the GSAK way, which is also how GDAK
stores its own: Caches.Latitude/Longitude hold the corrected position
with HasCorrected = 1, the posted one is in Caches.LatOriginal/LonOriginal
(and in Corrected.kBeforeLat/kBeforeLon for GSAK).
]]

-- ── Settings ────────────────────────────────────────────────────────────────

-- Two settings come from a form (remembered between runs). Headless, give
-- them with --arg, e.g.
--   opensak run gdak-export.lua --arg active_filter=no --arg max_logs=20 --yes
-- (--yes takes the remembered value or the default for a field not given):
--   active_filter  no (default): every cache of the database; yes: only the
--                  active filter
--   max_logs       newest logs kept per cache; 0 (default) = all of them
local settings = opensak.form{
    title = "Export to GDAK",
    remember = true,
    fields = {
        { type = "checkbox", id = "active_filter", label = "Only the caches of the active filter",
          default = false },
        { type = "number", id = "max_logs", label = "Logs per cache (0 = all)",
          default = 0, min = 0 },
    },
}
if not settings then return end         -- cancelled
local ONLY_ACTIVE_FILTER = settings.active_filter == true
local MAX_LOGS_PER_CACHE = math.floor(tonumber(settings.max_logs) or 0)

-- Caches per SQL statement (each statement must finish within 60 s).
local BATCH = 2000

-- ── The GSAK schema (what GDAK reads) ───────────────────────────────────────

-- GSAK's database version, as in a database copied from GSAK.
local GSAK_USER_VERSION = 27

local TABLES = {
    { "Caches", [[
  (Code text default '' not null, Name text default '' not null, Distance real default 0.00 not null, PlacedBy text default '' not null, Archived integer default 0 not null,
   Bearing text default '' not null, CacheId text default '1' not null, CacheType text default 'O' not null, Changed text default current_date not null,
   Container text default 'Unknown' not null, County text default '' not null, Country text default '' not null, Degrees real default 0.00 not null,
   Difficulty real default  1.0 not null, DNF integer default  0 not null, DNFDate text default '' not null, Found integer default  0 not null,
   FoundCount integer default  0 not null, FoundByMeDate text default  '' not null, FTF integer default  0 not null, HasCorrected integer default  0 not null,
   HasTravelBug integer default  0 not null, HasUserNote integer default 0 not null, LastFoundDate text default '' not null,
   LastGPXDate text default '' not null, LastLog text default '' not null, LastUserDate text default current_date  not null, Latitude text default '0.0' not null,
   Lock integer default 0 not null,LongHtm integer default 0 not null, Longitude text default '0.0' not null, MacroFlag integer default 0 not null,
   MacroSort text default '' not null, NumberOfLogs integer default 0 not null, OwnerId text default '' not null, OwnerName text default '' not null,
   PlacedDate text default current_date not null, ShortHtm integer default 0 not null, SmartName text default '' not null,SmartOverride integer default 0 not null,
   Source text default '' not null, State text default '' not null, Symbol text default '' not null, TempDisabled integer default 0 not null,
   Terrain real default 1.0 not null, UserData text default '' not null, User2 text default '' not null, User3 text default '' not null,
   User4 text default '' not null, UserFlag integer default 0 not null, UserNoteDate text default  '' not null, UserSort integer default 0 not null,
   Watch integer default 0 not null, IsOwner integer default 0 not null, LatOriginal text default '0.0' not null, LonOriginal text default '0.0' not null,
   Created text default current_date not null, Status text default 'A' not null, Color text default '' not null, ChildLoad integer default 0 not null,
   LinkedTo text default '' not null, GetPolyFlag integer default 0 not null,  Elevation real default 0.0 not null,Resolution text default '' not null,
   GcNote text default '' not null,IsPremium Integer default 0 not null,Guid text default '' not null,FavPoints Integer default 0 not null)]] },
    { "CacheMemo", [[(Code text default "" not null,LongDescription text default "" not null, ShortDescription text default "" not null,
Url text default "" not null,Hints text default "" not null,UserNote text default "" not null,TravelBugs text default "" not null)]] },
    { "Logs", [[(lParent not null,lLogId integer not null, lType, lBy, lDate date, lLat, lLon, lEncoded boolean, lownerid integer, lHasHtml boolean, lIsowner boolean, lTime text)]] },
    { "LogMemo", [[(lParent ,lLogId integer, lText default "")]] },
    { "Waypoints", [[(cParent not null,cCode not null, cPrefix, cName, cType, cLat, cLon, cByuser boolean, cDate date, cFlag boolean, sB1 boolean)]] },
    { "WayMemo", [[(cParent,cCode,cComment default "", cUrl default "")]] },
    { "Attributes", [[(aCode text, aId integer, aInc integer)]] },
    { "Corrected", [[(kCode not null,kBeforeLat , kBeforeLon , kBeforeState, kBeforeCounty, kAfterLat,kAfterLon,kAfterState, kAftercounty)]] },
    { "CacheImages", [[(iCode text default '' not null, iName text default '' not null, iDescription text default '' not null, iGuid text default '' not null, iImage text default '' not null)]] },
    { "LogImages", [[(iCode text default '' not null, iLogid Integer default 0, iName text default '' not null, iDescription text default '' not null, iGuid text default '' not null,iImage text default '' not null)]] },
}

-- Unique keys first, so INSERT OR IGNORE drops a duplicate instead of
-- failing the index afterwards. GDAK's own inserts rely on the same keys.
local UNIQUE_INDEXES = {
    "CREATE UNIQUE INDEX macro.CachesCode on Caches (code)",
    "CREATE UNIQUE INDEX macro.MemoCode on CacheMemo (code)",
    "CREATE UNIQUE INDEX macro.logkey on Logs (lparent,llogid)",
    "CREATE UNIQUE INDEX macro.logParent on LogMemo (lParent,lLogId)",
    "CREATE UNIQUE INDEX macro.waykey on Waypoints (cparent,ccode)",
    "CREATE UNIQUE INDEX macro.wayParent on WayMemo (cParent,cCode)",
    "CREATE UNIQUE INDEX macro.acode on Attributes (aCode,aId)",
    "CREATE UNIQUE INDEX macro.corcode on Corrected (kcode)",
}
-- The rest after the data, which is faster.
local OTHER_INDEXES = {
    "CREATE INDEX macro.CachesSmart on Caches (smartname collate nocase)",
    "CREATE INDEX macro.LatLon_String on Caches (Latitude,Longitude)",
    "CREATE INDEX macro.CacheImagesI1 on CacheImages (iCode)",
    "CREATE INDEX macro.LogImagesI1 on LogImages (iCode,iLogId)",
}

-- ── OpenSAK → GSAK values ───────────────────────────────────────────────────

-- The reverse of GSAK_CACHE_TYPE_MAP in importer/gsak_importer.py. D is
-- GSAK's "Groundspeak Lost and Found Celebration", today's Geocaching HQ
-- Celebration. Custom waypoints (Waypoint, Hotel/POI) become O (Other).
local CACHE_TYPE = [[CASE c.cache_type
    WHEN 'Traditional Cache' THEN 'T'
    WHEN 'Multi-cache' THEN 'M'
    WHEN 'Unknown Cache' THEN 'U'
    WHEN 'Letterbox Hybrid' THEN 'B'
    WHEN 'Webcam Cache' THEN 'W'
    WHEN 'Virtual Cache' THEN 'V'
    WHEN 'Event Cache' THEN 'E'
    WHEN 'Cache In Trash Out Event' THEN 'C'
    WHEN 'Earthcache' THEN 'R'
    WHEN 'Wherigo Cache' THEN 'I'
    WHEN 'Locationless (Reverse) Cache' THEN 'L'
    WHEN 'Benchmark' THEN 'G'
    WHEN 'Lab Cache' THEN 'Q'
    WHEN 'Project A.P.E. Cache' THEN 'A'
    WHEN 'Geocaching HQ Cache' THEN 'H'
    WHEN 'Giga-Event Cache' THEN 'J'
    WHEN 'Geocaching HQ Block Party' THEN 'P'
    WHEN 'Geocaching HQ Celebration' THEN 'D'
    WHEN 'GPS Adventures Maze' THEN 'X'
    WHEN 'Mega-Event Cache' THEN 'Z'
    WHEN 'Community Celebration Event' THEN 'F'
    ELSE CASE
        WHEN c.cache_type LIKE '%mystery%' OR c.cache_type LIKE '%unknown%' THEN 'U'
        WHEN c.cache_type LIKE '%earth%' THEN 'R'
        WHEN c.cache_type LIKE '%multi%' THEN 'M'
        WHEN c.cache_type LIKE '%tradi%' THEN 'T'
        WHEN c.cache_type LIKE '%wherigo%' THEN 'I'
        WHEN c.cache_type LIKE '%letterbox%' THEN 'B'
        WHEN c.cache_type LIKE '%mega%' THEN 'Z'
        WHEN c.cache_type LIKE '%giga%' THEN 'J'
        WHEN c.cache_type LIKE '%event%' THEN 'E'
        ELSE 'O' END
    END]]

-- GSAK's containers are OpenSAK's, except for caches without one: the GSAK
-- importer turns GSAK's "Virtual" (virtual and webcam caches) and
-- "Unknown" (the rest, mostly EarthCaches) into "Not chosen".
local CONTAINER = [[CASE
    WHEN COALESCE(c.container, '') IN ('', 'Not chosen') THEN
        CASE WHEN c.cache_type IN ('Virtual Cache', 'Webcam Cache') THEN 'Virtual' ELSE 'Unknown' END
    ELSE c.container END]]

-- A corrected cache: its user note has both corrected coordinates.
local IS_CORRECTED = "(n.is_corrected = 1 AND n.corrected_lat IS NOT NULL AND n.corrected_lon IS NOT NULL)"

-- GSAK's lLogId is the numeric geocaching.com log id, unique per cache.
-- OpenSAK keeps it as "<code>_<id>" (GSAK import) or "<id>" (GPX import);
-- anything else gets the negative OpenSAK row id, which cannot collide.
local LOG_ID = [[CASE
    WHEN instr(l.log_id, '_') > 0
         AND substr(l.log_id, instr(l.log_id, '_') + 1) <> ''
         AND substr(l.log_id, instr(l.log_id, '_') + 1) NOT GLOB '*[^0-9]*'
        THEN CAST(substr(l.log_id, instr(l.log_id, '_') + 1) AS INTEGER)
    WHEN l.log_id <> '' AND l.log_id NOT GLOB '*[^0-9]*' THEN CAST(l.log_id AS INTEGER)
    ELSE -l.id END]]

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function sql(query, params)
    return opensak.sql(query, params)
end

local function scalar(query, params)
    local row = opensak.sql(query, params)[1]
    if not row then return nil end
    for _, v in pairs(row) do return v end
end

-- The caches to export, by OpenSAK id: temp.gdak_sel(id). The range filter
-- of every batch uses its ids.
local function select_caches()
    sql("CREATE TEMP TABLE IF NOT EXISTS gdak_sel (id INTEGER PRIMARY KEY)")
    sql("DELETE FROM temp.gdak_sel")
    if not ONLY_ACTIVE_FILTER then
        sql("INSERT INTO temp.gdak_sel (id) SELECT id FROM main.caches")
        return
    end
    local codes = opensak.codes()
    local chunk = 500
    for first = 1, #codes, chunk do
        local params, marks = {}, {}
        for i = first, math.min(first + chunk - 1, #codes) do
            params[#params + 1] = codes[i]
            marks[#marks + 1] = "?"
        end
        sql("INSERT OR IGNORE INTO temp.gdak_sel (id) SELECT id FROM main.caches WHERE gc_code IN ("
            .. table.concat(marks, ",") .. ")", params)
    end
end

-- ── One batch of caches: every table ────────────────────────────────────────

-- :lo/:hi select one range of ids of temp.gdak_sel.
local RANGE = "s.id BETWEEN :lo AND :hi"

local STATEMENTS = {
    -- Caches. Coordinates are text, as in GSAK and GDAK.
    [[INSERT INTO macro.Caches (
        Code, Name, PlacedBy, Archived, CacheType, Changed, Container,
        County, Country, State, Difficulty, Terrain,
        DNF, DNFDate, Found, FoundByMeDate, FTF, FoundCount,
        HasCorrected, HasUserNote, UserNoteDate, LastFoundDate, LastLog, NumberOfLogs,
        Latitude, Longitude, LatOriginal, LonOriginal,
        LongHtm, ShortHtm, OwnerId, OwnerName, PlacedDate, Source,
        Status, TempDisabled, UserFlag, Watch, IsOwner, IsPremium,
        Created, LastGPXDate, LastUserDate, LinkedTo, GcNote, FavPoints)
    SELECT
        c.gc_code, c.name, COALESCE(c.placed_by, c.owner_name, ''), c.archived,
        ]] .. CACHE_TYPE .. [[,
        COALESCE(date(c.last_updated), date('now')),
        ]] .. CONTAINER .. [[,
        COALESCE(c.county, ''), COALESCE(c.country, ''), COALESCE(c.state, ''),
        COALESCE(c.difficulty, 1.0), COALESCE(c.terrain, 1.0),
        c.dnf, COALESCE(date(c.dnf_date), ''),
        c.found, COALESCE(date(c.found_date), ''), c.first_to_find, COALESCE(c.find_count, 0),
        CASE WHEN ]] .. IS_CORRECTED .. [[ THEN 1 ELSE 0 END,
        CASE WHEN COALESCE(n.note, '') <> '' THEN 1 ELSE 0 END,
        CASE WHEN COALESCE(n.note, '') <> '' THEN COALESCE(date(n.updated_at, 'localtime'), '') ELSE '' END,
        COALESCE(date(c.last_found_date), ''), COALESCE(date(c.last_log_date), ''), c.log_count,
        CAST(CASE WHEN ]] .. IS_CORRECTED .. [[ THEN n.corrected_lat ELSE c.latitude END AS TEXT),
        CAST(CASE WHEN ]] .. IS_CORRECTED .. [[ THEN n.corrected_lon ELSE c.longitude END AS TEXT),
        CAST(c.latitude AS TEXT), CAST(c.longitude AS TEXT),
        c.long_desc_html, c.short_desc_html,
        COALESCE(c.owner_id, ''), COALESCE(c.owner_name, ''),
        COALESCE(date(c.hidden_date), ''),
        CASE WHEN c.gc_code LIKE 'GC%' THEN 'GC' ELSE '' END,
        CASE WHEN c.archived THEN 'X' WHEN NOT c.available THEN 'T' ELSE 'A' END,
        CASE WHEN NOT c.archived AND NOT c.available THEN 1 ELSE 0 END,
        c.user_flag, c.watch, c.is_owner, c.premium_only,
        COALESCE(date(c.imported_at, 'localtime'), date('now')),
        COALESCE(date(c.last_gpx_update, 'localtime'), ''),
        COALESCE(date(c.last_user_update, 'localtime'), date('now')),
        COALESCE(c.parent_gc_code, ''), COALESCE(c.gc_note, ''), COALESCE(c.favorite_points, 0)
    FROM temp.gdak_sel s
    JOIN main.caches c ON c.id = s.id
    LEFT JOIN main.user_notes n ON n.cache_id = c.id
    WHERE ]] .. RANGE,

    -- CacheMemo (hints: GSAK keeps them decoded, as OpenSAK does)
    [[INSERT OR IGNORE INTO macro.CacheMemo (Code, LongDescription, ShortDescription, Url, Hints, UserNote)
    SELECT c.gc_code, COALESCE(c.long_description, ''), COALESCE(c.short_description, ''),
           COALESCE(c.url, ''), COALESCE(c.encoded_hints, ''), COALESCE(n.note, '')
    FROM temp.gdak_sel s
    JOIN main.caches c ON c.id = s.id
    LEFT JOIN main.user_notes n ON n.cache_id = c.id
    WHERE ]] .. RANGE,

    -- Corrected (GSAK's; GDAK itself uses LatOriginal/LonOriginal). OpenSAK
    -- has one state/county per cache (the one of its shown coordinates), so
    -- before and after both get it.
    [[INSERT OR IGNORE INTO macro.Corrected (kCode, kBeforeLat, kBeforeLon, kBeforeState, kBeforeCounty,
                                         kAfterLat, kAfterLon, kAfterState, kAftercounty)
    SELECT c.gc_code, CAST(c.latitude AS TEXT), CAST(c.longitude AS TEXT),
           COALESCE(c.state, ''), COALESCE(c.county, ''),
           CAST(n.corrected_lat AS TEXT), CAST(n.corrected_lon AS TEXT),
           COALESCE(c.state, ''), COALESCE(c.county, '')
    FROM temp.gdak_sel s
    JOIN main.caches c ON c.id = s.id
    JOIN main.user_notes n ON n.cache_id = c.id
    WHERE ]] .. RANGE .. " AND " .. IS_CORRECTED,

    -- Attributes
    [[INSERT OR IGNORE INTO macro.Attributes (aCode, aId, aInc)
    SELECT c.gc_code, a.attribute_id, CASE WHEN a.is_on THEN 1 ELSE 0 END
    FROM temp.gdak_sel s
    JOIN main.caches c ON c.id = s.id
    JOIN main.attributes a ON a.cache_id = c.id
    WHERE ]] .. RANGE,
}

-- Logs and LogMemo read the same rows; the inner query numbers them per
-- cache, newest first, for MAX_LOGS_PER_CACHE.
local LOG_ROWS = [[
    SELECT c.gc_code AS code, l.*, ]] .. LOG_ID .. [[ AS gsak_id
    FROM (SELECT l.*, ROW_NUMBER() OVER (PARTITION BY l.cache_id
                                         ORDER BY l.log_date DESC, l.id DESC) AS rn
          FROM temp.gdak_sel s JOIN main.logs l ON l.cache_id = s.id
          WHERE ]] .. RANGE .. [[) l
    JOIN main.caches c ON c.id = l.cache_id
    WHERE (:max_logs = 0 OR l.rn <= :max_logs)
    ORDER BY l.id]]

STATEMENTS[#STATEMENTS + 1] = [[
    INSERT OR IGNORE INTO macro.Logs (lParent, lLogId, lType, lBy, lDate, lLat, lLon,
                                      lEncoded, lownerid, lHasHtml, lIsowner, lTime)
    SELECT code, gsak_id, COALESCE(log_type, 'Write note'), COALESCE(finder, ''),
           COALESCE(date(log_date), ''),
           COALESCE(CAST(latitude AS TEXT), ''), COALESCE(CAST(longitude AS TEXT), ''),
           CASE WHEN text_encoded THEN 1 ELSE 0 END,
           CASE WHEN finder_id <> '' AND finder_id NOT GLOB '*[^0-9]*'
                THEN CAST(finder_id AS INTEGER) ELSE 0 END,
           0,
           CASE WHEN logged_by_owner THEN 1 ELSE 0 END,
           COALESCE(time(log_date), '')
    FROM (]] .. LOG_ROWS .. ")"

STATEMENTS[#STATEMENTS + 1] = [[
    INSERT OR IGNORE INTO macro.LogMemo (lParent, lLogId, lText)
    SELECT code, gsak_id, COALESCE(text, '') FROM (]] .. LOG_ROWS .. ")"

-- Waypoints and WayMemo: GSAK's cCode is unique per cache. GSAK-imported
-- waypoints keep theirs (wp_code); GPX-imported ones get prefix + the
-- cache code without "GC", as on geocaching.com. A code that repeats on
-- the same cache gets a number appended.
local WP_ROWS = [[
    SELECT c.gc_code AS parent, w.*,
           CASE WHEN w.rn = 1 THEN w.base ELSE w.base || w.rn END AS gsak_code
    FROM (SELECT w.*, ROW_NUMBER() OVER (PARTITION BY w.cache_id, w.base ORDER BY w.id) AS rn
          FROM (SELECT w.*, COALESCE(NULLIF(w.wp_code, ''),
                                     COALESCE(w.prefix, '') || substr(c2.gc_code, 3)) AS base
                FROM temp.gdak_sel s
                JOIN main.waypoints w ON w.cache_id = s.id
                JOIN main.caches c2 ON c2.id = w.cache_id
                WHERE ]] .. RANGE .. [[) w) w
    JOIN main.caches c ON c.id = w.cache_id
    ORDER BY w.id]]

STATEMENTS[#STATEMENTS + 1] = [[
    INSERT OR IGNORE INTO macro.Waypoints (cParent, cCode, cPrefix, cName, cType, cLat, cLon,
                                           cByuser, cDate, cFlag, sB1)
    SELECT parent, gsak_code, COALESCE(prefix, ''),
           COALESCE(NULLIF(name, ''), description, ''), COALESCE(NULLIF(wp_type, ''), 'Reference Point'),
           COALESCE(CAST(latitude AS TEXT), '0.0'), COALESCE(CAST(longitude AS TEXT), '0.0'),
           CASE WHEN created_by_user THEN 1 ELSE 0 END,
           COALESCE(date(wp_date), ''),
           CASE WHEN wp_flag THEN 1 ELSE 0 END,
           0
    FROM (]] .. WP_ROWS .. ")"

STATEMENTS[#STATEMENTS + 1] = [[
    INSERT OR IGNORE INTO macro.WayMemo (cParent, cCode, cComment, cUrl)
    SELECT parent, gsak_code, COALESCE(comment, ''), COALESCE(url, '') FROM (]] .. WP_ROWS .. ")"

-- ── Run ─────────────────────────────────────────────────────────────────────

local started = os.time()
local path = opensak.macro_db()
local function folder_of(p) return (p:gsub("\\", "/"):match("^(.*)/[^/]*$") or ""):lower() end
if folder_of(path) ~= opensak.temp_dir():gsub("\\", "/"):lower() then
    print("Note: not run from OpenSAK's temp folder, so the database is written next to the macro: "
          .. path .. " (copy this macro to " .. opensak.temp_dir() .. " and run it from there "
          .. "to keep it out of the macros folder)")
end

-- Replace what an earlier run left.
for i = #TABLES, 1, -1 do
    sql("DROP TABLE IF EXISTS macro." .. TABLES[i][1])
end
for _, t in ipairs(TABLES) do
    sql("CREATE TABLE macro." .. t[1] .. " " .. t[2])
end
for _, q in ipairs(UNIQUE_INDEXES) do sql(q) end
sql("PRAGMA macro.user_version = " .. GSAK_USER_VERSION)

select_caches()
local total = scalar("SELECT COUNT(*) FROM temp.gdak_sel") or 0
if total == 0 then
    print("No caches to export.")
    return
end
local lo_id = scalar("SELECT MIN(id) FROM temp.gdak_sel")
local hi_id = scalar("SELECT MAX(id) FROM temp.gdak_sel")

-- Batches of BATCH ids each (ids can have gaps, so a batch may hold fewer).
local steps = math.floor((hi_id - lo_id) / BATCH) + 1
local p = opensak.progress("Export to GDAK", steps)
local cancelled = false
local step = 0
for lo = lo_id, hi_id, BATCH do
    step = step + 1
    if not p:update(step, ("caches %d of %d"):format(math.min(step * BATCH, total), total)) then
        cancelled = true
        break
    end
    local params = { lo = lo, hi = lo + BATCH - 1, max_logs = MAX_LOGS_PER_CACHE }
    for _, q in ipairs(STATEMENTS) do
        -- Each statement uses only the names it has.
        local used = {}
        for name in pairs(params) do
            if q:find(":" .. name, 1, true) then used[name] = params[name] end
        end
        sql(q, used)
    end
end
p:close()

for _, q in ipairs(OTHER_INDEXES) do sql(q) end
sql("DROP TABLE IF EXISTS temp.gdak_sel")

if cancelled then
    print("Cancelled: " .. path .. " is incomplete, run the macro again.")
    return
end

-- ── Report ──────────────────────────────────────────────────────────────────

local function count(t) return scalar("SELECT COUNT(*) FROM macro." .. t) end
print(("Exported to %s in %d s:"):format(path, os.time() - started))
for _, t in ipairs({ "Caches", "CacheMemo", "Corrected", "Attributes", "Logs", "LogMemo", "Waypoints", "WayMemo" }) do
    print(("  %-10s %8d"):format(t, count(t)))
end
if count("Caches") ~= total then
    print(("Warning: %d caches selected, %d written."):format(total, count("Caches")))
end
if count("Logs") ~= count("LogMemo") or count("Waypoints") ~= count("WayMemo") then
    print("Warning: Logs/LogMemo or Waypoints/WayMemo row counts differ.")
end
print("On the phone, put it in GDAK's databases folder as <database name>/sqlite.db3 "
      .. "(rename the file to sqlite.db3, inside a folder named after the database).")
