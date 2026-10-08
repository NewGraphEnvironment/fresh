# Task: Bulk point snap: one call snaps a dataset and returns watershed_group_code (#247)

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

## Phase 1: Snap helpers (test-first)
- [x] Unit tests for `.frs_point_snap_sql()` shape: one lateral query, `ST_DWithin`, guards, NULL-tolerant hint, `stream_order_min`, `LIMIT`, `watershed_group_code`, tie-break, `candidate_rank` only when `num_features > 1`, rank outside the lateral, no `fwa_indexpoint`
- [x] Implement `.frs_db_write_temp()` and `.frs_point_snap_sql()` in `R/utils.R` / `R/frs_point_snap.R`; tests pass

## Phase 2: Swap `frs_point_snap()` and its callers (one green commit)
- [x] Rewrite `test-frs_point_snap.R` unit tests: input dispatch (df / sf / table), srid rules, scalar validation, `col_id` NA / duplicate / collision rejection, numeric `points` or `x =`/`y =` gives the migration error, one query per call, NA coords drop silently
- [x] Live tests, input shapes: N points in one call return ≤N rows with `watershed_group_code`; `sf` input; per-row hint column incl. NULL hints
- [x] Live tests, behaviour: far point dropped at 100 m and kept at 5000 m; all-far input gives a 0-row result; `num_features = 3` ranked candidates; table input with `to =` writes the table
- [x] Implement the new `frs_point_snap()`; remove `frs_point_snap_knn()` and the `fwa_indexpoint` path
- [x] `frs_watershed_split()`: one bulk call (`col_x = "lon"`, `col_y = "lat"`, its 5000 m default passed through), "failed to snap — skipping" message via anti-join on `id_point`; update `test-frs_watershed_split.R` stubs
- [x] Update x/y callers in `test-frs_network_upstream.R`, `-downstream`, `-prune`, `-point_locate` to `points = data.frame(x = -126.5, y = 54.5), tolerance = 500`; full suite green

## Phase 3: `frs_feature_find(points = )`
- [x] Live test: `frs_feature_find(points = <sf>)` snaps real points into `to` with `blue_line_key`, measure, `label`, `feature_id`
- [x] Rewrite `.frs_feature_find_points()` over `frs_point_snap()`; pass `label` and `append` through (`R/frs_feature_find.R:101` currently drops them); `feature_id` cast to text. BLK scoping to `table` applied to points too (the `table` param exists for it; revised from "table-path only" at implementation)

## Phase 4: Parity with `lnk_points_snap()`
- [x] `data-raw/` or `scripts/` parity script (not a testthat test — link imports fresh, so `link::` in tests is an undeclared dep): PSCIS in one WSG (intersect `fwa_watershed_groups_poly`) through both snappers at the same tolerance; compare `blue_line_key` (link: `snapped_blue_line_key`) + measure per `stream_crossing_id` at `num_features = 1` and sorted candidate sets at 5; exclude + count rows where link picked a `999.*` stream
- [x] Record results in `findings.md`

## Phase 5: Docs and wrap-up
- [ ] Roxygen for `frs_point_snap()` (`\dontrun{}` examples — DB required; required network columns for a custom `tbl_network`; output CRS 3005; pgbouncer caveat); refresh cross-refs in `frs_point_match.R:70`, `frs_candidates_pick.R`, `frs_feature_find.R`; `devtools::document()`
- [ ] `NEWS.md`: breaking signature + migration example, 100 m default, `watershed_group_code`, KNN-only (integer clamped measure, 1425 + `999.*` excluded), `frs_feature_find(points =)` fixed. CLAUDE.md: update the `frs_point_snap` line (~226) + technical note on snap semantics
- [ ] `lintr::lint_package()` clean; full `devtools::test()`
- [ ] Draft follow-up issues (confirm with user before filing): link — `lnk_points_snap()` → thin wrapper, 999 guard bug, `frs_point_snap_knn` roxygen ref; breaks / wet / diggs / stewardship_upper_wedzin_kwa — migrate to the new signature

Version bump (0.40.0) happens at merge via `/gh-pr-merge`, per convention.

## Validation
- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

