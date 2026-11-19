-- OpenSAK Macro --
-- Name: RoadSheet
-- Author: OokOok
-- Version: 1.0
-- Requires-API: 3
-- Description: Printable contact/road sheet HTML report for caches in the current filter.
-- Permissions: open

-- Ported from geo-mario's original RoadSheet macro originally written for GSAK.

local total = opensak.count()
if total == 0 then
    opensak.message("No caches in the current filter.", "RoadSheet")
    return
end

-- Helper: escape HTML special characters
local function esc(s)
    if s == nil then return "" end
    return tostring(s)
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;")
end

-- Helper: format decimal degrees to Geocaching DD° MM.MMM' (equivalent to GSAK FormatMinutes)
local function format_dm(lat, lon)
    if not lat or not lon then return "" end
    local function fmt(deg, pos_hemi, neg_hemi)
        local hemi = deg >= 0 and pos_hemi or neg_hemi
        local abs_deg = math.abs(deg)
        local d = math.floor(abs_deg)
        local m = (abs_deg - d) * 60
        return string.format("%s %02d° %06.3f'", hemi, d, m)
    end
    return fmt(lat, "N", "S") .. "<br>" .. fmt(lon, "E", "W")
end

-- Helper: build the 2x2 Last-4-Logs color grid (green = Found, red = DNF, yellow = Other, gray = Empty)
local function build_l4_grid(code)
    local ok, logs = pcall(opensak.logs, code)
    logs = (ok and type(logs) == "table") and logs or {}

    local cells = {}
    for i = 1, 4 do
        local log = logs[i]
        if log then
            local ltype = tostring(log.type or log.log_type or "")
            local ldate = tostring(log.date or log.log_date or "")
            if ltype == "Found it" then
                cells[i] = string.format('<td class="l4-found" title="%s (%s)">y</td>', esc(ltype), esc(ldate))
            elseif ltype == "Didn't find it" then
                cells[i] = string.format('<td class="l4-dnf" title="%s (%s)">n</td>', esc(ltype), esc(ldate))
            else
                cells[i] = string.format('<td class="l4-other" title="%s (%s)">o</td>', esc(ltype), esc(ldate))
            end
        else
            cells[i] = '<td class="l4-empty">x</td>'
        end
    end

    return string.format(
        '<table class="l4-grid"><tr>%s%s</tr><tr>%s%s</tr></table>',
        cells[1], cells[2], cells[3], cells[4]
    )
end

-- Helper: normalize attribute name to Geocaching filename slug
local function attr_slug(raw)
    local s = tostring(raw or ""):lower()
    -- Common Geocaching attribute filename mappings if full names are returned
    local map = {
        ["dogs"] = "dogs",
        ["dogs allowed"] = "dogs",
        ["access or parking fee"] = "fee",
        ["climbing gear required"] = "rappelling",
        ["boat required"] = "boat",
        ["scuba gear required"] = "scuba",
        ["recommended for kids"] = "kids",
        ["takes less than an hour"] = "onehour",
        ["scenic view"] = "scenic",
        ["significant hike"] = "hiking",
        ["difficult climbing"] = "climbing",
        ["may require wading"] = "wading",
        ["may require swimming"] = "swimming",
		["may require snowshoes"] = "snowshoes",
		["may require cross country skis"] = "skiis",
        ["available at all times"] = "available",
        ["available 24/7"] = "available",
        ["recommended at night"] = "night",
        ["available during winter"] = "winter",
        ["poison plants"] = "poisonoak",
        ["dangerous animals"] = "dangerousanimals",
        ["ticks"] = "ticks",
        ["abandoned mine"] = "mine",
        ["ticks"] = "ticks",
        ["cliff / falling rocks"] = "cliff",
        ["hunting"] = "hunting",
        ["dangerous area"] = "danger",
        ["wheelchair accessible"] = "wheelchair",
        ["parking nearby"] = "parking",
        ["public transportation nearby"] = "public",
        ["drinking water nearby"] = "water",
        ["public restrooms nearby"] = "restrooms",
        ["telephone nearby"] = "phone",
        ["picnic tables nearby"] = "picnic",
        ["camping nearby"] = "camping",
        ["bicycles"] = "bicycles",
        ["motorcycles"] = "motorcycles",
        ["quads"] = "quads",
        ["off-road vehicles / jeeps"] = "jeeps",
        ["snowmobiles"] = "snowmobiles",
        ["horses"] = "horses",
        ["campfires"] = "campfires",
        ["thorns"] = "thorns",
        ["stealth required"] = "stealth",
        ["stroller accessible"] = "stroller",
        ["needs maintenance"] = "firstaid",
        ["livestock nearby"] = "cow",
        ["flashlight required"] = "flashlight",
        ["lost and found tour"] = "landf",
        ["trucks / rvs"] = "rv",
        ["field puzzle"] = "field_puzzle",
        ["uv light required"] = "uv",
        ["snowshoes"] = "snowshoes",
        ["cross country skis"] = "skiis",
        ["special tool required"] = "s-tool",
        ["night cache"] = "nightcache",
        ["park and grab"] = "parkngrab",
        ["abandoned structure"] = "abandonedbuilding",
        ["short hike (<1 km)"] = "hike_short",
        ["medium hike (1-10 km)"] = "hike_med",
        ["long hike (> 10 km)"] = "hike_long",
        ["fuel nearby"] = "fuel",
        ["food nearby"] = "food",
        ["wireless beacon"] = "wirelessbeacon",
        ["partnership cache"] = "partnership",
        ["seasonal access"] = "seasonal",
        ["recommended for tourists"] = "touristok",
        ["tree climbing required"] = "treeclimbing",
        ["yard (private residence)"] = "frontyard",
        ["teamwork required"] = "teamwork",
        ["geotour"] = "geotour",
        ["bonus cache"] = "bonuscache",
        ["power trail"] = "powertrail",
        ["challenge cache"] = "challengecache",
        ["geocaching.com solution checker"] = "hqsolutionchecker"
    }
    if map[s] then
        return map[s]
    end
    -- If already a slug or unknown name, clean spaces/slashes to match filename conventions
    s = s:gsub("%.png$", ""):gsub("%-yes$", ""):gsub("%-no$", "")
    s = s:gsub("[^a-z0-9_%-]", "")
    return s
