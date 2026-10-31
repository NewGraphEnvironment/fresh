# Task: Fetchers: fix row order, and add simplify and a polygon extent, so map layers rebuild identically (#286)

**If we do it:** a script that draws map context from fresh (lakes, streams, wetlands, a watershed outline) gets the same `sf` back from the same FWA on every run. A rebuilt map file then changes only when the map does, and repos that hand-write these queries today can call fresh instead. **If we never do:** each repo keeps its own SQL for the same layers, with its own simplification and no fixed row order, and moving them onto fresh brings the churn with them.


## Context

`frs_lake_fetch()`, `frs_stream_fetch()`, `frs_wetland_fetch()` emit SQL with no `ORDER BY`. In
wet#155, two rebuilds of one map's lake layer returned the same 49 lakes in a different order, so a
rebuilt map file changed when the map did not. They have no simplification and only an envelope
(`&&`) bbox. `frs_watershed_at_measure()` returns fwapg's polygon at full resolution. Callers
therefore write their own SQL (about 20 repos hit `fwa_lakes_poly` directly). The goal: the same
`sf` back from the same database on every run, so wet#155 and others can call fresh instead.

Explored (main at 08b19b7, synced):
- All three fetchers build SQL as `SELECT cols FROM table <.frs_build_where()> [LIMIT]` and run it
  through `frs_db_query()` (`R/frs_db_query.R`, `sf::st_read`). `.frs_build_where()` is in
  `R/utils.R:688`; bbox is `geom && ST_MakeEnvelope(...)`.
- `.frs_resolve_aoi()` (`R/utils.R:842`) already turns sf/sfc into
  `ST_Intersects(geom, ST_GeomFromText('<wkt>', 3005))`, plus WSG codes and list(blk, measure) /
  list(table, id). `frs_extract()` documents and uses it as `aoi`.
- Local fwapg: unique indexes on `fwa_lakes_poly(waterbody_poly_id)`,
  `fwa_wetlands_poly(waterbody_poly_id)`, `fwa_stream_networks_sp(linear_feature_id)`; counts equal
  distinct counts, no NULLs. Lakes are MULTIPOLYGON XY.
- Probe (PostGIS 3.5.2, GEOS 3.9.0): `ST_Normalize('LINESTRING ZM(5 5 1 10, 0 0 2 0)')` →
  `LINESTRING Z (0 0 2, 5 5 1)` — reversed and M dropped. `ST_SimplifyPreserveTopology` on a ZM line
  also drops M.
- `frs_watershed_at_measure()` runs two delineations and `sf::st_difference()` in R for a subbasin.
  Its tests mock `frs_db_query` and count calls (`tests/testthat/test-frs_watershed_at_measure.R`).

## Decided at the gate (user, 2026-10-31)

1. **Extent = reuse `aoi`** through `.frs_resolve_aoi()`, not a new `extent` arg. sf/sfc →
   `ST_Intersects`; WKT callers wrap with `sf::st_as_sfc(wkt, crs = 3005)`; the WSG and blk+measure
   forms come along.
2. **`ST_Normalize` on polygons only** (lakes, wetlands, watershed). Streams get
   `ST_SimplifyPreserveTopology()` alone, keeping digitized direction. Docs say `simplify_m` drops M.
   **User asked to confirm the line path does not churn** — Phase 4 measures it.

Mechanism choices (mine, stated):
- `order_by` argument per fetcher, defaulting to the table's unique key, validated with
  `.frs_validate_identifier()`; `NULL` drops the clause. Needed because `table` is already
  configurable and a hard-coded key would break another table.
- `bbox` keeps `&&` semantics (no change for existing callers); its roxygen says so and points to `aoi`
  for exact intersection.
- `simplify_m` rewrites the geometry column in the select list to
  `<expr>(geom, simplify_m) AS geom`; `area_ha` is a stored column, so it is pre-simplify already.
  Geometry column found as the `cols` entry named `geom` (error if `simplify_m` set and none).
  `simplify_m` validated: single finite number > 0.
