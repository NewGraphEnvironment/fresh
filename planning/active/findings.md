# Findings — Bulk point snap: one call snaps a dataset and returns watershed_group_code (#247)

## Issue context

**If we do it:** there is one way to put points on the FWA network, and it takes a whole dataset (data frame, `sf`, or table) and returns everything a downstream consumer needs. Validation, crossings, stations and eDNA all compose it the same way. **If we never do:** snapping stays duplicated. One copy is single-point in fresh and one is bulk in link, each missing fields and with different defaults, and `frs_feature_find(points = )` stays broken.

## Problem

Pinned at fresh@e2c917c (v0.38.0) and link@da44240.

Two snappers exist, and neither is the primitive callers need:

| | `fresh::frs_point_snap()` | `link::lnk_points_snap()` |
|---|---|---|
| input | one `x`, `y` (length-1 numerics) | a Postgres table of geometries |
| output | `sf`: `linear_feature_id`, `gnis_name`, `blue_line_key`, `downstream_route_measure`, `distance_to_stream`, `geom` | a new table: `linear_feature_id`, `blue_line_key`, `downstream_route_measure`, `wscode_ltree`, `localcode_ltree`, distance |
| default tolerance | 5000 m | 100 m |
| `watershed_group_code` | no | no |
| candidates | `num_features` | `num_features` |
| filters | `blue_line_key`, `stream_order_min`, `exclude_edge_types` | `blue_line_key_col`, `stream_order_min`, `exclude_edge_types` |