end

-- Helper: build attributes icons (<attribute>-yes.png / <attribute>-no.png / <attribute>.png)
local function build_attributes(code)
    local ok, attrs = pcall(opensak.attributes, code)
    if not ok or type(attrs) ~= "table" or #attrs == 0 then
        return ""
    end

    local base_url = "https://geocaching.com/images/attributes/"
    local items = {}

    for _, a in ipairs(attrs) do
        local raw_name = tostring(a.slug or a.icon or a.name or a.attribute or a.id or "attribute-blank")
        local display_name = tostring(a.name or a.attribute or a.id or "Attr")
        local inc = (a.inc == true or a.inc == 1 or a.positive == true or a.yes == true)
        local slug = attr_slug(raw_name)
        local suffix = inc and "-yes" or "-no"
        local label = (inc and "+" or "-") .. display_name

        local primary_src = base_url .. slug .. suffix .. ".png"
        local fallback_src = base_url .. slug .. ".png"

        -- Falls back to <attribute>.png if -yes/-no fails, then to text if neither exists
        local onerror_js = string.format(
            "if(!this.dataset.tried){this.dataset.tried=1;this.src='%s';}else{this.outerHTML='<span class=\\'%s\\'>%s</span>';}",
            esc(fallback_src),
            inc and "attr-yes" or "attr-no",
            esc(label)
        )

        items[#items + 1] = string.format(
            '<img class="attr-icon" src="%s" alt="%s" title="%s" onerror="%s">',
            esc(primary_src),
            esc(label),
            esc(label),
            onerror_js
        )
    end
    return table.concat(items, "")
end

-- Build HTML document
local rows = {}
local idx = 0

local fields = {
    "code", "name", "type", "container", "lat", "lon", "corrected",
    "difficulty", "terrain", "owner", "placed_by", "last_log_date",
    "trackable_count", "hint", "url"
}

