# Code review — round 1 (#213, branch vs main)

## Clean

No issues found.

Verified:
- `.frs_conn_resolve()`: explicit args filtered by `.frs_is_set()` (NULL / "" / NA dropped), standard-group detection over PGHOST/PGHOSTADDR/PGPORT/PGDATABASE/PGUSER/PGSERVICE returns explicit args only (libpq reads the rest), SHARE group fills only unset fields, and `PG_PASS_SHARE` alone falls through to "default" (intended). Output order matches the test's `expect_identical()` list.
- `.frs_state` is an environment in the namespace; mutating its contents is allowed after the namespace is locked.
- `frs_habitat()` workers: `.frs_conn_params()` still passes `password = ""`. libpq treats an empty value as unset and falls back to PGPASSWORD / .pgpass. That behaviour predates this branch and is now documented in both NEWS and the helper docs.
- Tests: `local_pg_env()` unsets all 12 vars through `withr::local_envvar(NA)` and restores the message flag through `withr::defer`. Calling it twice in one block stacks correctly. `expect_silent(res <- ...)` and `expect_message(res <- ...)` assign in the caller.
- `skip_if_no_schema()` quotes its input with `dbQuoteString`, disconnects through `on.exit` inside `tryCatch`, and returns FALSE on error. It is placed inside both `frs_params` DB `test_that` blocks, after the availability skip.
- The other `bcfishpass.*` / `bcfishobs.*` references in tests are mock-connection SQL-string assertions, so they need no schema guard.
- The removed `test-utils.R` "stops on missing env vars" test matches the removed `stop()` calls.
