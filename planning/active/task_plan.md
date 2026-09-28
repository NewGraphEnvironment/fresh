# Task: Live integration tests error when the database is unreachable instead of skipping (#229)

`tests/testthat/test-frs_network_features-live.R` decides whether to run from whether a credential env var is set (`PG_PASS_SHARE`). A set credential doesn't mean the server is reachable. When it isn't, `bcfp_conn()` errors at lines 26, 89 and 123 rather than skipping.

Design: `skip_if_no_conn(connect = frs_db_conn)` in `tests/testthat/helper-db.R` — calls `connect()`, runs `SELECT 1`, disconnects, skips with the error message on failure. Same shape as `skip_if_no_schema()`. Called once at file top level in the live file with its own `bcfp_conn`. `.frs_db_available()` (`R/utils.R`) left as-is.

## Phase 1: Tests for the helper
- [ ] Add `tests/testthat/test-helper-db.R`: connector that errors → `skip_if_no_conn()` signals a skip (`expect_condition(..., class = "skip")`), and skip message carries the error text
- [ ] Success path: with `skip_if_not(.frs_db_available())`, `skip_if_no_conn()` (default `frs_db_conn`) returns without skipping
- [ ] Confirm the new tests fail (helper not yet defined)

## Phase 2: Helper
- [ ] Add `skip_if_no_conn(connect = frs_db_conn)` to `tests/testthat/helper-db.R`, same shape as `skip_if_no_schema()`
- [ ] Phase 1 tests pass

## Phase 3: Gate the live file on reachability
- [ ] `test-frs_network_features-live.R`: replace the `PG_PASS_SHARE` `skip_if()` with `skip_if_no_conn(bcfp_conn)` after `bcfp_conn` is defined (keep `skip_on_cran()` / `skip_on_ci()` first so CI never attempts the connect)
- [ ] Update the file header comment (skip condition now "tunnel unreachable", not "PG_PASS_SHARE unset")
- [ ] Verify: run the file with the tunnel down → reports skip, 0 errors; with tunnel up (if available) → 3 tests run

## Phase 4: Docs
- [ ] CLAUDE.md "Testing on alternate hosts" note: live file gated on a reachable tunnel connection, not `PG_PASS_SHARE`; mention `skip_if_no_conn()` alongside `skip_if_no_schema()`
- [ ] NEWS.md entry (internal/test-only change)

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