- Watershed: `simplify_m = NULL` keeps today's path byte-for-byte. With `simplify_m` and no upstream
  point, simplify in the one SQL. With an upstream point, one SQL computes
  `ST_Intersects(d.geom, u.geom)` and `ST_Normalize(ST_SimplifyPreserveTopology(ST_Difference(d.geom, u.geom), m))`,
  so the shared boundary is not simplified twice (which would leave slivers); R checks the flag and
  errors as now.

## Phase 1: Shared helpers + failing tests
- [x] `.frs_geom_select(cols, simplify_m, normalize)` in `R/utils.R`: returns the select list with the
      `geom` entry replaced; validates `simplify_m`
- [x] `.frs_order_by(order_by)`: validated `" ORDER BY <col>"` or `""`
- [x] `.frs_build_where()` gains `aoi`/`conn`, appending `.frs_resolve_aoi()`'s predicate when non-empty
- [x] Mocked unit tests (capture SQL via `local_mocked_bindings(frs_db_query = ...)`): ORDER BY present
      with default key and absent with `order_by = NULL`; ORDER BY precedes LIMIT; simplify expression
      present with Normalize for lakes/wetlands, without for streams; `aoi` sf → `ST_Intersects`;
      bad `simplify_m` / bad `order_by` error; `simplify_m` with no `geom` in `cols` errors

## Phase 2: Fetchers
- [x] `frs_lake_fetch()`, `frs_wetland_fetch()`: `aoi`, `simplify_m`, `order_by = "waterbody_poly_id"`;
      add `.frs_validate_identifier()` on `table`/`cols` as `frs_stream_fetch()` already does
- [x] `frs_stream_fetch()`: `aoi`, `simplify_m` (no Normalize), `order_by = "linear_feature_id"`
- [x] Roxygen for each: new params, bbox = envelope overlap, `simplify_m` drops M, GEOS-version limit;
      examples show `aoi` + `simplify_m`; `devtools::document()`

## Phase 3: Watershed
- [x] `frs_watershed_at_measure(simplify_m = NULL)`: two paths as decided above
- [x] Mocked tests: default path SQL unchanged and still two calls; simplify single-point SQL; simplify
      subbasin is one call carrying ST_Difference + intersects flag, and errors when the flag is FALSE

## Plan review fixes (review-286.md, folded in 2026-10-31)
- [x] `.frs_resolve_aoi()` sends WKT at `digits = 15` (was `getOption("digits")`, rounding Albers x to the metre)
- [x] `order_by` takes a vector; new fetch args moved after `limit`; `area_ha_min` through `.frs_sql_num()`
- [x] fetcher `aoi` docs: needs a CRS; WSG form is an envelope prefilter
- [x] simplified subbasin drops an empty difference, matching `sf::st_difference()`
- [x] line churn check moved ahead (see findings.md): streams 0 WKB differences across GEOS 3.9/3.10

## Phase 4: Live determinism tests + line churn check
- [x] Live tests (skip without DB): lakes, wetlands, streams and watershed each fetched twice with
      `simplify_m` → `identical()`; key column `!is.unsorted()` (fails without ORDER BY even when two
      calls happen to agree); `aoi` result is a subset of the bbox result for the same extent
- [x] Line churn check for the user: streams with `simplify_m` over a WSG, two separate connections,
      compare WKB bytes (`sf::st_as_binary`) row for row; if a second fwapg with a different GEOS is
      reachable, compare there too and record the vertex differences. Write result to `findings.md`
- [x] Confirm `identical()` on two `st_read` results is a fair test (no per-read attributes), per the
      code-check-r rule on reader results

## Phase 5: Wrap-up
- [ ] NEWS.md entry (written by `/gh-pr-merge` at release, as for 0.48.0; the `limit` change goes in the PR body for it); `lintr` on changed files; `pkgdown::check_pkgdown()`; full `devtools::test()`
- [ ] `/code-check branch`

## Owed at the end
- [ ] Comment on wet#155 that the fetchers are ready (our repo, after merge)

## Validation
- [ ] Tests pass
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: mocked tests pin the SQL shape; restore each defect (drop ORDER BY, drop Normalize,
revert aoi) and confirm a test goes red; live `identical()` + `is.unsorted()` tests against local
fwapg; the Phase 4 line-churn measurement answers the user's question directly.

