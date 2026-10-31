# Findings — Fetchers: fix row order, and add simplify and a polygon extent, so map layers rebuild identically (#286)

## Issue context

**If we do it:** a script that draws map context from fresh (lakes, streams, wetlands, a watershed outline) gets the same `sf` back from the same FWA on every run. A rebuilt map file then changes only when the map does, and repos that hand-write these queries today can call fresh instead. **If we never do:** each repo keeps its own SQL for the same layers, with its own simplification and no fixed row order, and moving them onto fresh brings the churn with them.

## What the fetchers do now (main at 08b19b7)

- `frs_lake_fetch()`, `frs_stream_fetch()` and `frs_wetland_fetch()` build `SELECT … FROM <table> WHERE …` with no `ORDER BY`, so rows come back in whatever order PostgreSQL returns them. In NewGraphEnvironment/wet#155, two rebuilds of one map's lake layer returned the same 49 lakes in a different order.
- There is no simplification option. A caller drawing a map either pulls full-resolution geometry and simplifies it in R, or writes its own SQL to simplify in the database.
- The extent is a bbox only, filtered with `geom && ST_MakeEnvelope(...)`. That is envelope overlap, so a feature whose envelope touches the box comes back even when the feature doesn't, and a map extent or AOI polygon can't be passed.
- `frs_watershed_at_measure()` returns fwapg's polygon unchanged. Callers that draw it simplify it themselves, each in its own way (`ST_Simplify` at 50, 100 or 200 m, or `ST_SimplifyPreserveTopology`).

On one machine's checkouts, about 20 repos query `fwa_lakes_poly` directly and 7 call `fwa_watershedatmeasure()` directly, through `sf::st_read(conn, query = ...)`. Outside fresh, only one repo calls `frs_lake_fetch()` or `frs_stream_fetch()`.

## Proposed

- [ ] End each fetch query with `ORDER BY` on the table's unique key (`waterbody_poly_id`, `linear_feature_id`). Any aggregate added later takes its input ordered (`ST_Union(geom ORDER BY …)`).
- [ ] An optional `simplify_m`: `ST_Normalize(ST_SimplifyPreserveTopology(geom, simplify_m))`, with `area_ha` taken before simplifying. `ST_Normalize()` puts the rings, the parts and each ring's vertices in a canonical order, so equal geometry serialises equally.
- [ ] An optional extent polygon (`sf`/`sfc` or WKT, EPSG:3005), filtered with `ST_Intersects()`, alongside `bbox`.
- [ ] The same `simplify_m` on `frs_watershed_at_measure()`.
- [ ] A test that two calls on the same database return `identical()` results.

**Known limit:** two databases running different GEOS versions can still simplify a ring differently. In wet#155's rebuilds, two lakes differed by one vertex each. Ordering can't fix that, so a caller that saves the result should record `postgis_full_version()` with it.

Relates to #30 (drop Z/M by default, which a caller drawing maps also wants). NewGraphEnvironment/wet#155 moves wet's map layers onto these fetchers once this lands.


## Plan-mode probes (2026-10-31, local fwapg: PostGIS 3.5.2, GEOS 3.9.0)

- Unique indexes: `fwa_lakes_poly_pkey (waterbody_poly_id)`, `fwa_wetlands_poly_pkey (waterbody_poly_id)`,
  `fwa_stream_networks_sp_pkey (linear_feature_id)`. Lakes 386,025 rows = distinct ids, 0 NULL;
  wetlands 375,178 = distinct.
- `ST_Normalize(LINESTRING ZM(5 5 1 10, 0 0 2 0))` → `LINESTRING Z (0 0 2,5 5 1)`: reversed, M dropped.
- `ST_SimplifyPreserveTopology(LINESTRING ZM(...), 0.5)` → `LINESTRING Z (...)`: M dropped.

## Line churn check (user's gate question), 2026-10-31

Script: one-off probe comparing `sf::st_as_binary()` row for row (local fwapg on two connections, and
local vs the shared bcfishpass instance). Local PostGIS GEOS 3.9.0; shared GEOS 3.10.2.

| layer | WSG | simplify_m | rows | WKB differ local x2 | WKB differ local vs shared |
|---|---|---|---|---|---|
| streams | BULK | 25 | 30,046 | 0 | 0 |
| streams | BULK | 100 | 30,046 | 0 | 0 |
| streams | MORR | 25 | 22,245 | 0 | 0 |
| streams | MORR | 100 | 22,245 | 0 | 0 |
| lakes | BULK | 25 | 1,754 | — | 46 (vertex count diff: -2 x1, -1 x27, +1 x18) |

- Streams (simplify only, no `ST_Normalize`) do not churn, even across GEOS versions. Row keys
  matched in order on both databases, so ORDER BY holds across them too.
- Lakes differ across GEOS by 1–2 vertices in 2.6% of polygons: the issue's known limit (wet#155 saw
  one vertex on two lakes). Vertex counts differ, so it is the simplification, not normalization.

## Plan review verdicts (review-286.md)

- Blocker 2 confirmed: `sf::st_as_text()` under `digits = 7` writes `POINT (1234568 456789.1)` for
  (1234567.891, 456789.123); `digits = 15` gives the full value. Fix in `.frs_resolve_aoi()`.
- Blocker 1 confirmed by reading `R/utils.R` (character branch is `&&`). Not changed (would also
  change `frs_extract()`); fetcher docs now say the WSG form is an envelope prefilter and point to
  `watershed_group_code`. Live test of `aoi` uses a polygon that a feature's envelope overlaps but
  the feature does not.
- Gap 1: `order_by` takes a vector. Gap 2: empty difference rows dropped to match `sf::st_difference`.
  Gap 3: new args moved after `limit`. Gap 4: NA-CRS aoi documented and tested; `area_ha_min` through
  `.frs_sql_num()`. Acceptance 2: NEWS says `limit = n` now returns the n lowest keys.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `function whse_basemapping.fwa_watershedatmeasure(numeric, integer) does not exist` for blue line key 356000000 | `sprintf("%s", <double>)` writes `3.56e+08`; write keys with `%d` + `as.integer()` (`.frs_watershedatmeasure_sql()`) |
