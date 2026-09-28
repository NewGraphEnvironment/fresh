## Clean

Round 3 review of the Phase 3–4 diff for #229: `test-frs_network_features-live.R`, `helper-db.R` (context only), CLAUDE.md and the planning files.

### Mechanism check: could this hide a real regression or leave the old failure mode reachable?

- **The only way it could hide a regression is that any connection error now skips.** A broken setup would skip every run without anyone noticing. That covers a rotated or wrong `PG_PASS_SHARE`, a renamed tunnel DB, a moved port, or `bcfp_conn()` itself breaking. It reaches exactly one place, the gate at `test-frs_network_features-live.R:24`. It cannot hide a `frs_network_features()` regression. The gate runs only `connect()` + `SELECT 1`, and each of the 3 `test_that()` blocks connects again and fails normally once the gate passes. The helper comment and CLAUDE.md both document this, and it is on the accepted-tradeoffs list, so it is not reported as a finding.
- **The old failure mode is no longer reachable in that file.** The old case was a credential being set while the DB was unreachable. `skip_on_cran()`/`skip_on_ci()` still run before the connect. The top-level `skip()` at file scope skips the rest of the file under testthat 3e, and the author's repro on this branch shows SKIP 1 where main shows FAIL 3. A race remains: the tunnel could drop between the gate and a test's connect. The result would then be a real error, which is correct behaviour and not the #229 case.
- **With `PG_PASS_SHARE` unset, the file now tries a real connect.** It passes `password = ""` to `localhost:63333`. libpq then falls back to `PGPASSWORD`/`.pgpass` for user `newgraph`, auth fails, and the file skips. Nothing is written and no error occurs.

### Other test files that open their own connection (the same failure mode as #229)

I grepped `tests/testthat/` for `dbConnect`, `RPostgres::Postgres()` and `frs_db_conn(` (with or without arguments). Every `frs_db_conn()` call outside the helper sits inside a `test_that()` behind `skip_if_not(.frs_db_available(), ...)`. `.frs_db_available()` in `R/utils.R:633` already does a real connect + `SELECT 1` and returns FALSE on any error. The two `frs_params` bcfishpass tests also use `skip_if_no_schema()`. `test-frs_network_features-live.R` is the only file that builds a connection outside `frs_db_conn()`, and this diff gates it. No other file would error instead of skipping when its DB is unreachable.

### Nothing new outside the accepted tradeoffs
- If `dbDisconnect` fails inside `on.exit` while a skip is unwinding, it could turn the skip into an error. This is the same pattern as `skip_if_no_schema()` and `.frs_db_available()` and was already accepted in earlier rounds.

/Users/airvine/Projects/repo/fresh/planning/active/review-p34-round3.md
