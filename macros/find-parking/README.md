# Find parking for the selected cache

Finds parking places near the selected cache in OpenStreetMap and saves the
one you pick as a **Parking Area** waypoint on the cache. The waypoint then
shows on the map and in the Waypoints tab, and goes with the cache in GPX and
GGZ exports to your GPS.

An optional map page shows the cache and the parking places together, with a
prompt for an AI chat (Claude, ChatGPT or Le Chat) that reads the listing and
tells you which parking place the owner means.

## What it needs

- OpenSAK 1.23.0 or newer (macro API 5): the macro uses `opensak.get_url()`,
  and from 1.23.0 a Pocket Query import keeps the waypoints you added yourself
- Permissions:
  - `write` — to add (or move) the parking waypoint on the cache
  - `open` — to open the map page in your browser
- Web sites: `overpass-api.de` and, if that one is busy, `maps.mail.ru` and then
  `overpass.private.coffee`. These are public servers for querying
  OpenStreetMap (`maps.mail.ru` is run by the Russian company VK). The macro
  sends them only a search area (the cache's coordinates and the search
  distance), never anything else about the cache or you.

The map page loads the map from `tile.openstreetmap.org` and the map library
(Leaflet) from `unpkg.com` in your browser. The AI prompt is only put on the
clipboard: nothing goes to an AI until you paste it there yourself.

## How to use it

1. Select a cache in the cache list and run the macro.
2. The form lists the parking places OpenStreetMap knows within 500 m of the
   cache (its corrected coordinates if it has them), nearest first, with
   distance, direction, name, fee and size when OpenStreetMap has them.
   Private parking is left out. Change **Search within** to look further away
   (up to 3 km); the macro remembers the distance for next time. The public
   OpenStreetMap servers are sometimes busy: then the form says so, and
   **Search again** tries once more.
3. If the cache already has a parking waypoint from the owner, the form says
   so, with its distance and direction.
4. Optional: click **Map and AI…** to see the parking places on a map. The
   page has buttons that open an AI chat with the prompt. Read the answer and
   pick the number it suggests in the form.
5. Pick a parking place, or **My own coordinates** to type them, adjust the
   waypoint name if you like, and click **Save waypoint**.

The waypoint gets the prefix `PX` (or `PY`, `PZ` if the cache already uses
`PX`). Owners mostly use `PK`, `P1`, `P2` …, so the macro's waypoint never gets
the same name on the GPS as the owner's. Run the macro again on the same cache
and it moves its waypoint instead of adding another one.

The waypoint's comment says it came from OpenStreetMap, with the details, and
its URL opens the parking place on openstreetmap.org.

## Servers

The public OpenStreetMap (Overpass) servers are often busy, so the macro
tries them one by one, the one that answered last time first. A server that
failed earlier in the same run is tried last when you click **Search again**.
The progress window shows which server it is waiting for, and **Cancel**
stops the search.

**Servers…** in the form shows how each server has done for you (how often
it answered, and how fast), lets you untick the ones you don't want and add
another Overpass server, e.g. one your club runs. Enter the address of its
interpreter, such as `https://example.org/api/interpreter`. OpenSAK asks
you before the macro contacts a server that isn't built in. A server you
added and untick again is removed.

The output pane shows each server's answer, e.g.
`overpass-api.de: HTTP 502 (0 s)` and `maps.mail.ru: 12 parking places in 8 s`.

## Notes

- OpenStreetMap is as good as its mappers: a small parking place by a forest
  road may be missing, and a mapped one may have changed. The listing and the
  owner's own parking waypoint are usually the best guide; the map page helps
  to compare.
- The settings at the top of the macro set the default distance, how many
  places are listed, the Overpass servers, the prefixes and the AI chats.

## Changes

- 0.4 — the server that answered last is tried first; Servers… dialog with statistics and own servers; Cancel stops the search; 30 s per server
- 0.3 — maps.mail.ru instead of overpass.osm.jp, which no longer exists
- 0.2 — a third server, a busy server is tried twice, shorter waits, Search again button
- 0.1 — first version