- **Per-point calls do not scale.** A 1,000-point dataset is 1,000 round trips. That is why link grew its own bulk copy, and its roxygen already says it "likely belongs in a future `pac` package".
- **Nothing returns `watershed_group_code`.** Every consumer that partitions by WSG has to re-join it from `fwa_stream_networks_sp`. `lnk_habitat_validate()` (link#283) requires it for observations from any non-bcfishobs source.
- **The tolerances differ by 50x.** bcfishobs's A/B matches are within 100 m; `frs_point_snap()`'s 5 km default pins a point that is well off the network to some stream anyway.
- **A live bug that the single-point signature caused.** `.frs_feature_find_points()` (`R/frs_feature_find.R:183`) calls `frs_point_snap(conn, points)` with the `sf`. That always fails with `x must be a single numeric value`, so `frs_feature_find(points = <sf>)` does not work at all. The only test (`test-frs_break.R:120`) checks that non-`sf` input is rejected.

Prior work: #2 introduced `frs_point_snap()`; #7, #16, #17 and #18 added candidates, the `blue_line_key` hint and `stream_order_min`; #207 added `frs_candidates_pick()` for scoring and deduplicating candidates. What is missing is the bulk shape and a complete output.

## Proposed solution

One bulk snap, with the candidate / pick split #207 already set up:

- **Input:** a data frame with coordinate columns plus `srid`, an `sf`, or a schema-qualified table. One call, one query, with the lateral KNN pattern `lnk_points_snap()` already uses.
- **Output:** the input's own id, plus `blue_line_key`, `downstream_route_measure`, `watershed_group_code`, `linear_feature_id`, `wscode_ltree`, `localcode_ltree`, `distance_to_stream`, and the candidate rank when `num_features > 1`. Returned as an `sf` / data frame, or written to `to =` for a table input.
- **Options, carried over:** `tolerance`, `num_features`, a per-row `blue_line_key` hint column, `stream_order_min`, `exclude_edge_types`. Scoring stays in `frs_candidates_pick()`.
- **Decide at design time:**
  - Keep the name `frs_point_snap()` and vectorize it, or add a sibling. Its current single-point callers are `frs_watershed_split()` and the broken `frs_feature_find()` path.
  - The default tolerance. 100 m matches bcfishobs A/B.

Then:
- `frs_feature_find(points = )` works through it.
- link's `lnk_points_snap()` becomes a thin wrapper or is removed. That is link-side work, tracked there.
- Callers compose snap → consumer. `lnk_habitat_validate()` takes network-located records and does not snap.

## Acceptance

- One call snaps N points in one query and returns the columns above, including `watershed_group_code`.
- `frs_feature_find(points = <sf>)` has a test that snaps real points, not only one that rejects non-`sf` input.
- Parity: on the PSCIS inputs link snaps today, the bulk snap gives the same `blue_line_key` and measure as `lnk_points_snap()`.

Relates to link#283.

Decisions (user, 2026-10-07):
- **Replace** `frs_point_snap()` in place — new signature takes a dataset. Breaking, pre-1.0.
- **Default tolerance 100 m.**
- **Output = input id + snap columns** (no `pts.*`; callers join back).

## Exploration notes that shape the plan

- **Snap semantics = link's lateral KNN**, not `fwa_indexpoint()`. `fwa_indexpoint()` is
  `DISTINCT ON (blue_line_key)`, excludes only edge 6010, no 999/NULL-localcode guards,
  fractional measure. The new snap: per-segment candidates, `.frs_snap_guards()`,
  `CEIL(GREATEST(FLOOR(LEAST(...))))` clamped measure, `ST_GeometryN(geom, 1)`,
  `ST_DWithin` + `ORDER BY <-> LIMIT n` lateral. link's PSCIS build relies on
  per-segment candidates feeding `frs_candidates_pick()` — no blk dedup.
- **Placeholder guard differs from link (verified):** fresh drops `wscode_ltree <@ '999'`
  (`R/utils.R:608`); link drops only `= '999'` (`lnk_points_snap.R:96`). 37,416 segments
  with `999.*` codes and non-NULL localcode are snappable in link, not in fresh. Keep
  fresh's guard; parity check excludes + reports rows where link picked a 999 stream;
  flag as a link bug.
- **Callers beyond fresh (verified):** `breaks/R/mod_aoi.R`, `breaks/R/mod_breaks.R`
  (positional x/y — would land in `to`), `breaks/data-raw/example_neexdzii.R`,
  `stewardship_upper_wedzin_kwa/scripts/edna_positions-resolve.R`,
  `diggs/data-raw/floodplain_co.R`, `wet/R/wet_station_snap.R`. New function errors
  loudly on numeric `points` or `x =`/`y =` with a pointer to NEWS.
- In-fresh callers: `frs_watershed_split()` (per-point loop in `tryCatch`, uses `gnis_name`),
  `.frs_feature_find_points()` (broken), 5 test files using `x = -126.5, y = 54.5` — that
  point is **170 m** off-stream, so they need explicit tolerance. No vignette/README use.
- `test-frs_watershed_split.R` stubs `frs_point_snap`; `whse_fish.pscis_assessment_svw`
  (MultiPoint, 3005) and link 0.50.0 are available locally.

## Design

```r
frs_point_snap(conn, points, to = NULL, col_id = NULL,
               col_x = "x", col_y = "y", col_geom = "geom", srid = 4326L,
               col_blk = NULL, tolerance = 100, num_features = 1L,
               stream_order_min = NULL, exclude_edge_types = 1425L)
```

- `points`: data.frame (`col_x`/`col_y` + `srid`), `sf` POINT (srid from
  `st_crs()$epsg`, error if NA), or schema-qualified table (`col_geom`; srid from the
  geometry, `srid` ignored, SRID 0 errors; `col_id` required).
- df/sf → plain `(id, x, y[, hint])` data.frame into a uniquely named TEMP table via a new
  `.frs_db_write_temp()` (utils.R, mockable), dropped on exit in `tryCatch`. Per-session,
  so mirai workers are fine; document the pgbouncer transaction-pooling caveat.
- Default id `id_point` (row index). `col_id` quoted with `dbQuoteIdentifier`; rejected if
  NA, duplicated (table: one `count(*) = count(DISTINCT)` query) or colliding with an
  output column name.
- Rows with NA x/y drop out like points beyond tolerance (no error). Hint predicate
  `(p.hint IS NULL OR s.blue_line_key = p.hint)` — a NULL hint means unconstrained
  (differs from link; documented).
- Internal `.frs_point_snap_sql()`: points CTE with `ST_Transform(ST_GeometryN(geom,1), 3005)`;
  lateral on `.frs_opt("tbl_network")` with `.frs_snap_guards()` fed `.frs_opt()` column
  names; tie-break `ORDER BY <->, linear_feature_id`; `candidate_rank` via
  `row_number() OVER (PARTITION BY id ORDER BY distance_to_stream, linear_feature_id)`
  **outside** the lateral (keeps the index KNN scan), only when `num_features > 1`.
  Output: `<id>, linear_feature_id, blue_line_key, downstream_route_measure,
  watershed_group_code, wscode_ltree, localcode_ltree, gnis_name, distance_to_stream,
  [candidate_rank], geom` (3005). Tolerance via `.frs_sql_num()`.
- `to = NULL` → `sf` (0 rows when nothing snaps, no error); `to` set → DROP/CREATE TABLE
  AS, returns `conn` invisibly.

## Plan-agent review (2026-10-07)

Two blockers (999 guard mismatch vs link; NA coords / NULL hints in bulk
`frs_watershed_split()`) and six gaps (id collisions + quoting, srid rules,
temp-table lifecycle + mockable writer, candidate tie-break + rank outside the
lateral, `.frs_opt()` columns in guards, `frs_feature_find()` label/append),
plus missed downstream callers and parity-test placement. All folded into the
Design section above and the phases in `task_plan.md`.
