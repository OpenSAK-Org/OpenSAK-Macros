-- OpenSAK Macro
-- Name: Ask AI about an earthcache
-- Author: AgreeDK
-- Version: 0.1
-- Requires-API: 5
-- Description: Turns the selected earthcache's listing into a prompt for an AI chat (Claude, ChatGPT, Le Chat or your own) that explains it in your language
-- Permissions: open
-- Headless: no
--
-- Select an earthcache in the cache list and run the macro. It collects what
-- OpenSAK knows about the cache (listing text, coordinates, elevation,
-- waypoints, attributes, hint, your own note and the latest logs), builds a
-- prompt from it and puts the prompt on the clipboard. Then it opens a page
-- in your browser with a button to the AI chat you chose: paste the prompt
-- there (Ctrl+V, Cmd+V on a Mac) if it isn't filled in already.
--
-- The first run asks which AI to use and which language it should answer
-- in. Tick "Don't ask again" to skip that question; hold Shift when you
-- start the macro to change your choice later.
--
-- The macro itself contacts no web site and sends nothing anywhere: the data
-- only leaves your computer when you paste it into the AI chat yourself.
--
-- The prompt asks the AI to help you understand the geology and what to look
-- for on site, not to hand you finished log answers: most earthcache owners
-- expect the answers to be your own observations.
--
-- Pictures in the listing are not part of the text. The page lists them, so
-- you can save one and drag it into the chat when it matters.

-- ── Settings ────────────────────────────────────────────────────────────────

-- The AI chats to choose from. `url` is the page the button opens; with
-- `prefill = true` the prompt is added to it as ?q=..., so the chat opens
-- with the prompt filled in. Add your own lines here if you like; "Other"
-- in the form takes any URL, and {prompt} in it is replaced by the prompt.
local AIS = {
    { name = "Claude",           url = "https://claude.ai/new",        prefill = true },
    { name = "ChatGPT",          url = "https://chatgpt.com/",         prefill = true },
    { name = "Le Chat (Mistral)", url = "https://chat.mistral.ai/chat", prefill = false },
}
local OTHER = "Other (my own URL)"

-- Offered in the form; you can also type any other language there.
local LANGUAGES = {
    "English", "Czech", "Danish", "Dutch", "French", "German", "Italian",
    "Norwegian", "Polish", "Portuguese", "Spanish", "Swedish",
}

local MAX_LOGS = 3                -- latest logs to include (0 = none)
local MAX_LOG_CHARS = 600         -- longer log texts are cut
-- A long listing makes the link too long to carry the prompt; then the link
-- opens an empty chat and you paste the prompt from the clipboard.
local MAX_LINK_CHARS = 7000

-- ── Helpers ─────────────────────────────────────────────────────────────────

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Plain text with at most one empty line in a row.
local function tidy(s)
    s = (s or ""):gsub("\r\n", "\n"):gsub("[ \t]+\n", "\n"):gsub("\n\n\n+", "\n\n")
    return trim(s)
end

local function as_text(text, is_html)
    if not text or text == "" then return "" end
    if is_html then text = opensak.text.html_to_text(text) end
    return tidy(text)
end

local function cut(s, max)
    if #s <= max then return s end
    return s:sub(1, max) .. " …"
end

local function rating(n)
    if not n then return "?" end
    return (n == math.floor(n)) and string.format("%d", n) or tostring(n)
end

-- ── The cache ───────────────────────────────────────────────────────────────

local c = opensak.current()
if not c then
    opensak.message("Select an earthcache in the cache list first.", "Ask AI")
    return
end

if not (c.type or ""):lower():find("earth") then
    if not opensak.confirm(string.format(
            "%s %s is a %s, not an earthcache.\n\nMake the earthcache prompt anyway?",
            c.code, c.name, c.type or "cache")) then
        return
    end
end

-- ── Which AI, which language ────────────────────────────────────────────────

