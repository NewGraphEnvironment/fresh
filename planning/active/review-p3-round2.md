# Review — #247 Phase 3, round 2

Scope: `R/frs_feature_find.R`, `tests/testthat/test-frs_break.R` (diff
`p3_diff.patch`), with `R/frs_point_snap.R`, `.frs_label_expr()`,
`.frs_db_write_temp()` / `.frs_db_execute()`.

Round 1 fixes hold: `feature_id` is `text` in both create-mode SELECTs and in
the append DDL. A points-path append into a table-path table works (live test).
`blue_line_key`, `downstream_route_measure` and `source` have compatible types
across both paths' CREATE TABLE AS, the append DDL and the other path's INSERT.

## Findings

- **[bug]** R/frs_feature_find.R:202-207 + R/frs_break.R:385-393 — the
  `label` column has the same mismatch, one axis over. The points path writes
  `label_src` with its native R type, and `.frs_label_expr()` builds
  `CASE WHEN label_src = '<name>' THEN '<label>' ELSE label_src END`, with no
  cast. For an integer, double or logical `label_col` combined with
  `label_map`, Postgres resolves the CASE to the column type and rejects the
  text label. Verified live on fwapg (PG 17.5):
  `points$code <- c(1L, 2L, 1L)`, `label_map = c("1" = "blocked")` fails with
  `invalid input syntax for type integer: "blocked"`. A logical column with
  `c("TRUE" = "blocked")` fails with `... type boolean: "blocked"`. Numeric
  status codes with a `label_map` are an ordinary input, so this fails in
  normal use. The table path has the same defect for non-text source columns
  (pre-existing).
  Fix: in `.frs_label_expr()`, cast once on the SQL side, as in
  `CASE WHEN label_col::text = ... ELSE label_col::text END`. This fixes both
  paths. Do not coerce with `as.character()` in R, because it brings back the
  round-1 `"2e+05"` defect for doubles. A logical column then compares as
  `'true'`/`'false'`, not `'TRUE'`, so document that or map in R for logicals.

- **[fragile]** R/frs_feature_find.R:96-98 vs 178-187 — in the default mode
  (`overwrite = TRUE, append = FALSE`), `to` is dropped before anything is
  checked or run. That includes the non-sf check, the new `label_col` check,
  the snap (no EPSG, duplicate `col_id`, `col_id` colliding with a snap output
  column), and the CREATE itself (the label_map bug above). A failing call
  therefore destroys the previous `to` and leaves nothing in its place. The
  live run above confirmed this. The ordering is pre-existing, but this phase
  adds several new failure points after the DROP. Separately,
  `to == table` drops the working streams table that the scoping subquery
  reads. `frs_point_snap()` guards this case for its own `to`; this function
  does not. Fix: move the DROP into `.frs_feature_find_write()`, just before
  the CREATE. Optionally reject `to` equal to `table` or `points_table`.

- **[fragile]** R/frs_feature_find.R:200-201, 221 (and table path line 148) —
  `feature_id::text` on a `double precision` id switches to exponent notation
  at 1e15 and above. Postgres gives
  `1234567890123456::float8::text = '1.234567890123456e+15'` (verified). This
  is the round-1 defect class moved from R to SQL. It affects only double ids
  of 16 or more digits. Integer, bigint/integer64, character and factor ids
  are exact. Low likelihood; noted so the fix's comment does not overclaim.

- **[fragile]** R/frs_feature_find.R:197 —
  `as.integer(snapped$blue_line_key)` coerces in R. On a custom network whose
  `blk_col` is bigint with values above 2^31 (frs_point_snap already casts its
  hint to bigint), this gives NA with a warning. The NA rows are then dropped
  silently by the `IN (...)` scoping, and the drop message does not count them.
  This is harmless on FWA, whose `blue_line_key` fits in int4. The append DDL
  also fixes `blue_line_key integer`, so the limit is shared. Writing the
  column with its native type would remove the silent loss.

Tests: the mocks match the real signatures (`frs_point_snap(conn, points, ...)`
receives `col_id`; `.frs_db_write_temp(conn, df)`). `expect_message` sees only
the one message. The live test is gated with `skip_if_not(.frs_db_available())`
and asserts a non-vacuous `keep`. No defects found in the test changes.
