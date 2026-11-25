# Update location (current cache)

Looks up country, state and county for the cache selected in the list, from
both OpenSAK's offline boundary data and OpenStreetMap, shows the results side
by side and lets you pick what to keep. Unlike **Tools → Update location**, it
can also replace or clear a value that is wrong, one cache at a time.

## What it needs

- OpenSAK with macro API version 3 or newer
- **A beta build for the OpenStreetMap lookup** (`opensak.get_url` is
  beta-only until 1.23.0). On a stable build the macro still works, with the
  offline data only.
- Permissions: `write` — to save the values you pick to the cache.
- Network: `nominatim.openstreetmap.org` — OpenStreetMap's reverse geocoding
  service, asked once per run for the cache's coordinates.

## How to use it

1. Select a cache in the list.
2. Run the macro from **Macros → Macro manager…**.
3. If the cache has corrected coordinates, choose whether to look up the
   posted or the corrected ones.
4. A form shows what the cache has now and what the offline data and
   OpenStreetMap found. Fields where the two sources disagree are marked
   with ⚠.
5. For each field, keep the suggested value, pick another one, type your own,
   or choose **(empty)** to clear it.
6. Press OK. Only the fields you changed are written, and the changes are
   listed in the macro output.

## Settings

At the top of the macro file:

- `LANGUAGE` — `"en"` (default) gives English names where OpenStreetMap has
  them, matching the offline data (e.g. "Switzerland"); `""` gives local names
  (e.g. "Schweiz / Suisse / Svizzera / Svizra").
- `STATE_KEYS`, `COUNTY_KEYS` — which OpenStreetMap address fields are used
  for state and county, in order.
- `USE_ONLINE` — `false` skips OpenStreetMap.

## Changes

- 0.1 — first version
