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

## Errors Encountered

| Error | Resolution |
|-------|------------|
