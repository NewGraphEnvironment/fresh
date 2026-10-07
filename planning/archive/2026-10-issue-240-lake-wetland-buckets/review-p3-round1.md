# Review — fresh#240 phase 3, round 1

Diff reviewed: staged `R/frs_habitat.R` (`.frs_trace_downstream()` generalised,
new `.frs_bucket_connected()`, second species loop in `.frs_run_connectivity()`),
`tests/testthat/test-frs_bucket_connected.R`, the golden fixture, and the
additions to `test-frs_habitat.R`. Probes ran on a copy of the repo in the
session scratchpad. The original tree was not touched.

## Findings

- **[severity: fragile]** `tests/testthat/test-frs_bucket_connected.R:9,92-118`.
  The four "within / beyond distance" tests cannot detect a broken network
  distance cap on the bucket path. `.bkt_fixture()` puts every segment on one
  straight line, so straight-line distance equals network distance. Both bucket
  traces run with `prefilter = TRUE`, and the `ST_DWithin` prefilter applies
  the same cutoff that `dist_to_origin < distance_max` applies. Mutation test on
  a copy:
  - Disabling the cap (`FROM downstream WHERE TRUE OR dist_to_origin < %s` in
    `.frs_trace_downstream()`) leaves the file at `[ FAIL 0 | PASS 18 ]`.
  - Disabling the cap and also setting `prefilter = FALSE` on both bucket calls
    gives `[ FAIL 2 | PASS 16 ]`.

  So the "beyond distance" verdicts come from the prefilter, not from the
  network measure the docs promise. A regression in the cumulative-length
  window, such as a changed `ORDER BY` or `PARTITION BY` or a wrong `rn` cap,
  would ship green whenever straight-line distance is under the cap.

  To reach the failure, add a fixture where the network is longer than the
  straight line. For example, spawning reached through a tributary that doubles
  back (wscode `100.300000`, geometry folded so its far end sits near the lake),
  with `distance_max` between the straight-line distance and the network
  distance. Alternatively, run the beyond-distance cases once with
  `prefilter = FALSE`.

## Checked and found sound (not findings)

- **Golden test pins the pre-change SQL.** I loaded `HEAD:R/frs_habitat.R`'s
  `.frs_trace_downstream()` into an env over the fresh namespace and captured
  its SQL with the same arguments (`w.streams`, `SELECT 1 AS origin_id`,
  `pg_temp.t`, 3000, 0.05):
  - old SQL is identical to the fixture (TRUE);
  - new default SQL is identical to the old SQL (TRUE).

  The SK caller passes `distance_max` and `bridge_gradient` positionally, and
  the new formals are appended after them, so that call is unchanged.
- **Prefilter cannot drop a segment that is within network distance.** Take the
  first segment X the prefilter excludes on an origin's path. Its whole geometry
  is more than `dm` from the origin geometry. The included segments above it
  therefore already sum to more than `dm` (path length is at least the
  straight-line distance from the origin's bottom to X's top). So X, and every
  later segment, would be capped anyway, and removing X cannot pull a later
  segment back under the cap. This assumes the mainstem path is contiguous in
  `table`, which is the same assumption the existing trace already makes.
- **origin_id uniqueness.**
  - Case 2 uses the id_segment of the lowest bucket line per
    `(waterbody_key, blue_line_key)`. That value is unique within `table`,
    because one segment has one key.
  - Case 3 uses the DBSCAN `cluster_id`, which is unique per cluster.

  No two origins share a distance window. Ties in case 3's `DISTINCT ON` are
  only possible between side-channel blue lines with identical
  wscode/localcode/drm. Those return the same downstream set, because
  `FWA_Downstream` to another blue line depends on the codes only.
- **WSG / species isolation.** Every habitat read and the `UPDATE` match
  `(id_segment, watershed_group_code)` and `species_code`. The OTHR test fails
  under either mutation: dropping the WSG match from case 1, or dropping it from
  the `UPDATE`.
- **NULLs.**
  - Bucket lines always have a `waterbody_key`, because the predicate is
    `s.waterbody_key IN (...)`.
  - Case 3 filters `IS NOT NULL`, and case 1's `IN` excludes NULL, so
    `keys_tbl` never holds a NULL.
  - A NULL `wscode_ltree` makes `FWA_Downstream` NULL, so that row simply does
    not join.
  - `ORDER BY ... ASC` puts NULL codes last in both `DISTINCT ON` picks.
- **Identifiers.** `table` and `habitat` go through `.frs_validate_identifier`.
  `column` is restricted by `stopifnot`, species is quoted, and `id_col` is
  validated. Temp names carry species and column, are dropped before creation,
  and do not collide with the SK path's `frs_qual_spawn_*` / `frs_trace_lfid_*`.
- The new test file passes on a copy (`[ FAIL 0 | PASS 18 ]`). Apart from the
  distance cap above, the tests can fail: removing case 1 breaks "own line
  connects", and a sibling connection would break the sibling test.

/Users/airvine/Projects/repo/fresh/planning/active/review-p3-round1.md
