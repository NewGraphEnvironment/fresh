# Review round 3: Phase 1 diff (#247)

## Findings

- **[severity: fragile]** tests/testthat/test-frs_point_snap.R:27-36 ("snap SQL projects the network position and watershed group"): the `cols_out` loop can't fail. Each bare column name already appears elsewhere in the SQL: in the guards (`s.wscode_ltree`, `s.localcode_ltree`), the lateral's own `AS` aliases (`linear_feature_id`, `blue_line_key`, `downstream_route_measure`, `watershed_group_code`, `gnis_name`) or the final `ORDER BY` (`distance_to_stream`). Mutation check: I cut the outer SELECT down to `c.id AS "id_point", c.geom`, and all 8 `expect_match()` calls still pass. The test does not guard the issue's headline requirement, which is that `watershed_group_code` reaches the output.

- **[severity: fragile]** tests/testthat/test-frs_point_snap.R:16-25 and 38-48 (guards test; "hint and stream order filters land in the lateral"): these assertions match against the whole SQL string, so they can't see *where* a predicate sits. The second test's title says "land in the lateral", but nothing checks that. Placement matters. A hint, `stream_order_min` or edge-type/999 guard placed outside the lateral runs after `LIMIT n`. It then drops the point (or returns fewer than n candidates) instead of picking the nearest qualifying segment. Mutation check: I moved the hint and stream-order predicates from the lateral WHERE to `FROM c WHERE ...`, and both `expect_match()` calls still pass. The same blind spot covers the three guard assertions and the `ST_DWithin` assertion in the first test.

### Mechanism

One mechanism produces both findings. The assertions test text the SQL contains, while the property under test is what that text is attached to: an output column of the outer SELECT, or a predicate inside the lateral before `LIMIT`. A column or predicate name that occurs anywhere in the string satisfies the match. It reaches:

- the `cols_out` loop (outer projection)
- the edge-type/999/localcode guard assertions (lateral WHERE)
- the hint and `stream_order >=` assertions (lateral WHERE)
- the `ST_DWithin` assertion (lateral WHERE)

The candidate_rank test (lines 50-62) already does it right: it extracts the lateral with `regmatches(... "CROSS JOIN LATERAL.*\\) s\n" ...)` and asserts against that slice. The other tests can reuse that slice: predicates should match inside it, and outer columns should match as `c.<col>` after it.

## Verified clean (no action)

- The SQL runs against local fwapg (PG 17.5) with a real temp table from `.frs_db_write_temp()` (types: `id` integer, `x`/`y`/`hint` double, no `row_names` column). With `num_features` 1 and 3, the clamped integer measures, `watershed_group_code`, `candidate_rank` 1..3 and the dropping of points beyond tolerance all came out as expected.
- EXPLAIN: the tie-break `ORDER BY s.geom <-> p.geom, s.linear_feature_id` keeps the GiST KNN index scan (`Order By: geom <-> ...`) and adds an Incremental Sort on the presorted distance key. `ST_DWithin` becomes an `&&` index condition, and every filter sits inside the lateral, under `Limit`.
- The `s` alias inside the lateral and the `s` alias on the lateral do not collide. The insertion point in `utils.R` does not split a roxygen block. The `withr` the tests use is in Suggests. The `DBI::dbWriteTable` mock is not vacuous: an unmocked call on the string `"mock"` would error. All tests pass: 86 PASS, 0 FAIL.