local saved = opensak.settings.load()
local names = {}
for _, a in ipairs(AIS) do names[#names + 1] = a.name end
names[#names + 1] = OTHER

local function known(name)
    for _, n in ipairs(names) do if n == name then return true end end
    return false
end

if not (saved.ai and known(saved.ai) and saved.language and saved.dont_ask)
        or opensak.shift_key() then
    local values = opensak.form{
        title = "Ask AI about an earthcache",
        fields = {
            { type = "choice", id = "ai", label = "AI chat", options = names,
              default = known(saved.ai) and saved.ai or names[1],
              on_change = function(f, value) f:set_visible("url", value == OTHER) end },
            { type = "text", id = "url", label = "URL",
              default = saved.url or "",
              placeholder = "https://… ({prompt} is replaced by the prompt)",
              visible = saved.ai == OTHER },
            { type = "choice", id = "language", label = "Answer in",
              options = LANGUAGES, editable = true,
              default = saved.language or "English" },
            { type = "checkbox", id = "dont_ask",
              label = "Don't ask again (hold Shift when starting the macro to change this)",
              default = saved.dont_ask or false },
        },
        validate = function(f)
            if f:get("ai") == OTHER and not trim(f:get("url")):match("^https?://") then
                return "Enter the URL of the AI chat, starting with https://"
            end
            if trim(f:get("language")) == "" then
                return "Enter the language the answer should be in."
            end
        end,
    }
    if not values then return end
    saved = {
        ai = values.ai,
        url = trim(values.url),
        language = trim(values.language),
        dont_ask = values.dont_ask,
    }
    opensak.settings.save(saved)
end

local ai
for _, a in ipairs(AIS) do
    if a.name == saved.ai then ai = a end
end
if not ai then
    ai = { name = "the AI chat", url = saved.url, prefill = false }
end

local d = opensak.description(c.code) or {}
local short = as_text(d.short, d.html)
local long = as_text(d.long, d.html)

-- Pictures in the listing (only HTML listings have them).
local images = {}
if d.html then
    local seen = {}
    for _, part in ipairs({ d.short or "", d.long or "" }) do
        for _, src in ipairs(opensak.re.findall(part, [==[<img[^>]*?\bsrc\s*=\s*["']([^"']+)["']]==])) do
            src = opensak.text.html_decode(src)
            if src:match("^https?://") and not seen[src] then
                seen[src] = true
                images[#images + 1] = src
            end
        end
    end
end

-- ── The prompt ──────────────────────────────────────────────────────────────

local lines = {}
local function add(s) lines[#lines + 1] = s or "" end

add("I'm a geocacher preparing for an EarthCache. Please help me understand it.")
add("")
add("What I'd like from you:")
add("1. Explain the geology behind this EarthCache in plain language: what the")
add("   feature is, how it formed and why it looks the way it does here.")
add("2. Go through the owner's tasks/questions one by one. For each, explain the")
add("   concepts I need, and tell me exactly what to observe, measure or")
add("   photograph on site to answer it myself.")
add("3. Point out anything worth knowing before I go (safety, access, time of")
add("   day, tools such as a ruler, a compass or a magnifier).")
add("")
add("Please don't write finished log answers for me, and don't guess answers that")
add("depend on what is actually on site: the owner expects my own observations.")
add("Where a question is pure theory, explain it so I can write the answer in my")
add("own words. If something in the listing is unclear, say so instead of guessing.")
add("Answer in " .. saved.language .. ".")
add("")
add("=== THE CACHE ===")
add(string.format("%s: %s", c.code, c.name))
add(string.format("Type: %s · Difficulty %s · Terrain %s", c.type or "?",
    rating(c.difficulty), rating(c.terrain)))
if c.owner or c.placed_by then add("Owner: " .. (c.placed_by or c.owner)) end
add("Posted coordinates: " .. opensak.coords.format(c.lat, c.lon))
if c.corrected then
    add("My corrected coordinates: " .. opensak.coords.format(c.corrected.lat, c.corrected.lon))
end
local place = {}
for _, p in ipairs({ c.county, c.state, c.country }) do
    if p and p ~= "" then place[#place + 1] = p end
end
if #place > 0 then add("Location: " .. table.concat(place, ", ")) end
if c.elevation then add(string.format("Elevation: about %d m", math.floor(c.elevation + 0.5))) end
if c.hidden then add("Published: " .. c.hidden) end
if c.archived then
    add("Note: the cache is archived.")
elseif not c.available then
    add("Note: the cache is temporarily disabled.")
end

local attrs = {}
for _, a in ipairs(opensak.attributes(c.code) or {}) do
    local name = a.name or ("attribute #" .. tostring(a.attribute_id))
    attrs[#attrs + 1] = (a.on and "" or "NOT ") .. name
end
if #attrs > 0 then add("Attributes: " .. table.concat(attrs, "; ")) end

if c.hint and trim(c.hint) ~= "" then add("Hint: " .. trim(c.hint)) end

local wpts = opensak.waypoints(c.code) or {}
if #wpts > 0 then
    add("")
    add("=== WAYPOINTS ===")
    for _, w in ipairs(wpts) do
        local where = (w.lat and w.lon) and opensak.coords.format(w.lat, w.lon) or "no coordinates"
        local text = trim(w.name or "")
        local extra = trim(w.comment or w.description or "")
        if extra ~= "" and extra ~= text then text = text .. " — " .. extra end
        add(string.format("- %s (%s): %s%s", w.prefix or "?", w.type or "?", where,
            text ~= "" and (" — " .. text) or ""))
    end
end

add("")
add("=== LISTING ===")
if short ~= "" then add(short) add("") end
add(long ~= "" and long or "(OpenSAK has no listing text for this cache.)")

if #images > 0 then
    add("")
    add(string.format("(The listing has %d picture(s), not included here. I can send them if they matter.)", #images))
end

local note = trim(c.note)
if note ~= "" then
    add("")
    add("=== MY OWN NOTES ===")
    add(note)
end

if MAX_LOGS > 0 then
    local logs = opensak.logs(c.code) or {}
    table.sort(logs, function(a, b) return (a.date or "") > (b.date or "") end)
    local shown = 0
    for _, l in ipairs(logs) do
        if shown >= MAX_LOGS then break end
        local text = l.text or ""
        if l.encoded then text = opensak.text.rot13(text) end
        text = cut(as_text(text, text:find("<%a") ~= nil), MAX_LOG_CHARS)
        if text ~= "" then
            if shown == 0 then
                add("")
                add("=== LATEST LOGS (for conditions on site) ===")
            end
            shown = shown + 1
            add(string.format("- %s, %s: %s", (l.date or "?"):sub(1, 10), l.type or "?", text))
        end
    end
end

local prompt = table.concat(lines, "\n")

-- ── Clipboard and page ──────────────────────────────────────────────────────

opensak.set_clipboard(prompt)

local esc = opensak.html.escape
local link = ai.url
local prefilled = false
local with_prompt
if ai.url:find("{prompt}", 1, true) then
    with_prompt = ai.url:gsub("{prompt}", function() return opensak.text.url_encode(prompt) end)
elseif ai.prefill then
    with_prompt = ai.url .. (ai.url:find("?", 1, true) and "&" or "?")
        .. "q=" .. opensak.text.url_encode(prompt)
end
if with_prompt and #with_prompt <= MAX_LINK_CHARS then
    link, prefilled = with_prompt, true
elseif with_prompt then
    -- too long: open the chat without the prompt
    link = ai.url:gsub("[?&][^?&]*{prompt}.*$", "")
end

local body = {}
body[#body + 1] = string.format([[
<p class="lead">The prompt is on the clipboard.
%s</p>
<p><a class="btn" href="%s" target="_blank" rel="noopener">Open %s</a>
<button class="btn ghost" type="button" onclick="copyPrompt()">Copy the prompt again</button>
<span id="copied"></span></p>]],
    prefilled
        and "The chat should open with the prompt filled in. If it doesn't, paste it (Ctrl+V / Cmd+V)."
        or (with_prompt
            and "The listing is too long to send in the link: paste the prompt in the chat (Ctrl+V / Cmd+V)."
            or "Paste the prompt in the chat (Ctrl+V / Cmd+V)."),
    esc(link), esc(ai.name))

if #images > 0 then
    body[#body + 1] = "<h2>Pictures in the listing</h2>"
    body[#body + 1] = "<p>Not part of the prompt. Save one and drag it into the chat if it matters.</p><div class=\"pics\">"
    for _, src in ipairs(images) do
        body[#body + 1] = string.format(
            '<a href="%s" target="_blank" rel="noopener"><img src="%s" alt="" loading="lazy"></a>',
            esc(src), esc(src))
    end
    body[#body + 1] = "</div>"
end

body[#body + 1] = string.format([[
<h2>The prompt</h2>
<textarea id="prompt" readonly>%s</textarea>
<script>
function copyPrompt() {
  var t = document.getElementById("prompt");
  var done = function () { document.getElementById("copied").textContent = "Copied."; };
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(t.value).then(done, function () { t.select(); document.execCommand("copy"); done(); });
  } else {
    t.select(); document.execCommand("copy"); done();
  }
}
</script>]], esc(prompt))

local css = [[
.lead { font-size: 1.05em; }
.btn { display: inline-block; padding: .55em 1.1em; margin: .2em .6em .2em 0;
       border-radius: 6px; border: 1px solid #c96442; background: #c96442;
       color: #fff; text-decoration: none; font: inherit; cursor: pointer; }
.btn.ghost { background: transparent; color: inherit; }
#copied { opacity: .7; }
textarea { width: 100%; min-height: 28em; font: 13px/1.4 ui-monospace, Consolas, monospace;
           box-sizing: border-box; padding: .6em; }
.pics { display: flex; flex-wrap: wrap; gap: .5em; }
.pics img { max-height: 140px; max-width: 220px; border-radius: 4px; }
]]

local page = opensak.html.page{
    title = c.code .. " " .. c.name,
    subtitle = "Ask " .. ai.name .. " about this earthcache",
    css = css,
    body = table.concat(body, "\n"),
    footer = "Made by the OpenSAK macro \"Ask AI about an earthcache\". "
        .. "Nothing is sent anywhere until you paste the prompt yourself.",
}

local path = opensak.write_text(opensak.temp_dir() .. "/ask_ai_" .. c.code .. ".html", page)
opensak.open(path)
print(string.format("%s: prompt with %d characters on the clipboard%s, for %s in %s; page %s",
    c.code, #prompt, prefilled and " and in the link" or "", ai.name, saved.language, path))
