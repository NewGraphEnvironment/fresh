# Findings — Live integration tests error when the database is unreachable instead of skipping (#229)

## Issue context

If we do it: an unreachable database gives skips, not errors, so a test run only fails on real regressions. If we never do: these three tests error in any environment where credentials are set but the server can't be reached, and those errors hide real failures.

`tests/testthat/test-frs_network_features-live.R` decides whether to run from whether a credential env var is set (`PG_PASS_SHARE`). A set credential doesn't mean the server is reachable. When it isn't, `bcfp_conn()` errors at lines 26, 89 and 123 rather than skipping.

Proposed: gate on whether a connection can actually be made. Attempt it once and `skip()` on failure. That is the same shape as `skip_if_no_schema()` in `tests/testthat/helper-db.R`, which tries the query and skips on error. A small shared helper there (for example `skip_if_no_conn()`) would let any live test use it.

## Exploration

- `.frs_db_available()` (`R/utils.R:633`) already does connect + `SELECT 1` → FALSE on error, but only for the default `frs_db_conn()` target. The live file connects to a different DB (tunnel, port 63333), so it needs a connector argument.
- Other DB tests gate per-test with `skip_if_not(.frs_db_available(), "DB not available")`.
- `bcfp_conn()` passes `password = Sys.getenv("PG_PASS_SHARE")`; libpq ignores empty-string conninfo values, so an unset var falls through to `.pgpass` / fails to connect → skip.
