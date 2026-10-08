# Code review: round 2 (#247 Phase 1)

Scope: `R/frs_point_snap.R` (`.frs_point_snap_sql()`), `R/utils.R` (`.frs_db_write_temp()`), `tests/testthat/test-frs_point_snap.R`, `planning/active/task_plan.md`.

## Clean

No issues found.

## What was checked

- `test-frs_point_snap.R` passes: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 86 ]`. The `DBI::dbWriteTable` mock takes effect through `::`. `withr` is in Suggests.
- End-to-end run against local fwapg (RPostgres 1.4.10):
  - `.frs_db_write_temp()` created the temp table `frs_tmp_<hex>`, and the unqualified name resolved through `pg_temp`.
  - A numeric hint column arrives as `double precision`, and `integer = double` compares correctly.
  - With `num_features = 2` the query returned two ranked candidates. A point with NA coordinates dropped silently, and a point whose hint does not match returned no rows.
  - The table dropped cleanly afterwards.
- `sprintf` safety: `pts_sql` and `col_id` are passed as arguments, never as the format string, so a `%` in them is harmless. `.frs_sql_num()` ignores `OutDec`.
- In the lateral, `ORDER BY s.geom <-> p.geom` is qualified, so it uses the table's `geom`, not the `ST_ClosestPoint` output alias. The tie-break is the same in the lateral and in the outer `row_number()` / `ORDER BY`.
- The test regex `CROSS JOIN LATERAL.*\) s\n` matches exactly one span, because TRE's `.` matches newlines.

## Not flagged (out of scope or already known)

- An all-NA hint becomes logical/boolean, and an NA `stream_order_min` / `num_features` renders as `NA`. Both are covered by Phase 2 coercion and scalar validation.
- `length_metre`, `gnis_name`, `stream_order`, `edge_type` and `watershed_group_code` are hardcoded rather than read from `.frs_opt()`. The existing snap code does the same, so this is not a regression.
