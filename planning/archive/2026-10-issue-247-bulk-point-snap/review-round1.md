# Code-check round 1: Phase 1 of #247 (snap helpers)

## Clean

No issues found in the diff.

### What was verified

- Ran `.frs_point_snap_sql()` output against local fwapg (PG 17.5) with a 3-point
  `VALUES` source that includes NULL and non-NULL hints, `num_features = 3` and
  `tolerance = 5000`. It parses and runs. It returns up to 3 ranked candidates per
  point with `watershed_group_code`. A point with no candidate inside tolerance is
  dropped, because the `CROSS JOIN LATERAL` removes it. The Phase 2 live tests
  already expect that.
- `EXPLAIN` (num_features = 1, tolerance = 100): Index Scan on
  `fwa_streamnetworks_geom_idx` with `Order By: geom <-> p.geom`, then Incremental
  Sort (presorted key `<->`) for the `linear_feature_id` tie-break, then Limit. The
  KNN ordered scan is intact and bounded by the `ST_DWithin` bbox index condition.
  `row_number()` sits outside the lateral as intended.
- The clamp's parentheses balance (`CEIL(GREATEST(ds, FLOOR(LEAST(us, ...))))`), and
  it matches the existing `frs_point_snap_knn()` / bcfishpass form.
- The tie-break ends on `linear_feature_id`, which is unique in the network table, so
  the checklist's "ORDER BY ends on a non-unique key" item does not apply.
- `tolerance` goes through `.frs_sql_num()`, so it is locale-safe and handles Inf.
  `stream_order_min`, `num_features` and the edge types are coerced with
  `as.integer`. `col_id` is double-quoted, and the caller validates it with the
  identifier regex.
- `.frs_db_write_temp()`: `tempfile()` hex suffix, lower-case, matching
  `[a-z0-9_]`, with no R RNG side effect. The mock captures the real
  `dbWriteTable(conn, name, value, ...)` formals, so the checklist's "`function(...)`
  mock" trap does not apply. `expect_false(identical(a, b))` compares two
  character values, so the type-crossing trap does not apply either.
- `tests/testthat/test-frs_point_snap.R`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 86 ]`.

### Forward note for Phase 2 (not a defect in this diff)

- `(p.hint IS NULL OR s.blue_line_key = p.hint)` needs `hint` to be a numeric
  column. If the caller writes a hint column that is all `NA` from R, its type is
  logical. `dbWriteTable` then creates a `boolean` column, and the query fails with
  `operator does not exist: integer = boolean` (confirmed in psql). A character hint
  column fails the same way. integer = double precision works. When Phase 2 builds
  `pts_sql`, cast the hint, for example
  `SELECT ..., hint::bigint AS hint` (or `as.numeric()` in R before the write). Add
  an all-NA hint case to the live tests.
