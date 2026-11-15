-- OpenSAK Macro
-- Name: OptimizePQs
-- Author: OokOok
-- Version: 1.0
-- Requires-API: 5
-- Description: A port of the GSAK macro PlacedPQ
-- Permissions: open
-- GSAK macro originally written by:  Lil Devil, Kai Team, lignumaqua, Clyde

-- Initialize Variables
maxPQsize = 1000
fromDate = "min"
toDate = ""
totalThisGroup = 0
pqNum = 1
outStr = ""

HTMLHeaderText=[[
<html><head>
<meta charset="utf-8">
<title>Optimized PQ Date Ranges</title>
<style type='text/css'>
body { font-family:'Arial'; }
table { margin-bottom: 1ex; }
th { padding:1px 2px; font-weight:normal; background-color:#CCCCFF; }
td { padding:1px 6px; vertical-align:top; }
tr { background-color:#FEF4D8; }
tr:nth-child(odd) { background-color:#CEF0D0; }
th, td:nth-child(4), td:nth-child(5) { text-align:center; }
td:nth-child(1) { text-align:right; }
</style>
<script type='text/javascript'>
var PQnodes = document.getElementsByTagName('a');


function makeBiggerCheckboxes() {
	var checkboxNodes = document.getElementsByTagName('input');
	for (var i=0; i < checkboxNodes.length; i++) {
		checkboxNodes[i].parentNode.addEventListener('click', function(ev) { if (ev.target.nodeName=='TD') { this.firstElementChild.click(); } }, false);
	}
}
</script></head>
<body onload='makeBiggerCheckboxes()'>
<table border='1'>
<tr><th colspan='5'>Optimized PQ Date Ranges</th></tr>
]]

	
----------
-- FORM --
----------
local function updateMaxLabel(f)
    f:set_label("MaxCachesLabel",
    "Maximum number of caches per Pocket Query: " .. (maxPQsize - f:get("bufferCombobox")))
end


local s = opensak.settings.load()
if opensak.shift_key() or s.runSilentCheckbox == nil or s.runSilentCheckbox == false then
    local v = opensak.form{
      title = "OptimizePQs",
      layout = "absolute",
      width = 384,
      height = 170,
      remember = true,
      on_open = updateMaxLabel,
      fields = {
        {
          type = "number",
          id = "bufferCombobox",
          x = 300,
          y = 30,
          w = 55,
          h = 24,
          default = s.bufferCombobox or 10,
          enabled = true,
          visible = true,
          italic = false,
          on_change = updateMaxLabel,
          exit_on_change = false,
          remember = true,
          min = 5,
          max = 20,
          step = 1,
        },
        {
          type = "label",
          id = "BufferLabel1",
          label = "Select the number of caches to subtract from the maximum",
          x = 12,
          y = 12,
          w = 350,
          h = 16,
        },
        {
          type = "label",
          id = "BufferLabel2",
          label = "to create a buffer for caches that are reactivated:",
          x = 12,
          y = 32,
          w = 292,
          h = 16,
        },
        {
          type = "label",
          id = "MaxCachesLabel",
          label = "",   -- filled in by updateMaxLabel at on_open and on_change
          x = 37,
          y = 68,
          w = 315,
          h = 16,
        },
        {
          type = "checkbox",
          id = "gcMonthCheckbox",
          label = "Show dates in geocaching.com format (Month dd yyyy)",
          x = 17,
          y = 98,
          w = 343,
          h = 20,
          default = s.gcMonthCheckbox or true,
          font_size = 10,
          remember = true,
        },
        {
          type = "checkbox",
          id = "runSilentCheckbox",
          label = "Run silently (if checked, hold down the Shift key to display this form)",
          x = 17,
          y = 128,
          w = 354,
          h = 20,
          font_size = 8,
          default = s.runSilentCheckbox or false,
          remember = true,
        },
      },
    }
    if not v then return end  -- cancelled
    s.bufferCombobox, s.gcMonthCheckbox, s.runSilentCheckbox = v.bufferCombobox, v.gcMonthCheckbox, v.runSilentCheckbox
    opensak.settings.save(s)
end

function HTMLHeader()
    local filterName = opensak.filter_name()
    if  filterName == "" then
        filterName = "Filter: None"
    else
        filterName = "Filter: " .. filterName
    end
    
-- From original GSAK macro PlacedPQ - not certain if this is still relevant or not.  Seems to work OK w/o it.
-- 	if $_FilterActive then
-- 		if SysInfo("JoinFilter") == "N" then
-- 			savedFilter = SaveFilter()
-- 			filterName = Extract(RegExData("SavedFilter.*",savedFilter,1),"=",2)
-- 			if filterName <> "" then
-- 				filterName = "Filter: " + filterName
-- 			else
-- 				filterName = "Unnamed Filter"
-- 			end
-- 		else
-- 			filterName = "Unnamed JOIN Filter"
-- 		end
-- 	end

    outStr = HTMLHeaderText
	outStr = outStr .. "<tr><th colspan='3'>Database: " .. opensak.database() .." &nbsp; &nbsp; " .. filterName .. "</th><th colspan='2'>Generated: ".. os.date("%m/%d/%Y") .."</th></tr>\n" 
 	outStr = outStr .. "<tr><th>PQ</th><th>From</th><th>To</th><th>Count</th><th>Done</th></tr>\n"
end


local function HTMLFooter()
	outStr = outStr .. "</table>\r\n"
	outStr = outStr .. "</body></html>\r\n"
end


local function OutputLine()
	pqString = string.format("%02d", pqNum)

	if fromDate == "min" then
		fromDateString = "Minimum date"
	else
        -- fromDate arrives as the # of seconds since the start of the epoch, so
	    -- we can directly convert that to a formatted string
		if s.gcMonthCheckbox then
		    fromDateString = opensak.date.format(fromDate, "%B %d, %Y")
		else
		    fromDateString = opensak.date.format(fromDate, "%m/%d/%Y")
		end
	end
		
	if toDate == "max" then
		toDateString = "Maximum date"
	else
		-- toDate arrives as a string and we are forced to first convert the 
		-- first 10 characters to the # of seconds since the start of the epoch
		-- and THEN confirm THAT into a date string
		toDateSec = opensak.date.parse(string.sub(toDate,1,10))
		if s.gcMonthCheckbox then
		    toDateString = opensak.date.format(toDateSec, "%B %d, %Y")
		else
		    toDateString = opensak.date.format(toDateSec, "%m/%d/%Y")
		end
	end
    
	outStr = outStr .. "<tr class=row><td>"..pqString.."</td><td>"..fromDateString.."</td><td>"..toDateString.."</td><td>"..totalThisGroup.."</td><td><input type='checkbox'></td></tr>\n" 
    return
end


----------
-- MAIN --
----------

-- Make sure there's at least ONE available cache in the DB
maxCaches = maxPQsize - tonumber(s.bufferCombobox)
rows = opensak.sql("SELECT count(*) as n FROM caches WHERE archived = 0")
if rows[1].n == 0  then
	print("No caches with a hidden date in " .. (DATABASE or opensak.database()) .. ".")
	exit()
end

-- generate the HTML header info
HTMLHeader()

-- Iterate through all caches and add chunks sharing the same hidden_date to a PQ until the PQ is "full"
for r in opensak.sql_each("SELECT hidden_date, count(*) AS qty FROM caches WHERE archived = 0 GROUP BY hidden_date ORDER BY hidden_date") do
	if totalThisGroup + r.qty <= maxCaches then
		-- add this chunk to the current PQ
		totalThisGroup = totalThisGroup + r.qty
		toDate = r.hidden_date
	else
	    -- close out the current PQ...
		OutputLine()

		-- ...and then start work on the next PQ
		pqNum = pqNum + 1
		totalThisGroup = r.qty    -- these are the caches we couldn't assign to the prior PQ
		fromDate = opensak.date.parse(toDate) + 60 * 60 * 24  -- move to next day and continue
		toDate = r.hidden_date    -- bogus assignment; will be recalc'ed to correct value next loop
    end
end

-- close out the final PQ
toDate = "max"
OutputLine()

-- close out HTML
HTMLFooter()

-- generate HTML file and display it
local path = opensak.write_text(opensak.temp_dir() .. "/OptimizePQs.html", outStr)
opensak.open(path)

