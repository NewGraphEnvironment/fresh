# Code-check round 2 — #279 per-run test table names

Branch `279-integration-tests-name-working-tables-as` at 2114e95, base origin/main 98e7cf0.

## Checklist read

- code-check-infra.md: in full.
- code-check.md: prose of every H3 under `## Mechanisms` (A guard that fails toward pass; A fixture that cannot reach the failure mode; A proxy is not the property; Verification that reads its own output; A guard's scope, escape hatches, and remedies; A fix lands in one of two callers that share a harness; Restore the bug and prove the guard fires; A shared working tree; A wrapper's exit is not the work; Zero-length, empty, and unset; The probe is broken before the world is; Written data outlives the fix; Serialization loses meaning silently; One fact derived twice), plus "Do not edit files a long test run is reading". Remaining headings not read.
- code-check-r.md, read by heading: Tests that silently do not run; A `skip_if_not()` skips only its own `test_that()` block; Under `R CMD check`, tests run from a temp dir against the INSTALLED package; A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check` if `pkg` is undeclared; `on.exit()` at a script's top level never fires; `paste()` with a zero-length argument returns length ONE; `$` on a list partial-matches; An `information_schema` lookup by the literal table name misses what Postgres resolves; `tempfile()` lives in the session tempdir; `sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words; `deparse(body(f))` excludes formal defaults; `deparse()` re-encodes non-ASCII; Postgres row order is never fixed unless the query fixes it; `lintr` also resolves against the installed package. About 120 other headings not read (no tool or shape in this diff).
- code-check-shell.md, read by heading: none applied (the diff has no shell); 0 read, all skipped.
- code-check-spatial.md, read by heading: none applied (no sf/terra/GDAL in the diff); 0 read, all skipped.

## What was checked

- The round-1 fix (`defs_from` / `.frs_test_guard_defs()`): the lintr restructure keeps the original short-circuit order (`is_assign` guards `e[[2]]`, `fname %in% names(default_to)` guards `default_to[[fname]]`); requoted snippets are byte-identical in content.
- In a detached worktree (removed afterwards), with `PG*` and `FRESH_PG*` pointed at an unreachable port: `devtools::test(filter = "test_table_names")` gave FAIL 0 / PASS 30.
- Mutation probe: a scratch test file holding a `local_fwapg_indexpoint()` block, a top-level helper calling `local_fwapg()`, and a block passing `local_fwapg()` inline, each writing a fixed `working.` name. With `defs_from` all three were flagged. Without it the `local_fwapg_indexpoint()` block was not, so the fix closes the round-1 gap and the guard fires on it.
- Enumerated every `test_that()` block the guard leaves unchecked (`is_test && !is_live`) that mentions DBI calls or `working`: all 22 use mock connections (`"mock"`, mockery stubs, a fake `DBIConnection`) or pure SQL builders. None is a live block the scanner misses.
- Connector inventory: every connection in the tests comes from `frs_db_conn()`, `local_fwapg()`, `local_fwapg_indexpoint()`, `bcfp_conn()` or `frs_fwapg_conn()`, and all of them are in the live set after the fix.
- Name budgets: every literal `frs_test_tbl()` name is 36 characters or fewer with the run prefix; the longest label is `brktest_110b` (20 with the prefix, at the cap). `.rules_test_run`'s `paste0(frs_test_tbl("rt_habitat_"), label)` reaches 28.
- Migrated files: no added `sprintf()` template carries a stray `%`. Every remaining catalog lookup in a live block goes through `frs_test_tbl_parts()`; `test-frs_feature_index.R`'s `pg_indexes` lookup is on `pg_temp` and unchanged by the branch. The `pg_temp.decoy_282` drop is now schema-qualified. `frs_migration_trial` names are distinct per test (`_a`..`_d`) and rolled back.
- Sweep (`frs_test_sweep()`): quoted identifiers; relkinds r/p/v/m; it matches only this run's `t<6>_` id; connection failures are caught.

## Clean
No issues found.
