# Update elevation (current cache)

Looks up the elevation of the cache selected in the list at two free
elevation services, shows the results side by side and lets you pick the
value to save. Useful for elevation challenges (e.g. "Mile High") and for
filtering and sorting on the **Elevation** column.

## What it needs

- **A beta build of OpenSAK 1.23.0** or newer (macro API 5;
  `opensak.get_url` is beta-only until 1.23.0 is released)
- Permissions: `write` — to save the elevation you pick to the cache.
- Network:
  - `api.opentopodata.org` — Open Topo Data, asked once per run
  - `api.open-meteo.com` — Open-Meteo, asked once per run

The coordinates of the cache are sent to these two services. Nothing else is.

## How to use it

1. Select a cache in the list.
2. Run the macro from **Macros → Macro manager…**.
3. If the cache has corrected coordinates, choose whether to look up the
   corrected (default) or the posted ones.
4. A form shows the elevation the cache has now and what each service
   found, with the elevation model and its resolution. If the two services
   differ by 20 m or more, the form warns you.
5. Keep the suggested value, pick another one, type your own, or choose
   **(empty)** to clear the elevation.
6. Press OK. The elevation is written only if it changed, and the change is
   listed in the macro output.

## Where the numbers come from

| Service | Elevation model | Resolution | Coverage |
|---|---|---|---|
| Open Topo Data | LINZ NZ DEM | 8 m | New Zealand |
| Open Topo Data | USGS NED | 10 m | USA |
| Open Topo Data | EU-DEM | 25 m | Europe |
| Open Topo Data | SRTM | 30 m | 60° N – 56° S |
| Open Topo Data | ASTER GDEM | 30 m | 83° N – 83° S |
| Open-Meteo | Copernicus GLO-90 | 90 m | Worldwide |

Open Topo Data uses the first model in the list that covers the point.
Elevation models measure the surface seen from above, so in a forest or a
city the value can include trees or buildings. Different services (and
Project-GC) can give a few metres' difference for the same point.

## Settings

At the top of the macro file:

- `USE_CORRECTED` — `true` (default) pre-selects the corrected coordinates,
  `false` the posted ones.
- `TOPO_DATASETS` — the Open Topo Data models to try, in order.
- `USE_OPENTOPODATA`, `USE_OPENMETEO` — `false` skips that service.

## Credits

Elevation data from [Open Topo Data](https://www.opentopodata.org) and
[Open-Meteo](https://open-meteo.com). Copernicus DEM GLO-90 © DLR e.V.
2010-2014 and © Airbus Defence and Space GmbH 2014-2018, provided under
COPERNICUS by the European Union and ESA, licensed CC BY 4.0. Open-Meteo's
free API is for non-commercial use.

## Changes

- 0.1 — first version (issue OpenSAK-Org/OpenSAK#526)
