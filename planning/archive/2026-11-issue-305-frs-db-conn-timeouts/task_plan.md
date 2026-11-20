# Task: frs_db_conn() sets no timeout, so a silent database host blocks the suite instead of skipping (#305)

`frs_db_conn()` builds its `DBI::dbConnect()` call from the resolved libpq parameters and passes no timeout of any kind (`R/frs_db_conn.R:59`). libpq's `connect_timeout` defaults to no limit, and no keepalive or `tcp_user_timeout` option is set either, so there are two unbounded waits: a connect to a host that does not answer the handshake, and a connection that establishes and then stops carrying traffic. `skip_if_no_conn()` catches only an error, so a silent host blocks every gated test instead of skipping.

## Context

`frs_db_conn()` (`R/frs_db_conn.R:59`) passes no timeout to `DBI::dbConnect()`. That leaves
two waits with no limit: a host that never answers the handshake, and a connection that is
established and then stops carrying traffic. `skip_if_no_conn()` (`tests/testthat/helper-db.R:21`)
and `.frs_db_available()` (`R/utils.R:1004`) only catch an *error*, so a silent host blocks the
whole suite where the docs promise a skip. On 2026-11-10 that cost 7 h 31 m inside one
mutation-sweep site. The fix: give libpq finite bounds, so a silent host raises an error, and an
error is something every existing gate already turns into a skip.

**Measured on this Mac:** `net.inet.tcp.keepidle` = 7,200,000 ms, `keepintvl` = 75,000 ms,
`keepcnt` = 8. libpq already turns keepalives on by default, but with these OS values a dead
established socket takes about 2 h 10 m to fail. That is the "hours" in the issue.
RPostgres 1.4.10 forwards `...` to libpq as connection keywords, and libpq rejects a keyword it
does not know, so one live connect proves every keyword is accepted.

## Decided at the gate

Recommended in plan mode and approved by the owner as written, 2026-11-20.

1. **API:** `frs_db_conn(dbname, host, port, user, password, connect_timeout = NULL, ...)`.
   - `connect_timeout` resolves like the other fields: the explicit argument first, then
     `PGCONNECT_TIMEOUT` (when it is set, nothing is passed, so libpq reads it), then a package
     default of **10 s**.
   - `...` goes to libpq unchanged and overrides any default below, e.g. `keepalives = 0`.
2. **Defaults for an established connection:** `keepalives = 1`, `keepalives_idle = 60`,
   `keepalives_interval = 10`, `keepalives_count = 6` (a dead peer fails in about 2 min), plus
   `tcp_user_timeout = 120000` ms. That last one covers the case keepalives miss, data sent and
   never acknowledged, but only on Linux (CI); on macOS libpq ignores it. Long queries are not
   bounded: the server's kernel answers keepalive probes and acknowledges data while the query
   runs. `statement_timeout` stays out of scope, as the issue says.
   - **Corrected 2026-11-20 by code-check round 1:** `tcp_user_timeout` is no longer a default.
     libpq knows the keyword only from PostgreSQL 12 and refuses it before that, so a system
     libpq 10 or 11 would have failed every connect. It did nothing on macOS, where the hang was
     observed, and on Linux it carried an unverified risk of dropping a stalled `COPY`. It stays
     available through `...`.
3. **One source for the bounds:** an internal `.frs_conn_bounds()` that both
   `.frs_conn_resolve()` and `.frs_conn_params()` call. Without it, `frs_habitat()`'s mirai
   workers (`R/frs_habitat.R:395`, `:581`) would reconnect through `DBI::dbConnect` with no bounds.
4. **The test helpers that bypass `frs_db_conn()` get the bounds too:** `bcfp_conn()` in
   `test-frs_network_features-live.R` (a tunnel: bounded at connect only, since keepalives are answered by the local ssh end; review finding 4) and
   `frs_fwapg_conn()` in `helper-db.R`. The `data-raw/` scripts that call `DBI::dbConnect`
   directly are left alone (they are interactive one-offs) and listed in the PR.
5. **NEWS and the version bump** are left to `/gh-pr-merge`.

## Phase 1: Failing tests (`tests/testthat/test-frs_db_conn.R`)
- [x] `connect_timeout` resolution: an explicit value wins; with `PGCONNECT_TIMEOUT` set the param is absent; with neither it is 10. Checked under each source (standard, share, default)
- [x] Keepalive defaults (and, until code-check round 1, `tcp_user_timeout`) are present under all three sources, and `...` overrides them (`keepalives = 0`)
- [x] An invalid `connect_timeout` (negative, non-whole, NA, a vector) is refused with a clear error. `0` is allowed, because libpq reads it as "no limit"
- [x] `.frs_conn_params()` carries the same bounds, so the worker path is covered
- [x] A silent host with no database: `serverSocket()` on a free localhost port that is never accepted. The kernel completes the handshake and libpq then waits for a startup reply that never comes. Assert `frs_db_conn(host = "127.0.0.1", port = p, connect_timeout = 2)` errors within 15 s (`skip_on_cran()`)

## Phase 2: Implement (`R/frs_db_conn.R`)
- [x] `.frs_conn_bounds(connect_timeout, ...)` validates the timeout, resolves it (argument, then env, then default) and merges the keepalive defaults with `...`
- [x] `frs_db_conn()` gains `connect_timeout` and `...` and adds the bounds to the resolved params itself (not inside `.frs_conn_resolve()`, whose share branch keeps identity fields only: review finding 3); `.frs_conn_params()` adds them for the workers
- [x] Whole doubles reach libpq as integers, never e-notation (`.frs_libpq_whole()`; review finding 2)
- [x] roxygen: `@param connect_timeout`, `@param ...`, and a "Timeouts" section (what each bound does, that long queries are not bounded, that `tcp_user_timeout` is Linux only, and the limits from review findings 4, 5, 7); `devtools::document()`

## Phase 3: Test helpers and docs
- [x] `bcfp_conn()` and `frs_fwapg_conn()` pass the bounds (`do.call` with `fresh:::.frs_conn_bounds()`)
- [x] `CLAUDE.md` "Testing on alternate hosts": a host that goes silent now skips, each gated test after up to `connect_timeout` per address (review finding 6), the same as one that refuses

## Validation
- [x] Tests pass: full `devtools::test()` against the local fwapg. The existing live test "frs_db_conn returns a DBI connection" then proves libpq accepts every default keyword (it passed at 4b33a7e with `tcp_user_timeout` still a default, so that keyword too)
- [x] Prove the guard fires: in a worktree, remove `connect_timeout` from `.frs_conn_bounds()`'s output (dropping only the default cannot work, since the test passes 2 explicitly: review finding 1) and run the silent-host test under GNU `timeout 60`; it must hang (killed), then pass with the default restored. Record the result in `progress.md`
- [x] `lintr::lint_package()`: no new lints, compared per file against `origin/main`
- [x] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion

