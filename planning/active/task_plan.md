# Task: frs_db_conn(): default to standard libpq env vars instead of PG_*_SHARE (#213)

`frs_db_conn()` hardcodes `PG_*_SHARE` env vars as its defaults
(`PG_DB_SHARE`, `PG_HOST_SHARE`, ...) and `stop()`s if they aren't set. This bakes
New Graph's internal "shared DB" deployment vocabulary into a general-purpose package
and locks every caller onto that one profile — there's no clean way to point it at a
different database (e.g. the local fwapg Docker DB from `fresh/docker/`) without passing
every argument explicitly.

## Decisions (user, plan mode)

- Standard `PG*` vars take precedence; `PG_*_SHARE` is fallback.
- Fallback emits a once-per-session `message()` (not a warning).

## Phase 1: Tests first
- [x] Replace the `frs_db_conn stops on missing env vars` block (`tests/testthat/test-utils.R:70-75`) with `.frs_conn_resolve()` unit tests, using `withr::local_envvar` and no database:
  - standard vars resolve
  - standard vars win when both groups are set
  - the `PG_*_SHARE` fallback resolves and messages once per session, then stays silent
  - groups are never mixed (`PGHOST` set plus `PG_DB_SHARE` set gives a NULL dbname, not bcfishpass)
  - explicit arguments override the environment
  - nothing set returns all NULL
  - `PGSERVICE` / `PGHOSTADDR` alone count as "standard group set" (no SHARE fallback)
  - fallback password: `PG_PASS_SHARE` passed when non-empty, dropped when `""`
  - reset the once-flag with `withr::defer()` on the package-env flag (no rlang)
- [x] Confirm the new tests fail on main (trivial red — resolver doesn't exist yet).

## Phase 2: Implement
- [x] Add `.frs_conn_resolve()` and the session-message state in `R/frs_db_conn.R`.
- [x] Rewrite `frs_db_conn()` with NULL defaults, resolve, and `do.call` dbConnect. Update the roxygen: precedence order, the deprecation note, a pointer to `docker/` for local fwapg, and the `@examples`.
- [x] Fix `.frs_conn_params()` roxygen (still names `PG_*_SHARE`); document that workers get `password = ""` → libpq reads the worker's `PGPASSWORD`, so the SHARE-fallback path needs an explicit `password` arg to `frs_habitat()` (pre-existing, doc only).
- [x] `devtools::document()`, then check that the new unit tests pass.

## Phase 3: Test-suite guards
- [x] Replace the 21 `skip_if(Sys.getenv("PG_DB_SHARE") == "", ...)` guards across 11 test files with `skip_if_not(.frs_db_available(), "DB not available")`, the existing helper at `R/utils.R:633`.
- [x] Add a test helper `skip_if_no_schema(schema)` in `tests/testthat/helper-db.R`. Apply it to the `bcfishpass.*` tests in `test-frs_break.R`, `test-frs_extract.R`, `test-frs_network_upstream.R`, `test-frs_network.R`, and the two live `frs_params(conn)` tests in `test-frs_params.R` (~931-953, default table `bcfishpass.parameters_habitat_thresholds`). `test-frs_network_features.R` refs are mocked — no change.
- [x] Note: ~45 existing `.frs_db_available()`-gated tests also move from tunnel to local fwapg on m4; they rely on `whse_basemapping` + `working` (created by `docker/load.sh:70`).
- [x] Leave `test-frs_network_features-live.R` alone. It builds its own tunnel connection and is gated on `PG_PASS_SHARE`.
- [x] Run the full `devtools::test()` against local fwapg (the new default). Record pass/skip counts; zero new failures vs main baseline, bcfishpass tests skipped.
- [x] Fallback run (`PG*` unset, `PG_*_SHARE` set): message fires once; bcfishpass tests run when tunnel is up (skip/record if tunnel down). — message + connect verified live against local 5432; tunnel down this session, tunnel-side run not done.

## Phase 4: Docs
- [x] CLAUDE.md: architecture line for `frs_db_conn.R`, Dependencies "Connection" line, and the "Testing on alternate hosts" section incl. the m1 recipe — standard `PG*` now drive tests; tunnel only when `PG*` point at it.
- [x] Update the connection line in README.md. (`docker/README.md` has no `frs_db_conn` refs — no-op.)
- [x] Header comment in bcfishpass-dependent `data-raw/` scripts (`pipeline_wsg.R`, `vignette_habitat_pipeline.R`, `example_byman_ailport.R`) noting they need a conn with the bcfishpass schema.
- [x] Add a comment above `conn <- frs_db_conn()` in the vignette `.Rmd.orig` files saying these chunks need a database with bcfishpass (the tunnel). Do not re-knit.
- [x] Add a NEWS.md entry flagging the behaviour change: machines with both `PG*` and `PG_*_SHARE` set now connect to the `PG*` target. The version bump to 0.36.0 is the final commit.

## Phase 5: Cross-repo follow-up
- [x] Draft a link issue: `lnk_db_conn()` (`link/R/lnk_db_conn.R:38`) still prefers `PG_*_SHARE`, which now diverges from fresh. Ask the user before filing.

## Validation

- [x] Tests pass
- [x] `lintr::lint_package()` clean on touched files
- [x] `/code-check` clean on each commit
- [x] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
