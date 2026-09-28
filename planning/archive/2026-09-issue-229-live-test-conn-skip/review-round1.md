# Code review round 1 — #229 skip_if_no_conn()

## Clean
No issues found.

Notes (verified, not defects):
- `on.exit()` inside the `tryCatch()` expression registers on `skip_if_no_conn()`'s frame (same pattern as `skip_if_no_schema()` and `.frs_db_available()`), so the connection is disconnected on both the success path and when `skip()` unwinds. When `connect()` itself errors, `on.exit` is never registered, so there's no reference to an undefined `conn`.
- The guard fails toward skipping, not toward passing. Any error from connect or `SELECT 1` is turned into `skip()`, and success returns `NULL` without a skip condition.
- Ran `testthat::test_file("tests/testthat/test-helper-db.R")` against local fwapg: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 3 ]`. The failing-connector fixture does reach the skip branch, and the message assertion matches the error text.
- `bcfp_conn` in `test-frs_network_features-live.R` is a zero-arg function returning a DBI connection, so it matches the helper's `connect` contract for Phase 3.
