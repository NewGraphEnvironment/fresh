# Review round 3 — #213 frs_db_conn libpq env resolution

## Findings

- **[severity: bug]** CLAUDE.md:131-133 ("To run against the bcfishpass tunnel" snippet) — the snippet hardcodes `PGUSER = "newgraph"` but takes the password from `Sys.getenv("PG_PASS_SHARE")`. On this dev box `PG_USER_SHARE` in `~/.Renviron` is **not** `newgraph` (checked by pattern match, value not printed; `PG_DB_SHARE='bcfishpass'` and `PG_PORT_SHARE=63333` do match the snippet). So the snippet pairs the `PG_PASS_SHARE` password with a different role and authentication fails. Because every DB test is now gated on `.frs_db_available()` (which returns FALSE on any connection error), the suite doesn't fail. Every live test skips and the run reports green, which is the opposite of what someone following "run against the tunnel" expects. Fix: `PGUSER = Sys.getenv("PG_USER_SHARE")`, which matches how `test-frs_network_features-live.R:20` resolves the user. It would also help to tell readers to check that the skip count dropped.

## Checked and clean

- `local_pg_env()` (test-frs_db_conn.R): `withr::local_envvar()` with `NA` unsets all 12 vars the resolver reads, so `~/.Renviron` values (this box sets both PG* and PG_*_SHARE) cannot leak in. The `.frs_state$share_msg_shown` reset/restore is per-test and LIFO-safe when called twice in one block. The message test would fail rather than pass vacuously if the flag were already TRUE, and the trailing `expect_silent` proves the flag is actually set.
- Resolver tests exercise each named branch: standard-only, both groups, PGHOST blocking PG_DB_SHARE, PGSERVICE / PGHOSTADDR alone, the share fallback, an empty PG_PASS_SHARE, explicit per-field override in both groups, explicit "" and default. None can pass with the env clearing skipped, because the standard-vs-share outcomes differ.
- `skip_if_no_schema()`: an error gives a skip, but it only runs after `.frs_db_available()` has passed. When the schema is present the query returns 1 row and the test runs. It never turns a genuine test failure into a skip beyond the connection-level case. `on.exit` inside the `tryCatch` expr registers on the helper's frame, so the disconnect runs.
- All 21 swapped `skip_if_not(.frs_db_available(), ...)` guards sit inside `test_that()` blocks. `.frs_db_available` is internal (R/utils.R:633), is visible under `load_all` / the testthat package env, and was already used the same way in about 60 pre-existing tests.
- The ssh `"..."` block in CLAUDE.md step 3: inside the outer single quotes `\"` is kept literally, and the remote shell turns it into `"` inside the `Rscript -e "..."` double-quoted string. The env var names are correct.
- NEWS.md: the var names and the behaviour-change description match `.frs_conn_resolve()`.
