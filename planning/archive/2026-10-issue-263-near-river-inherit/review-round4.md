## Checklist read

- Diff: `codecheck.77Mw2K/fix3.patch` (commit 0ebe396, branch 263-inherit-near-river-from-the-thresholds-c)
- `R/frs_habitat_classify.R` in full
- `R/frs_near_river.R` in full (the `frs_near_river()` body, `.frs_near_river_check()`, `.frs_near_river_check_shape()`, `.frs_near_river_table()`, and the walk SQL to see which relations it reads)
- `tests/testthat/test-frs_habitat_classify.R` in full
- `R/utils.R` `.frs_index_working()` (index names), `R/frs_habitat.R` callers of classify (serial and parallel), link's `near_river` users (`lnk_discharge.R`, `lnk_habitat_validate.R`) for any dependence on classify's output order or on when the near-river table is written

## Clean

What was checked, and how:

1. **Does the walk depend on anything created between its old and new position?** No. The walk reads only `table` (plus `whse_basemapping` polygon tables) and writes `<to>_near_river`, `pg_temp.frs_near_river_walk`, a GiST index on `table` and an `ANALYZE` of `table`. Nothing between the old and new positions creates or changes any of those: `CREATE TABLE IF NOT EXISTS <to>`, the `DELETE` from `<to>` (which `overwrite` governs), and the `<table>_acc_*` tables built from `table` and `breaks_tbl`. `.frs_index_working(conn, table)` still runs before the walk, as it did before. `gate`, `barrier_overrides` and `breaks_tbl` never reach the walk. Index names do not collide: `.frs_index_working(conn, to)` writes `<to>_blk_idx` and similar, and the walk writes `<to>_near_river_seg_idx` / `_wsg_idx`.
2. **Results.** The classify INSERTs read `near_tbl` after the walk in both orders, and nothing between them modifies `table`. The only side effect that moves is the walk's `ANALYZE table`, which now comes before the access `CREATE TABLE AS` statements. That changes planner statistics only, not rows.
3. **`near_tbl` NULL.** The block is skipped in both positions, so nothing changes.
4. **An empty table with no groups.** The walk's DELETE and its walks match nothing, as before. The existing "empty table" test passes.
5. **Verbose output.** The "Near river …" lines now print before "Ungated…" / "Access N%…", and still before the per-species lines. No test in fresh or link reads that order (grepped both repos for "Near river", "Ungated" and `expect_output`).
6. **`<to>_near_river` on failure.** A failure inside the walk leaves it as it did before: the group's rows deleted, then the pairs written up to the failing one. It is no worse than before. A walk failure also no longer leaves orphan `<table>_acc_*` tables. One new window exists and is not a defect: if classify fails after the walk, before its own DELETE (for example, `CREATE TABLE <to>` refused), the near-river table now holds the new pairs beside the old habitat rows. Both are derived and rebuilt by the next run, and no data is lost.
7. **The type check through DBI.** I probed RPostgres on the local fwapg with `LIMIT 0` frames, with and without rows. `integer` gives integer, `bigint` gives integer64, and `numeric`, `numeric(6,2)`, `real`, `double precision` and a domain over double all give numeric. `smallint` gives integer. Every one is `is.numeric()` TRUE, and only `text` gives FALSE. The check would misfire only on a connection opened with `bigint = "character"`, and nothing in fresh or link opens one (grepped).
8. **Tests.** I ran them in a copy of the repo with `NOT_CRAN=true`. `test-frs_habitat_classify.R` had 19 tests, 0 failures, 0 errors and 0 skips; `test-frs_near_river.R` had 54 passes and 0 failures. Then I restored the old order with `git apply -R` on `R/frs_habitat_classify.R` only. The new assertion at line 503 (`nr_hab` count still 1 after the mocked walk failure) went red, so the guard fires against the old order.
