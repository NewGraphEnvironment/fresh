# Review round 4 — #213 frs_db_conn libpq env resolution

## Mechanism

Two linked mechanisms. (1) A copy-pasteable recipe whose values have to match the
user's environment (credentials, DB name, running container). (2) `.frs_db_available()`
turns any connection failure into `FALSE`, and every live test reads that `FALSE` as a
skip. When the two combine, a recipe with a wrong value produces an all-skip, green
suite. The round-3 fix added a guard to break the chain:
`stopifnot(fresh:::.frs_db_available())`. But that guard runs *before*
`devtools::test()`, so `fresh:::` resolves to whatever `fresh` namespace is loaded,
which in a fresh R session is the **installed** package, not the dev source. The
installed package on this machine is 0.34.0. Its `frs_db_conn()` defaults every
argument to `Sys.getenv("PG_*_SHARE")` and passes the values explicitly, and libpq
explicit params override `PG*` env. So the guard checks the legacy SHARE target, not
the `PG*` values the recipe just set.

Verified empirically. With SHARE pointed at a working DB and bogus `PG*`
(`PGDATABASE=does_not_exist`, `PGUSER=nobody`):
- the installed `fresh:::.frs_db_available()` returned `TRUE`;
- the same call after `devtools::load_all()` returned `FALSE`.

So the guard passes while every live test would skip.

Places the mechanism reaches:

1. CLAUDE.md "To run against the bcfishpass tunnel" `Sys.setenv` + `stopifnot` snippet.
   The values are now correct: `PGUSER`/`PGPASSWORD` come from `PG_*_SHARE`, and on
   this machine `PG_DB_SHARE=bcfishpass`, `PG_PORT_SHARE=63333` and
   `PG_HOST_SHARE=localhost` all match the literals (checked by equality only). The
   guard is **not correct**: it evaluates the installed package (FINDING 1). On this
   machine the SHARE target happens to equal the recipe's `PG*` target, so it is
   accidentally right today. It breaks when the literals drift from SHARE, or when no
   `fresh` is installed (then it errors "no package called fresh", which is loud and
   acceptable).
2. CLAUDE.md cross-host m1 snippet (`Sys.setenv(PGHOST..., PGUSER="postgres",
   PGPASSWORD="postgres") ... devtools::test()`). The values match
   `docker/docker-compose.yml` (postgres/postgres/fwapg, 5432). The snippet has **no
   guard**. If m1's Docker fwapg is down or its creds differ, every live test skips,
   and the backgrounded log reads green (FINDING 2). The same fix was not applied to
   this sibling snippet.
3. CLAUDE.md prose "a plain `devtools::test()` runs against local fwapg". This relies
   on `~/.Renviron` `PG*`, which is set here (`PGHOST`/`PGPORT`/`PGDATABASE`/`PGUSER`/
   `PGPASSWORD` names are present; `PGDATABASE==fwapg` confirmed). If the local
   container is down, the result is an all-skip green run. This is the accepted
   `.frs_db_available()` design and prose rather than a recipe, but the same
   check-first warning would apply. Noted, not a finding.
4. CLAUDE.md Connection line, README.md, NEWS.md. These are descriptive, with no
   runnable recipe. Correct.
5. R/frs_db_conn.R roxygen `@examples` (`\dontrun`). Example 2,
   `frs_db_conn(port = 63333, dbname = "bcfishpass")`, takes user/password from `PG*`.
   With the typical local `PG*` that means tunnel auth fails. The failure is **loud**
   (error, not skip), so it is not the silent mechanism. Correct as a semantics demo.
6. data-raw/example_byman_ailport.R, pipeline_wsg.R, vignette_habitat_pipeline.R
   headers ("e.g. PGPORT=63333 PGDATABASE=bcfishpass"). The recipe is incomplete: it
   leaves user/password at the local values. Scripts call `frs_db_conn()` directly, so
   a mismatch errors loudly. Not silent. Correct enough.
7. vignettes/*.Rmd.orig comments. The knit calls `frs_db_conn()` directly, so failure
   is loud. Correct.
8. tests/testthat/helper-db.R `skip_if_no_schema()`. `tryCatch(error = FALSE)` turns a
   connect/query error into a skip. It is only reached after `.frs_db_available()`
   passes, so a connect failure there is unlikely. Its purpose (skip `bcfishpass`
   tests on local fwapg) is intended. Note: even the tunnel recipe's `stopifnot` does
   not prove the `bcfishpass` tests ran, only that a connection works. Acceptable.
9. Live tests switched from `skip_if(PG_DB_SHARE == "")` to
   `skip_if_not(.frs_db_available())`: test-frs_db_conn, db_query, lake_fetch,
   network_downstream/upstream/prune, point_locate, stream_fetch, wetland_fetch and
   wsg_drainage. This is the accepted design. Under `devtools::test()` these resolve
   to the dev namespace, so they are correct.
10. test-frs_params `skip_if_no_schema("bcfishpass")`. Correct, same as item 8.
11. test-frs_db_conn resolver unit tests (`local_pg_env`, `fresh:::.frs_state`,
    `fresh:::.frs_conn_resolve`). No DB involved. Under `load_all`, `fresh:::` is the
    dev namespace. `withr` is in Suggests. Correct.

## Findings

- **[severity: fragile]** CLAUDE.md, tunnel snippet
  `stopifnot(fresh:::.frs_db_available())`. Run before `devtools::test()` in a fresh
  session, `fresh:::` loads the installed package (0.34.0 here). Its `frs_db_conn()`
  passes `PG_*_SHARE` explicitly and ignores the `PG*` vars the snippet just set. The
  guard therefore checks the legacy target, not the one the tests will use.
  Demonstrated: `TRUE` from the installed guard vs `FALSE` after `load_all` with a
  broken `PG*`. It only works today because SHARE and the recipe coincide. Fix: call
  `devtools::load_all()` before the check, e.g.
  `devtools::load_all(); stopifnot(.frs_db_available())`. Or make it loud and
  version-independent: `devtools::load_all(); DBI::dbDisconnect(frs_db_conn())`.
- **[severity: fragile]** CLAUDE.md, cross-host m1 step 3 snippet. It has the same
  `Sys.setenv` → `devtools::test()` recipe with no connection check. If m1's Docker
  fwapg is not running, or its creds differ from postgres/postgres, every live test
  skips. The log in `/tmp/m1_fresh_test.log` then reports a pass. Add the same
  (corrected) guard after `Sys.setenv`, e.g.
  `devtools::load_all(); stopifnot(.frs_db_available());` before
  `testthat::set_max_fails(Inf)`.

/Users/airvine/Projects/repo/fresh/planning/active/review-round4.md
