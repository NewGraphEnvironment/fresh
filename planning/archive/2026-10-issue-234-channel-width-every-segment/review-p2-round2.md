## Verdict: Clean (shipped code). One low-severity test-assertion weakness.

Scope: diff_phase2.patch (`frs_channel_width()` `value` + `verbose`, tests, `frs_col_join()` doc link). Checked against the R section and the general mechanisms of the checklist. No live tests were run; one read-only fwapg query was made.

### Finding (low): the live count assertion is unanchored, so a wrong count can pass

`tests/testthat/test-frs_channel_width.R:399-401`

```r
expect_message(
  frs_channel_width(conn, tbl, value = 0.5),
  sprintf("%d modelled .*, 1 assigned, 0 still NULL", n_null - 1L))
```

Nothing anchors the pattern on the left, so the expected count matches any reported count that ends in the same digits. With `n_null - 1L == 5`, the message `channel_width: 15 modelled (...)` passes. This is the only assertion that checks the reported counts against a real database: the unit tests feed the counts in through mocks (`n_rows`, `n_null`), and the `dbGetQuery` mock returns `n_null` for any SQL that is not the `pg_attribute` query. So the unit tests also pass when the count query's predicate or table is wrong. The DB-side checks that follow (`nrow(filled)`, the `ASSIGNED` row, 0 NULLs left) check what was written, not the message. A bug in the counting would have to give a number with the same trailing digits to slip through, so the risk is small. The fix is one token: anchor the pattern on the column name, as the first unit message test already does:
`sprintf("^channel_width: %d modelled .*, 1 assigned, 0 still NULL$", n_null - 1L)`.

(Not a code defect. Reported because the brief asked whether a test could pass while the real path is broken.)

### Checked, no issue

- **@param overwrite** ("rewrites every row: the regression where its inputs allow, NULL elsewhere"). True for `to`, and for `col_source` when it is set (the CASE with no ELSE gives NULL). With `value`, the NULLs are then filled, which the `value` doc covers ("rows still NULL after the regression"). The overwrite + value + col_source = NULL unit test pins the second statement exactly.
- **@param value**:
  - The claim "typically segments with no upstream area, such as FWA placeholder and unmapped lines" was measured read-only on BULK + MORR (lut → upstream_area join, precip on wscode/localcode). Placeholder: 2,784 segments, 0 with area, 0 with precip. Unmapped: 2,296 segments, 0 and 0. Normal: 52,291 segments, 52,255 with area. So those segments do reach the `value` pass, and so do 36 normal segments with no area, which is consistent with "typically".
  - "Default NULL leaves them NULL" is true.
  - "Labelled ASSIGNED" applies only when `col_source` is non-NULL, and the `col_source` doc says NULL writes no label.
- **@param verbose / the message**:
  - overwrite = FALSE: modelled = rows the guarded UPDATE touched.
  - overwrite = TRUE: the UPDATE has no WHERE, so `n_written` = all rows. A guard-true row cannot evaluate to NULL, so written − NULL-after = modelled.
  - `n_null` is counted before the value pass, and the value UPDATE uses the same `to IS NULL` predicate, so "still NULL" is 0 whenever `value` is set.
  - Every number goes through `as.integer()` before `%d`.
- **value + overwrite = FALSE + a `to` column with existing non-NULL values.** Only `to IS NULL` rows are touched, so measured and mapped widths and their labels are left alone. The live test's byte-identical `before`/`after` check covers this.
- **value with an existing `to` typed numeric(p,s)**, which the type check accepts. The value is coerced to the column's scale. That is plausible only for contrived scales; not flagged.
- **value validation.** NULL, non-numeric, length ≠ 1, NA/NaN/Inf and ≤ 0 are all refused before any DB call, through a short-circuiting `||` chain. A yaml-style `list(0.5)` is refused loudly, not coerced. `.frs_sql_num()` renders integer input correctly: `sprintf("%.10g", 2L)` gives "2".
- **Mock fidelity otherwise.**
  - `.frs_db_execute` returns 0 for ALTER and the per-UPDATE count, matching what `DBI::dbExecute` returns.
  - The `dbGetQuery` mock is installed with `.package = "DBI"`, which intercepts the `DBI::` call.
  - `.run_cw()` defaults to `verbose = FALSE`, so the earlier tests run no count query and are unaffected.
  - The `verbose = FALSE` test asserts that no `count(` query runs.
- **Callers.** No other R/ function calls `frs_channel_width()`. The new arguments are appended after `overwrite`, so positional calls are unaffected.
- **frs_col_join doc link.** Accurate. Both functions carry `@family habitat`, and the Rd seealso lists `frs_channel_width()`.
- **Checklist items that could apply:**
  - `expect_message` first-condition: the NOTICEs print rather than arrive as conditions (round 1).
  - testthat 3e return value: there is no `x <- expect_message()`.
  - `$` partial match: exact column `n_null`.
  - Zero-length: count(*) always returns one row.
  - Defaults that decide: `value = NULL` and `verbose = TRUE` are a safe default and a preference.
  - `sprintf("%g")` and Inf: Inf is refused before rendering.
  - No identifier or literal injection: `ASSIGNED` is a fixed literal and the identifiers are validated.

### Considered, not flagged

- The description (R/frs_channel_width.R:8-9, a line outside the diff) still says placeholder and unmapped segments "stay `NULL`". That is true under the default `value = NULL` and false when `value` is set. Rewording it to "stay `NULL` unless `value` is given" would remove the tension. Low stakes, so I am not calling it a defect.
