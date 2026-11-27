-- OpenSAK Macro
-- Name: Find parking for the selected cache
-- Author: AgreeDK
-- Version: 0.4
-- Requires-API: 5
-- Description: Finds parking places near the selected cache in OpenStreetMap, lets you pick one (on a map, or with help from an AI chat) and saves it as a Parking Area waypoint
-- Permissions: write, open
-- Network: overpass-api.de, maps.mail.ru, overpass.private.coffee
-- Headless: no
--
-- Select a cache in the cache list and run the macro. It looks up the
-- parking places OpenStreetMap knows around the cache (its corrected
-- coordinates if it has them) and lists them, nearest first, with distance,
-- direction and what OpenStreetMap says about them (name, fee, size).
--
-- Pick one and click "Save waypoint": the macro adds it to the cache as a
-- waypoint of type Parking Area. It then shows on the map, in the Waypoints
-- tab and goes with the cache in GPX and GGZ exports to your GPS. You can
-- also type your own coordinates instead.
--
-- "Map and AI…" opens a page in your browser with the cache and the parking
-- places on a map. The page also has a prompt for an AI chat (Claude,
-- ChatGPT, Le Chat) with the listing text and the numbered parking places,
-- so the AI can tell you which one the listing points to. The prompt is put
-- on the clipboard; nothing leaves your computer until you paste it there
-- yourself. Read the AI's answer, then pick the number in the form.
--
-- The macro uses a prefix cache owners rarely use (PX, see PREFIXES), so
-- its waypoint never shares a name on the GPS with the owner's own parking
-- waypoint. Run it again on the same cache and it moves its own waypoint
-- instead of adding a second one. Waypoints you add yourself survive the
-- next Pocket Query import (OpenSAK 1.23.0 and newer).
--
-- The public OpenStreetMap servers are often busy. The macro tries them one
-- by one, the one that answered last time first. "Servers…" shows how each
-- of them has done for you, lets you untick the ones you don't want and add
-- another server; OpenSAK asks you before the macro contacts a server that
-- isn't built in.

-- ── Settings ────────────────────────────────────────────────────────────────

-- Search radius when the macro runs for the first time, in metres. The form
-- lets you change it; the macro remembers your last value.
local DEFAULT_RADIUS = 500
local MAX_RADIUS = 3000

-- At most this many parking places are listed, nearest first.
local MAX_CANDIDATES = 15

-- Built-in Overpass servers (the OpenStreetMap query service). The one that
-- answered last time is tried first, then these in this order, and the
-- ones that failed earlier in the same run last. "Servers…" in the form
-- turns them off and adds others. A built-in server must also be on the
-- Network line in the header.
-- A busy answer (HTTP 429, 502, 503 or 504) is tried once more on the same
-- server before the next one. The main server comes first: it answers at
-- once, also when it is too busy. The one that tends to time out comes last.
local OVERPASS = {
    "https://overpass-api.de/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
}
-- Seconds to wait for each server. The progress window has a Cancel button
-- to stop waiting sooner.
local TIMEOUT = 30
local BUSY = { [429] = true, [502] = true, [503] = true, [504] = true }

-- Prefixes for the macro's own waypoint: the first one the cache doesn't
-- already use for something else. Owners mostly use PK, P1, P2 … for their
-- parking waypoints, so these are left to them.
local PREFIXES = { "PX", "PY", "PZ" }

-- Parking places with these access values are left out.
local SKIP_ACCESS = { private = true, no = true }

-- The AI chats on the map page. With `prefill` the prompt is added to the
-- link as ?q=…, so the chat opens with the prompt filled in.
local AIS = {
    { name = "Claude",            url = "https://claude.ai/new",        prefill = true },
    { name = "ChatGPT",           url = "https://chatgpt.com/",         prefill = true },
    { name = "Le Chat (Mistral)", url = "https://chat.mistral.ai/chat", prefill = true },
}
-- A long listing makes the link too long; then the chat opens empty and
-- you paste the prompt from the clipboard.
local MAX_LINK_CHARS = 7000

-- ── Helpers ─────────────────────────────────────────────────────────────────

local TITLE = "Find parking"
local OWN = "My own coordinates"
local PARKING = "Parking Area"

