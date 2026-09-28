# Code-check: Phases 3-4, round 1 (#229)

## Clean

Checked:
- Skip order in `tests/testthat/test-frs_network_features-live.R`: `skip_on_cran()` and `skip_on_ci()` run first, so CI never tries to connect. `bcfp_conn` is defined (lines 15-22) before `skip_if_no_conn(bcfp_conn)` (line 24). A top-level `skip()` in a testthat 3e file skips the rest of the file, which gives the "SKIP 1" you saw.
- If `PG_PASS_SHARE` is unset, `bcfp_conn()` passes `password = ""`. libpq ignores the empty value and falls back to `.pgpass`. If that fails, the file skips. This matches the old unset-credential behaviour.
- Stale `PG_PASS_SHARE` gate references: none left. Every remaining hit is legitimate: the credential used inside `bcfp_conn()`, `R/frs_db_conn.R` and its tests, the tunnel `Sys.setenv` example in CLAUDE.md, and planning history.
- CLAUDE.md "Testing on alternate hosts": correct. "Same helper file" refers to `tests/testthat/helper-db.R`, which does define `skip_if_no_conn()`.
- Accepted tradeoffs (any error skips, no connect_timeout, a disconnect error could hide the skip) are not re-flagged.
