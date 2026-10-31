# What makes a fetch return the same `sf` twice

**Verified:** 2026-10-31 · **Issues:** #286 (spawned by wet#155) · **Produced by:** probes recorded in
`planning/archive/2026-10-issue-286-deterministic-fetchers/findings.md`; local fwapg PostGIS 3.5.2 /
GEOS 3.9.0, second fwapg GEOS 3.10.2.

## Row order

PostgreSQL fixes no row order unless the query does. Without `ORDER BY`, BULK lakes (1,754),
wetlands (3,684) and streams (32,472) all came back out of key order. The FWA tables carry
unique indexes on `waterbody_poly_id` (lakes, wetlands) and `linear_feature_id` (streams), so
ordering on them is total. fresh's own segmented tables repeat `linear_feature_id`, so they need
a second column (`order_by = c("linear_feature_id", "downstream_route_measure")`).

## Simplification

- `ST_SimplifyPreserveTopology()` and `ST_Normalize()` both drop M.
- `ST_Normalize()` reverses a line whose first vertex sorts after its last
  (`LINESTRING ZM(5 5 1 10, 0 0 2 0)` → `LINESTRING Z (0 0 2,5 5 1)`). FWA lines run downstream to
  upstream, so line layers simplify without normalizing.
- Streams simplified at 25 m and 100 m (BULK, MORR; 52,291 segments) were byte-identical (WKB)
  across two connections and across GEOS 3.9.0 and 3.10.2. Lines need no normalizing to repeat.
- Lakes simplified at 25 m (BULK, 1,754) differed across those GEOS versions by 1–2 vertices in
  46 polygons. The vertex counts differ, so it is the simplifier, not the normalization. Saving a
  simplified polygon layer means recording `postgis_full_version()` with it.
- A subbasin is simplified after `ST_Difference()`, once; simplifying the two watersheds first
  simplifies their shared boundary twice.

## Numbers written into SQL

- `sprintf("%s", <double>)` writes `3.56e+08` for blue line key 356000000. Postgres reads that as
  `numeric`, which matches no `fwa_watershedatmeasure(integer, double precision)`. Keys go in
  through `%d` of `as.integer()` (max FWA key 380,887,830 < 2^31).
- `%.10g` (`.frs_sql_num()`) rounds 2415.57257727526 to 2415.572577, below the segment that
  starts there; fwapg then picks the segment before, or returns nothing. 15 digits is not
  enough either: 88 FWA `upstream_route_measure` values reach the next segment's start at 15.
  Values compared against stored data go through `.frs_sql_exact()` (`%.17g`), which Postgres
  reads back exactly (2,000 of 2,000 random doubles).
- R's own `as.numeric()` is not correctly rounded on 17-digit text (1,612 of the same 2,000), so
  a round-trip test has to go through Postgres.
- `sf::st_as_text()` follows `getOption("digits")`; at the default 7 it rounds BC Albers x to the
  metre. `.frs_resolve_aoi()` passes `digits = 15`.