for c in opensak.caches{ fields = fields } do
    idx = idx + 1
    if idx % 10 == 0 or idx == 1 then
        opensak.progress(string.format("Processing cache %d / %d...", idx, total))
    end

    local lat = (c.corrected and c.corrected.lat) or c.lat
    local lon = (c.corrected and c.corrected.lon) or c.lon
    local coords_html = format_dm(lat, lon)
    if c.corrected then
        coords_html = "<strong>*</strong> " .. coords_html
    end

    local url = (c.url and c.url ~= "") and c.url or ("https://coord.info" .. tostring(c.code))
    local code_link = string.format('<a href="%s" target="_blank">%s</a>', esc(url), esc(c.code))

    local owner = c.owner or c.placed_by or ""
    local last_date = c.last_log_date and tostring(c.last_log_date):sub(1, 10) or ""
    local dt_str = string.format("D: %s<br>T: %s", tostring(c.difficulty or "?"), tostring(c.terrain or "?"))

    local l4_html = build_l4_grid(c.code)
    local attr_html = build_attributes(c.code)

    local hint_parts = {}
    if c.trackable_count and c.trackable_count > 0 then
        hint_parts[#hint_parts + 1] = string.format('<span class="tb-badge">[TB:%d]</span>', c.trackable_count)
    end
    if c.hint and c.hint ~= "" then
        local clean_hint = tostring(c.hint):gsub("\r\n", ", "):gsub("\n", ", ")
        hint_parts[#hint_parts + 1] = esc(clean_hint)
    end
    local hint_html = table.concat(hint_parts, " ")

	local short_type = ""
	if c.type:match("^([^ ]*)") == "Cache" then
		short_type = "CITO"
	else
		short_type = c.type:match("^([^ ]*)")
	end

    local row_html = string.format(
        '<tr>'
        .. '<td class="nowrap">%s</td>'
        .. '<td>%s</td>'
        .. '<td class="center">%s</td>'
        .. '<td class="center">%s</td>'
        .. '<td class="center">%s</td>'
        .. '<td>%s</td>'
        .. '<td class="center nowrap">%s</td>'
        .. '<td class="center nowrap">%s</td>'
        .. '<td class="center nowrap">%s</td>'
        .. '<td class="attrs">%s</td>'
        .. '<td class="hint">%s</td>'
        .. '</tr>',
        code_link,
        esc(c.name),
        esc(short_type),
        esc(c.container),
        l4_html,
        esc(owner),
        esc(last_date),
        coords_html,
        dt_str,
        attr_html,
        hint_html
    )
    rows[#rows + 1] = row_html
end

local title = string.format("RoadSheet - Number of caches in current filter: %d", total)

local html = string.format([[<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>%s</title>
<style>
  body { font-family: Arial, Helvetica, sans-serif; font-size: 11px; margin: 12px; color: #111; }
  h2 { font-size: 14px; margin: 0 0 8px 0; }
  table.sheet { width: auto; table-layout: auto; border-collapse: collapse; }
  table.sheet th, table.sheet td { border: 1px solid #888; padding: 3px 5px; vertical-align: middle; white-space: nowrap; }
  table.sheet th { background: #e6e9ef; font-weight: bold; text-align: center; }
  table.sheet tr:nth-child(even) { background: #f9fafb; }
  center { text-align: center; }
  .nowrap { white-space: nowrap; }
  table.sheet td:nth-child(10), .attrs { font-size: 10px; line-height: 1.2; max-width: 160px; white-space: normal; overflow-wrap: break-word; }
  .attr-icon { width: 18px; height: 18px; margin: 1px; vertical-align: middle; }
  .attr-yes { color: #155724; margin-right: 3px; display: inline-block; }
  .attr-no { color: #721c24; text-decoration: line-through; margin-right: 3px; display: inline-block; }
  table.sheet td:nth-child(11), .hint { font-size: 10px; max-width: 200px; white-space: normal; overflow-wrap: break-word; }
  .tb-badge { background: #fff3cd; border: 1px solid #ffeeba; padding: 0 3px; font-weight: bold; }
  table.l4-grid { border-collapse: collapse; margin: 0 auto; }
  table.l4-grid td { width: 9px; height: 9px; padding: 0; font-size: 7px; text-align: center; border: 1px solid #555; }
  .l4-found { background: #28a745; color: #28a745; }
  .l4-dnf { background: #dc3545; color: #dc3545; }
  .l4-other { background: #ffc107; color: #ffc107; }
  .l4-empty { background: #adb5bd; color: #adb5bd; }
  @media print {
    @page { size: landscape; }
    body { margin: 4mm; }
    a { color: #000; text-decoration: none; }
  }
</style>
</head>
<body>
<h2>%s</h2>
<table class="sheet">
  <thead>
    <tr>
      <th>Code</th>
      <th>Name</th>
      <th>Type</th>
      <th>Size</th>
      <th>L4</th>
      <th>Owner</th>
      <th>Last Log</th>
      <th>Coordinates</th>
      <th>D / T</th>
      <th>Attributes</th>
      <th>Hint</th>
    </tr>
  </thead>
  <tbody>
%s
  </tbody>
</table>
</body>
</html>
]], esc(title), esc(title), table.concat(rows, "\n"))


local out_path = opensak.temp_dir() .. "/roadsheet.html"
opensak.write_text(out_path, html)
opensak.open(out_path)