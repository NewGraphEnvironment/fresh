## Outcome

`frs_point_snap()` was replaced in place by a bulk snap. It takes a data frame, an `sf` object or a table, snaps every point in one lateral-KNN query, and returns the input id with `blue_line_key`, measure, `watershed_group_code`, wscode/localcode, `gnis_name`, distance and (for `num_features > 1`) `candidate_rank`, optionally written to `to =`. The default tolerance is now 100 m. The `fwa_indexpoint()` path and `frs_point_snap_knn()` were removed. `frs_watershed_split()` now snaps in one call, and `frs_feature_find(points = <sf>)`, which had always errored, snaps through the new function with the same id, label, append and stream-scoping behaviour as table input.

The code-check rounds mattered more than usual. Phases 2–5 each ended on an enumeration, after a reviewer found a defect inside the previous round's fix. Examples: a `to` equal to the input or network table was dropped before being read; one out-of-range lon/lat, in any geographic CRS, failed the batch; numeric ids were written as `2e+05`; a boolean `label_col` mapped as text silently fell through (keys `TRUE`/`t` are now normalised); the parity summary did not partition the input. The enumerations are `review-p{2,3,4,5}-enumeration.md`.

The snap semantics are written up in [`research/fwa_point_snap.md`](../../../research/fwa_point_snap.md).

## Measurement

Parity with `link::lnk_points_snap()` on all 19,905 PSCIS crossings at 150 m (fresh db1e959, link 0.50.0):
- 18,180 identical picks.
- 22 equidistant ties (same stream, measures 1 m apart).
- 11 where link picked a `999.*` placeholder segment that fresh excludes (8 left unsnapped, 3 snapped to the nearest real stream).
- 1,692 that neither snapped.
- 0 other differences.

At `num_features = 5`, 18,108 candidate sets are identical and 86 differ only at a tied fifth candidate. There are 0 measure mismatches. Runtime is about 1 s for each snapper. The placeholder count behind link#313 is 37,416 `999.*` segments with a non-NULL local code. No segment carries the bare code `999`.

Test suite at the end: FAIL 0 / WARN 3 / SKIP 2 / PASS 1,499. The warnings and skips were there before this branch. `R CMD check` (tests run separately): 0 errors, 0 warnings, 0 notes.

## Evidence

`data-raw/logs/point_snap_parity_247/*` (from `data-raw/point_snap_parity_check.R`)

Follow-ups filed: NewGraphEnvironment/link#313, link#314, breaks#13, diggs#25, stewardship_upper_wedzin_kwa#15, wet#55.

Closed by: PR for branch `247-bulk-point-snap-one-call-snaps-a-dataset`
