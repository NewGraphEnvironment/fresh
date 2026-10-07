# Code check, round 1: R CMD check fixes (diff_checkfix.patch)

Verdict: **the diff is clean.** Nothing in it causes a failure or data loss. There is one
doc-accuracy finding that the diff newly publishes (F1). There are two pre-existing
problems outside the diff, found while answering the "does anything else still pass
removed args" question (F2, F3).

## Findings

### F1 (minor, docs): the `gate` text inherited into `frs_habitat()` is inverted
- Source: `R/frs_habitat_classify.R:42-45`. Now also in `man/frs_habitat.Rd`, through the
  new `@inheritParams frs_habitat_classify`.
- It says: "segments **downstream** of blocking breaks are marked inaccessible".
- The SQL does the opposite (`R/frs_habitat_classify.R:241-256`). A segment is
  inaccessible when a blocking break sits **downstream** of it: same BLK with
  `b.downstream_route_measure <= s.downstream_route_measure`, or another BLK where
  `fwa_upstream(b, s)` holds. So the segments marked inaccessible are the ones
  **upstream** of the break, which is also how the vignette puts it.
- Before this diff the wrong sentence appeared only on `frs_habitat_classify`. Now it is
  also on the orchestrator page.
- Fix at the source: "segments upstream of blocking breaks are marked inaccessible".
  Then re-document.

### F2 (outside the diff, present since #95): three callers still pass point-mode args to `frs_break_find()`
Each errors with "unused arguments (points_table, where, aoi, append)" if run:
- `vignettes/habitat-pipeline.Rmd:137-144`: a non-evaluated `r` block that users will
  copy. The prose at lines 126-130 also says "`frs_break_find()` with the table mode
  pulls barrier falls".
- `data-raw/vignette_habitat_pipeline.R:118-125`: comments at 108-117 say the same.
- `data-raw/pipeline_wsg.R:89-92`.

The replacement is the same call this diff puts into `frs_habitat_access()`:
`frs_feature_find(conn, tbl, points_table = "bcfishpass.falls_vw", where = "barrier_ind = TRUE", to = <breaks>, overwrite = FALSE, append = TRUE)`.
Drop `aoi`, because `frs_feature_find` scopes by the BLKs in `table`.

Not live code:
- No caller in `R/`, `tests/`, `README.md` or `scripts/` passes the removed args.
- `inst/issues/design-habitat-models.md` uses an aspirational `frs_break(conn, aoi = ...)`
  API. It is a design note, not runnable docs.
- No caller in `../link`.

### F3 (outside the diff, sibling of fix 7): a unit test still treats the aliased subquery as valid
- `tests/testthat/test-frs_col_join.R:86-90` passes `from = "(SELECT ...) sub"` and
  asserts success. The test is mocked, so it passes.
- Real Postgres rejects the SQL it builds. Checked read-only on local fwapg:
  `SELECT 1 FROM (SELECT 1 AS a) sub _src` gives `ERROR: syntax error at or near "_src"`.
- The example is fixed. This test still documents the broken form as supported.
- Low severity: nothing fails, but it is the second caller of the same defect.

## Verified (no issue)

**Column compatibility of `frs_feature_find(append = TRUE)` into the `frs_break_find()` table.**
- Single-threshold CTAS (`R/frs_break.R:166-235`) produces these columns:
  - `blue_line_key integer` (FWA column is `integer`, checked against `information_schema`)
  - `downstream_route_measure numeric` (from `ROUND(...::numeric, 2)`)
  - `label text` (a `'gradient'` literal resolves to `text`, checked with `pg_typeof`)
  - `source text`
- On the append path, `.frs_feature_find_table` runs `CREATE TABLE IF NOT EXISTS`, which
  is a no-op here.
- It then runs `INSERT INTO to (blue_line_key, downstream_route_measure, label, source)`
  with an explicit column list. double to numeric is an assignment cast. `col_id` is not
  passed, so no `feature_id` column is needed.
- `overwrite = FALSE, append = TRUE` means `overwrite && !append` is FALSE, so there is
  no DROP.
- This is byte-for-byte the pre-#95 `.frs_break_find_table` append path
  (`git show 667d0368^:R/frs_break.R`). It also matches what `frs_network_segment()` does
  (`R/frs_network_segment.R:174-183`).

**No remaining unused-argument calls in `R/`.**
- I ran `codetools::checkUsage` over every function in the loaded namespace and got
  zero "unused argument" or "possible error" lines.
- Positive control: the same check on HEAD's `frs_break` reports
  `unused arguments (points_table = points_table, points = points, where = points_where, aoi = aoi)`.
- This is the same predicate R CMD check uses, so it is the guard for this class of
  defect.

**`frs_break_apply` `measure_precision` doc matches the SQL.**
- `SELECT DISTINCT blue_line_key, round(downstream_route_measure::numeric, mp)`
  (`R/frs_break.R:596-604`) collapses breaks that round to the same position.
- The default `0L` matches the doc.

**`@inheritParams` on `frs_habitat`.**
- Only `gate`, `label_block` (from classify) and `measure_precision` (from
  `network_segment`) were added to the Rd.
- `frs_habitat` forwards all three, with the same defaults: `R/frs_habitat.R` lines 469,
  489, 642, 653, 711, 716 and 733.
- The `measure_precision` sentence "Also rounds the breaks table and deduplicates" is
  true of the `frs_network_segment` path it is forwarded to.
- The `frs_break` page inherits only args that `frs_break_find` still has.

**Non-ASCII.** `tools:::.check_package_ASCII_code(".", FALSE)` returns `character(0)`.
The `stop()` change keeps the prefix that `test-frs_wsg_drainage.R:171` matches. No peer
repo matches the message text.

**Test dependencies.** `tools:::.check_packages_used_in_tests()` is empty. `tibble::`
(12 uses) and `bit64::` are declared in Suggests.

**`.Rbuildignore`.** `^\.lintr$` and `^docker$` are anchored regexes with no comment
lines. `docker/` holds nothing the package needs. `^docker/postgres-data$` is now
redundant but harmless.

**The new tests catch the defect class.** I checked this by reading. Tests were not run,
per instructions.
- `frs_break` test: HEAD's `frs_break` forwards `points_table`, `points`, `where` and
  `aoi` by name. None are in `formals(frs_break_find)`, so the assertion goes red. The
  stubs are reached: an unreached stub would run the real function against `"mock"` and
  error, not pass vacuously. The sibling "find, validate, apply" test pins the call.
- `frs_habitat_access` test: HEAD calls `frs_break_find` three times, so the pinned
  sequence `c("frs_break_find", "frs_feature_find", "frs_feature_find")` fails, and so
  does the formals check.
- `get(fn, asNamespace("fresh"))` reads the real formals under both `load_all` and an
  installed check.
- Coverage limit, not a defect: the tests pin argument **names**, not values. A mutation
  to `overwrite = TRUE` / `append = FALSE` in `frs_habitat_access` would stay green.
  With `overwrite = TRUE`, the gradient breaks would be silently dropped before each
  source is appended.

**`src$label` partial match.** With only `label_col` set, `src$label` partial-matches to
`label_col`'s value. This is harmless, because `.frs_label_expr` checks `label_col`
first. It is pre-existing and shared with `frs_network_segment`.
