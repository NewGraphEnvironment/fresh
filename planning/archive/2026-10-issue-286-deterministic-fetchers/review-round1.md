# Code-check round 1: #286 branch (08b19b7...HEAD)

## Checklist read

- code-check.md: every H3 under `## Mechanisms` (all 14), prose read with table rows and evidence blocks skipped. Rules-that-stand-alone and Security were covered from the index only.
- code-check-r.md: in full, these sections: "Postgres row order is never fixed unless the query fixes it...", "`sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words...", "Verify a float-formatting fix in its consumer, not through `as.numeric()`", "`identical()` on two reader results tests the reader, not the file", "A `function(...)` mock hides arguments the real callee no longer accepts", "A database driver's value is not a base R type — and it fails twice". That is 6 sections; the other ~109 were checked from the index only.
- code-check-infra.md: "A SQL function test that cannot fail: pruned columns and a function in `FROM`", "Function-as-join-predicate: index visibility depends on inlineability". 2 read, ~39 from the index only.
- code-check-spatial.md: "Canonicalize geometry before hashing it...", "sf: `st_intersection()` / `st_difference()` return a GEOMETRYCOLLECTION...", "sf: name validation must account for the geometry column". 3 read, ~90 from the index only.
- code-check-shell.md: nothing in it applies to this diff (no shell). All ~70 checked from the index only.

## Probes run (on a copy at $TMPDIR scratchpad/fresh_rev1, local fwapg: PostGIS 3.5.2, GEOS 3.9.0)

- Changed test files, run with `NOT_CRAN=true testthat::test_file()`. test-frs_fetch_sql.R: 42 pass. test-utils.R: 88 pass. test-frs_watershed_at_measure.R: 43 pass. test-frs_fetch_live.R: 19 pass. No failures, errors or skips.
- `sf::st_as_text(digits = 15)` on sf 1.1.2 keeps full BC Albers coordinates, where the default rounds x to whole metres. PostGIS parses `1e+06` WKT.
- An sf `aoi` (rounded to 15 digits) against the exact DB polygon (`aoi = list(blk, measure)`) for 3 watersheds. Streams, lakes and wetlands returned identical id sets (4459/172/909, 8876/423/1702 and 1704/65/430), so the 15-digit WKT does not change boundary-touch membership.
- `waterbody_poly_id` (lakes, wetlands) and `linear_feature_id` (streams) each have a unique primary-key index, so the default ORDER BY ends on a unique key.
- ORDER BY + LIMIT with a small bbox: the planner uses the GiST index and then sorts. It does not walk the PK index.
- The roxygen map-layer examples (ws at 25 m, then the lake, wetland and stream fetches with that `aoi`) all run. They return CRS 3005, no invalid or empty geometries, and streams stay LINESTRING.
- Simplified subbasin with a tributary upstream point (360873822/165115 to 360886221/838) gives 1 row named `geom`, MULTIPOLYGON like the unsimplified path, with area ratio 1.000064.
- Empty difference end to end through `frs_db_query()`: `intersects` arrives as logical, POLYGON EMPTY survives simplify and normalize, and the filter leaves 0 rows. `sf::st_difference()` also returns 0 rows for a covered polygon, so the comment's claim holds.
- Callers: no internal caller passes a custom `table` to the fetchers, and the `frs_watershed_split()` positional call is unaffected by the new trailing argument.

## Clean

No issues found.