-- One return value only: gsub also returns a count, which would otherwise
-- be passed on as an extra argument (e.g. to opensak.coords.parse).
local function trim(s)
    return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function tidy(s)
    s = (s or ""):gsub("\r\n", "\n"):gsub("[ \t]+\n", "\n"):gsub("\n\n\n+", "\n\n")
    return trim(s)
end

local function as_text(text, is_html)
    if not text or text == "" then return "" end
    if is_html then text = opensak.text.html_to_text(text) end
    return tidy(text)
end

-- 0.142 km -> "140 m", 1.234 km -> "1.2 km"
local function metres(km)
    if km < 1 then
        return string.format("%d m", math.floor(km * 100 + 0.5) * 10)
    end
    return string.format("%.1f km", km)
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local function compass(deg)
    return COMPASS[math.floor(((deg % 360) + 22.5) / 45) % 8 + 1]
end

local function contains(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

-- ── The cache ───────────────────────────────────────────────────────────────

local c = opensak.current()
if not c then
    opensak.message("Select a cache in the cache list first.", TITLE)
    return
end

local lat, lon, where = c.lat, c.lon, "posted coordinates"
if c.corrected then
    lat, lon, where = c.corrected.lat, c.corrected.lon, "corrected coordinates"
end

-- The cache's own parking waypoints, and the macro's own one from an
-- earlier run (a Parking Area with one of PREFIXES), which a new pick moves.
local existing, mine = {}, nil
local used_prefixes = {}
for _, w in ipairs(opensak.waypoints(c.code) or {}) do
    local prefix = (w.prefix or ""):upper()
    used_prefixes[prefix] = true
    if w.type == PARKING then
        if contains(PREFIXES, prefix) and not mine then
            mine = w
        else
            existing[#existing + 1] = w
        end
    end
end

local prefix = mine and mine.prefix
if not prefix then
    for _, p in ipairs(PREFIXES) do
        if not used_prefixes[p] then prefix = p break end
    end
end
if not prefix then
    opensak.message(string.format(
        "%s already has waypoints with the prefixes %s.\n\n"
        .. "Add another prefix to PREFIXES at the top of the macro.",
        c.code, table.concat(PREFIXES, ", ")), TITLE)
    return
end

-- ── OpenStreetMap ───────────────────────────────────────────────────────────

-- What OpenStreetMap says about a parking place, in a few words.
local function details(tags)
    local parts = {}
    local kind = tags.parking
    if kind == "underground" then parts[#parts + 1] = "underground"
    elseif kind == "multi-storey" then parts[#parts + 1] = "multi-storey"
    elseif kind == "street_side" or kind == "lane" or kind == "on_street" then
        parts[#parts + 1] = "street parking"
    end
    if tags.fee == "yes" then parts[#parts + 1] = "fee"
    elseif tags.fee == "no" then parts[#parts + 1] = "free" end
    if tags.access == "customers" then parts[#parts + 1] = "customers only" end
    if tags.capacity and tags.capacity:match("^%d+$") then
        parts[#parts + 1] = tags.capacity .. " spaces"
    end
    if tags.maxstay then parts[#parts + 1] = "max stay " .. tags.maxstay end
    return table.concat(parts, ", ")
end

-- ── Servers ─────────────────────────────────────────────────────────────────

-- saved.custom: servers the user added; saved.off: unticked servers (URL ->
-- true); saved.last_ok: the server that answered last; saved.stats: per
-- server {ok =, fail =, secs =} (secs: seconds taken by the answers).
local saved = opensak.settings.load()
for _, key in ipairs({ "custom", "off", "stats" }) do
    if type(saved[key]) ~= "table" then saved[key] = {} end
end

local function host_of(url)
    return url:match("^https?://([^/:]+)") or url
end

local function all_servers()
    local list = {}
    for _, u in ipairs(OVERPASS) do list[#list + 1] = u end
    for _, u in ipairs(saved.custom) do
        if not contains(list, u) then list[#list + 1] = u end
    end
    return list
end

local failed_now = {}   -- servers that failed in this run: tried last

-- The servers to ask, in order: the one that answered last time, the rest
-- in list order, the ones that failed in this run last.
local function search_order()
    local first, rest, late = {}, {}, {}
    for _, u in ipairs(all_servers()) do
        if not saved.off[u] then
            if failed_now[u] then late[#late + 1] = u
            elseif u == saved.last_ok then first[#first + 1] = u
            else rest[#rest + 1] = u end
        end
    end
    for _, u in ipairs(rest) do first[#first + 1] = u end
    for _, u in ipairs(late) do first[#first + 1] = u end
    return first
end

local function record(server, ok, secs)
    local st = saved.stats[server]
    if type(st) ~= "table" then st = { ok = 0, fail = 0, secs = 0 } saved.stats[server] = st end
    if ok then
        st.ok = (st.ok or 0) + 1
        st.secs = (st.secs or 0) + secs
        saved.last_ok = server
        failed_now[server] = nil
    else
        st.fail = (st.fail or 0) + 1
        failed_now[server] = true
    end
end

local function parse(body)
    local okj, data = pcall(opensak.json.decode, body)
    if not (okj and type(data) == "table" and type(data.elements) == "table") then
        return nil
    end
    local found = {}
    for _, e in ipairs(data.elements) do
        local tags = e.tags or {}
        local plat = e.lat or (e.center and e.center.lat)
        local plon = e.lon or (e.center and e.center.lon)
        if plat and plon and not SKIP_ACCESS[tags.access or ""] then
            local km = opensak.coords.distance(lat, lon, plat, plon)
            found[#found + 1] = {
                lat = plat, lon = plon, km = km,
                dir = compass(opensak.coords.bearing(lat, lon, plat, plon)),
                name = trim(tags.name),
                details = details(tags),
                osm = string.format("%s/%s", e.type or "node", tostring(e.id)),
            }
        end
    end
    table.sort(found, function(a, b) return a.km < b.km end)
    while #found > MAX_CANDIDATES do table.remove(found) end
    return found
end

-- Asks the Overpass servers for parking within *radius* metres. Returns
-- the parking places nearest first and the host that answered, or nil and
-- an error text. Each server's result goes to the output pane and the
-- server statistics.
local function search(radius)
    local query = string.format(
        '[out:json][timeout:' .. TIMEOUT .. '];nwr["amenity"="parking"](around:%d,%.6f,%.6f);out center tags;',
        radius, lat, lon)
    local servers = search_order()
    if #servers == 0 then
        return nil, "No server is ticked: see Servers…"
    end
    local errors = {}
    for _, server in ipairs(servers) do
        local url = server .. (server:find("?", 1, true) and "&" or "?")
            .. "data=" .. opensak.text.url_encode(query)
        local host = host_of(server)
        local started = os.time()
        local ok, body, info
        for attempt = 1, 2 do
            ok, body, info = pcall(opensak.get_url, url,
                { timeout = TIMEOUT, caption = "Searching OpenStreetMap for parking (" .. host .. ")" })
            if not (ok and BUSY[info.status]) or attempt == 2 then break end
            opensak.sleep(2)
        end
        local secs = os.time() - started
        local found, why
        if not ok then
            -- the error repeats the long URL: say "the server" instead
            why = tostring(body):gsub("^opensak%.get_url: ", "")
                :gsub("https?://%S*[^%s:]", "the server")
            why = trim(why)
            -- the user stopped waiting: don't go on to the next server
            if why:find("cancelled", 1, true) then
                print(string.format("%s: cancelled after %d s", host, secs))
                return nil, host .. ": you cancelled the search"
            end
        elseif info.status ~= 200 then
            why = "HTTP " .. info.status
        else
            found = parse(body)
            if not found then why = "unreadable answer" end
        end
        record(server, found ~= nil, secs)
        if found then
            print(string.format("%s: %d parking place%s in %d s", host, #found,
                #found == 1 and "" or "s", secs))
            opensak.settings.save(saved)
            return found, nil, host
        end
        print(string.format("%s: %s (%d s)", host, why, secs))
        errors[#errors + 1] = host .. ": " .. why
    end
    opensak.settings.save(saved)
    return nil, table.concat(errors, "\n")
end

-- The "Servers…" dialog. Returns true when the list changed.
local function servers_dialog()
    local all = all_servers()
    local on, lines = {}, {}
    for _, u in ipairs(all) do
        if not saved.off[u] then on[#on + 1] = u end
        local st = saved.stats[u]
        local tries = type(st) == "table" and ((st.ok or 0) + (st.fail or 0)) or 0
        local text = host_of(u) .. ": "
        if tries == 0 then
            text = text .. "not tried yet"
        else
            text = text .. string.format("answered %d of %d times", st.ok or 0, tries)
            if (st.ok or 0) > 0 then
                text = text .. string.format(", in %d s on average",
                    math.floor((st.secs or 0) / st.ok + 0.5))
            end
        end
        if u == saved.last_ok then text = text .. " — answered last" end
        lines[#lines + 1] = opensak.html.escape(text)
    end
    local values = opensak.form{
        title = TITLE .. " — servers",
        fields = {
            { type = "label", label = "The macro asks these Overpass servers (OpenStreetMap's "
                .. "query service) for parking places, the one that answered last first.<br>"
                .. "Untick the ones you don't want to use." },
            { type = "checklist", id = "on", options = all, default = on },
            { type = "label", label = "<b>How they have done for you</b><br>"
                .. table.concat(lines, "<br>") },
            { type = "text", id = "add", label = "Add a server",
              placeholder = "https://example.org/api/interpreter" },
            { type = "label", label = "<i>OpenSAK asks you before the macro contacts a server "
                .. "that isn't built in. A server you added and untick is removed.</i>" },
        },
        validate = function(f)
            local add = trim(f:get("add"))
            if add ~= "" and not add:match("^https?://[^/%s]+/%S*$") then
                return "Enter the full address of the server's interpreter, "
                    .. "e.g. https://example.org/api/interpreter"
            end
            if add == "" and #(f:get("on") or {}) == 0 then
                return "Tick at least one server."
            end
        end,
    }
    if not values then return false end
    local ticked = {}
    for _, u in ipairs(values.on or {}) do ticked[u] = true end
    local add = trim(values.add)
    local custom, off = {}, {}
    for _, u in ipairs(OVERPASS) do
        if not ticked[u] then off[u] = true end
    end
    for _, u in ipairs(saved.custom) do
        if ticked[u] then custom[#custom + 1] = u end
    end
    if add ~= "" then
        if not contains(OVERPASS, add) and not contains(custom, add) then
            custom[#custom + 1] = add
        end
        off[add] = nil
        print("Added server " .. add)
    end
    saved.custom, saved.off = custom, off
    opensak.settings.save(saved)
    return true
end

local function label(i, p)
    local text = string.format("%d. %s %s", i, metres(p.km), p.dir)
    if p.name ~= "" then text = text .. " — " .. p.name end
    if p.details ~= "" then text = text .. " (" .. p.details .. ")" end
    return text
end

-- ── Map and AI page ─────────────────────────────────────────────────────────

local function prompt_for(candidates)
    local d = opensak.description(c.code) or {}
    local lines = {}
    local function add(s) lines[#lines + 1] = s or "" end

    add("I'm a geocacher going to the geocache below by car. Where should I park?")
    add("")
    if #candidates > 0 then
        add("Below is the cache listing and a numbered list of parking places from")
        add("OpenStreetMap near the cache. Please:")
        add("1. Tell me which number is the best place to park for this cache, and why.")
        add("   Use what the listing and the waypoints say (owners often say where to")
        add("   park, or where not to), the walking route to the cache and any access")
        add("   restrictions. Answer with the number first.")
        add("2. If the listing points to a place that is not in the list, say so and")
        add("   quote what the listing says about it.")
    else
        add("OpenStreetMap knows no parking places near the cache. Please tell me what")
        add("the listing and the waypoints say about parking or a good starting point.")
    end
    add("Don't invent coordinates: only use coordinates from the list, the waypoints")
    add("or the listing itself. Don't help with solving the cache, only with parking.")
    add("")
    add("=== THE CACHE ===")
    add(string.format("%s: %s (%s)", c.code, c.name, c.type or "?"))
    add(string.format("Cache coordinates (%s): %s", where, opensak.coords.format(lat, lon)))
    if c.terrain then add("Terrain: " .. tostring(c.terrain)) end
    local place = {}
    for _, p in ipairs({ c.county, c.state, c.country }) do
        if p and p ~= "" then place[#place + 1] = p end
    end
    if #place > 0 then add("Location: " .. table.concat(place, ", ")) end

    local wpts = opensak.waypoints(c.code) or {}
    if #wpts > 0 then
        add("")
        add("=== WAYPOINTS ===")
        for _, w in ipairs(wpts) do
            local at = (w.lat and w.lon) and opensak.coords.format(w.lat, w.lon) or "no coordinates"
            local text = trim(w.name or "")
            local extra = trim(w.comment or w.description or "")
            if extra ~= "" and extra ~= text then text = text .. " — " .. extra end
            add(string.format("- %s (%s): %s%s", w.prefix or "?", w.type or "?", at,
                text ~= "" and (" — " .. text) or ""))
        end
    end

    if #candidates > 0 then
        add("")
        add("=== PARKING PLACES FROM OPENSTREETMAP (distance and direction from the cache) ===")
        for i, p in ipairs(candidates) do
            add(string.format("%d. %s — %s %s%s%s", i, opensak.coords.format(p.lat, p.lon),
                metres(p.km), p.dir,
                p.name ~= "" and (" — " .. p.name) or "",
                p.details ~= "" and (" (" .. p.details .. ")") or ""))
        end
    end

    local short, long = as_text(d.short, d.html), as_text(d.long, d.html)
    add("")
    add("=== LISTING ===")
    if short ~= "" then add(short) add("") end
    add(long ~= "" and long or "(OpenSAK has no listing text for this cache.)")
    return table.concat(lines, "\n")
end

local function show_page(candidates)
    local prompt = prompt_for(candidates)
    opensak.set_clipboard(prompt)
    local esc = opensak.html.escape

    -- Points for the map: the cache, the cache's waypoints and the candidates.
    local points = {}
    points[#points + 1] = { lat = lat, lon = lon, kind = "cache",
        text = c.code .. " " .. c.name .. " (" .. where .. ")" }
    for _, w in ipairs(opensak.waypoints(c.code) or {}) do
        if w.lat and w.lon then
            points[#points + 1] = { lat = w.lat, lon = w.lon, kind = "wpt",
                text = (w.prefix or "") .. " " .. (w.type or "") .. ": " .. (w.name or "") }
        end
    end
    for i, p in ipairs(candidates) do
        points[#points + 1] = { lat = p.lat, lon = p.lon, kind = "parking", n = i,
            text = label(i, p) }
    end

    local buttons = {}
    for _, ai in ipairs(AIS) do
        local link = ai.url
        if ai.prefill then
            local full = ai.url .. (ai.url:find("?", 1, true) and "&" or "?")
                .. "q=" .. opensak.text.url_encode(prompt)
            if #full <= MAX_LINK_CHARS then link = full end
        end
        buttons[#buttons + 1] = string.format(
            '<a class="btn" href="%s" target="_blank" rel="noopener">Ask %s</a>',
            esc(link), esc(ai.name))
    end

    local body = string.format([[
<div id="map"></div>
<p class="legend"><span class="dot cache"></span> cache
 <span class="dot wpt"></span> waypoint
 <span class="dot parking">1</span> parking place from OpenStreetMap</p>
<h2>Ask an AI which one</h2>
<p>The prompt is on the clipboard. If the chat doesn't open with it filled in,
paste it (Ctrl+V, Cmd+V on a Mac). Then pick the number in OpenSAK's form.</p>
<p>%s
<button class="btn ghost" type="button" onclick="copyPrompt()">Copy the prompt again</button>
<span id="copied"></span></p>
<textarea id="prompt" readonly>%s</textarea>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
var points = %s;
var map = L.map("map");
L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
  maxZoom: 19, attribution: "&copy; OpenStreetMap contributors" }).addTo(map);
var bounds = [];
points.forEach(function (p) {
  var html = p.kind === "parking" ? String(p.n) : "";
  var icon = L.divIcon({ className: "pin " + p.kind, html: html, iconSize: [24, 24] });
  L.marker([p.lat, p.lon], { icon: icon }).addTo(map).bindPopup(p.text.replace(/[<&]/g,
    function (ch) { return ch === "<" ? "&lt;" : "&amp;"; }));
  bounds.push([p.lat, p.lon]);
});
if (bounds.length > 1) { map.fitBounds(bounds, { padding: [30, 30] }); }
else { map.setView(bounds[0], 16); }
function copyPrompt() {
  var t = document.getElementById("prompt");
  var done = function () { document.getElementById("copied").textContent = "Copied."; };
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(t.value).then(done, function () { t.select(); document.execCommand("copy"); done(); });
  } else { t.select(); document.execCommand("copy"); done(); }
}
</script>]], table.concat(buttons, "\n"), esc(prompt),
        (opensak.json.encode(points):gsub("</", "<\\/")))

    local css = [[
#map { height: 460px; border-radius: 6px; margin-bottom: .5em; }
.pin { border-radius: 50%; border: 2px solid #fff; box-shadow: 0 0 3px #0008;
       color: #fff; font: bold 12px/20px sans-serif; text-align: center; }
.pin.cache { background: #2e7d32; }
.pin.wpt { background: #6d6d6d; transform: scale(.7); }
.pin.parking { background: #1565c0; }
.legend .dot { display: inline-block; width: 16px; height: 16px; border-radius: 50%;
               vertical-align: middle; color: #fff; font: bold 10px/16px sans-serif;
               text-align: center; margin: 0 .2em 0 .8em; }
.legend .dot.cache { background: #2e7d32; } .legend .dot.wpt { background: #6d6d6d; }
.legend .dot.parking { background: #1565c0; }
.btn { display: inline-block; padding: .5em 1em; margin: .2em .5em .2em 0;
       border-radius: 6px; border: 1px solid #c96442; background: #c96442;
       color: #fff; text-decoration: none; font: inherit; cursor: pointer; }
.btn.ghost { background: transparent; color: inherit; }
#copied { opacity: .7; }
textarea { width: 100%; min-height: 18em; font: 13px/1.4 ui-monospace, Consolas, monospace;
           box-sizing: border-box; padding: .6em; }
]]

    local page = opensak.html.page{
        title = c.code .. " " .. c.name,
        subtitle = "Parking places from OpenStreetMap",
        css = css,
        body = body,
        footer = "Made by the OpenSAK macro \"Find parking for the selected cache\". "
            .. "Map data © OpenStreetMap contributors. Nothing is sent to an AI "
            .. "until you paste the prompt yourself.",
    }
    local path = opensak.write_text(opensak.temp_dir() .. "/find_parking_" .. c.code .. ".html", page)
    opensak.open(path)
end

-- ── The form ────────────────────────────────────────────────────────────────

local radius = tonumber(saved.radius) or DEFAULT_RADIUS
if radius < 50 or radius > MAX_RADIUS then radius = DEFAULT_RADIUS end

local candidates, err, answered = search(radius)
candidates = candidates or {}

local function options_for(list)
    local opts = {}
    for i, p in ipairs(list) do opts[#opts + 1] = label(i, p) end
    opts[#opts + 1] = OWN
    return opts
end

local function status_text(list, why, host)
    if why then
        return "<font color=\"#c62828\">OpenStreetMap could not be reached:</font><br>"
            .. opensak.html.escape(why):gsub("\n", "<br>")
            .. "<br>The public servers are often busy: try <b>Search again</b> in a moment."
    end
    if #list == 0 then
        return "OpenStreetMap knows no parking within this distance. Try a larger "
            .. "distance, or type your own coordinates."
    end
    return string.format("%d parking place%s from OpenStreetMap (%s), nearest first:",
        #list, #list == 1 and "" or "s", opensak.html.escape(host or "?"))
end

local intro = string.format("<b>%s</b> %s<br>Searching around the %s.",
    opensak.html.escape(c.code), opensak.html.escape(c.name), where)
if #existing > 0 then
    local names = {}
    for _, w in ipairs(existing) do
        local at = ""
        if w.lat and w.lon then
            at = string.format(" (%s %s)",
                metres(opensak.coords.distance(lat, lon, w.lat, w.lon)),
                compass(opensak.coords.bearing(lat, lon, w.lat, w.lon)))
        end
        names[#names + 1] = opensak.html.escape((w.prefix or "") .. " " .. (w.name or "") .. at)
    end
    intro = intro .. "<br>The cache already has a parking waypoint: "
        .. table.concat(names, "; ")
end
if mine then
    intro = intro .. string.format("<br>Your parking waypoint %s from an earlier run "
        .. "will be moved to the place you pick.", opensak.html.escape(mine.prefix))
end

local function picked(f)
    local value = f:get("pick")
    for i, p in ipairs(candidates) do
        if value == label(i, p) then return p end
    end
    return nil
end

-- Searches again with the distance in the form and updates the list.
local function refresh(f)
    local list, why, host = search(math.floor(f:get("radius")))
    candidates, err, answered = list or {}, why, host
    f:set_options("pick", options_for(candidates))
    local current = f:get("pick")
    if current == nil
            or (current == OWN and #candidates > 0 and trim(f:get("own")) == "") then
        f:set("pick", #candidates > 0 and label(1, candidates[1]) or OWN)
    end
    f:set_label("status", status_text(candidates, why, host))
    f:set_visible("own", f:get("pick") == OWN)
end

-- The form. "Servers…" closes it for the servers dialog, then it opens
-- again with the same choices (a form isn't opened from inside a form).
local values, button
local state = { radius = radius }
while true do
    local options = options_for(candidates)
    local pick = state.pick
    if not contains(options, pick)
            or (pick == OWN and #candidates > 0 and trim(state.own) == "") then
        pick = #candidates > 0 and label(1, candidates[1]) or OWN
    end
    local name = state.name
    if not name then
        name = (#candidates > 0 and candidates[1].name ~= "") and candidates[1].name or "Parking"
    end

    values, button = opensak.form{
        title = TITLE .. " — " .. c.code,
        fields = {
            { type = "label", label = intro },
            { type = "number", id = "radius", label = "Search within", default = state.radius,
              min = 50, max = MAX_RADIUS, step = 100, suffix = " m",
              on_change = function(f) refresh(f) end },
            { type = "label", id = "status", label = status_text(candidates, err, answered) },
            { type = "button", id = "again", label = "Search again",
              on_click = function(f) refresh(f) end },
            { type = "radio", id = "pick", options = options, default = pick,
              on_change = function(f, value)
                  f:set_visible("own", value == OWN)
                  local p = picked(f)
                  if p then f:set("name", p.name ~= "" and p.name or "Parking") end
              end },
            { type = "text", id = "own", label = "Coordinates", default = state.own or "",
              placeholder = "e.g. N55 40.123 E012 34.567",
              visible = pick == OWN },
            { type = "text", id = "name", label = "Waypoint name", default = name },
            { type = "button", id = "page", label = "Map and AI…",
              tooltip = "Show the parking places on a map, with a prompt for an AI chat",
              on_click = function(f) show_page(candidates) end },
        },
        buttons = {
            { id = "servers", label = "Servers…" },
            { id = "save", label = "Save waypoint", default = true },
            { id = "cancel", label = "Cancel", cancel = true },
        },
        validate = function(f, b)
            if b ~= "save" then return nil end
            if f:get("pick") == OWN then
                if not opensak.coords.parse(trim(f:get("own"))) then
                    return "Enter the coordinates of the parking place, e.g. N55 40.123 E012 34.567"
                end
            elseif not picked(f) then
                return "Pick a parking place."
            end
        end,
    }
    if not values or button ~= "servers" then break end
    state = values
    if servers_dialog() then
        local list, why, host = search(math.floor(values.radius))
        candidates, err, answered = list or {}, why, host
    end
end

if not values then return end
saved.radius = math.floor(values.radius)
opensak.settings.save(saved)
if button ~= "save" then return end

-- ── Save ────────────────────────────────────────────────────────────────────

local plat, plon, comment, url
if values.pick == OWN then
    plat, plon = opensak.coords.parse(trim(values.own))
    comment = "Added with the Find parking macro"
else
    local p
    for i, cand in ipairs(candidates) do
        if values.pick == label(i, cand) then p = cand end
    end
    plat, plon = p.lat, p.lon
    comment = "OpenStreetMap: amenity=parking"
    if p.details ~= "" then comment = comment .. " (" .. p.details .. ")" end
    url = "https://www.openstreetmap.org/" .. p.osm
end

local km = opensak.coords.distance(lat, lon, plat, plon)
local name = trim(values.name)
if name == "" then name = "Parking" end
local fields = {
    prefix = prefix, type = PARKING, name = name,
    lat = plat, lon = plon, comment = comment, url = url or false,
    description = string.format("%s %s of the cache (%s)", metres(km),
        compass(opensak.coords.bearing(lat, lon, plat, plon)), where),
}

if mine then
    opensak.update_waypoint(mine.id, fields)
else
    fields.url = url   -- nil instead of false: nothing to clear
    opensak.insert_waypoint(c.code, fields)
end

print(string.format("%s: %s parking waypoint %s %s, %s from the cache",
    c.code, mine and "moved" or "added", prefix,
    opensak.coords.format(plat, plon), metres(km)))
