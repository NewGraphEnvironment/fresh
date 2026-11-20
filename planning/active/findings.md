# Findings: frs_db_conn() sets no timeout (#305)

## Issue context

## Problem

`frs_db_conn()` builds its `DBI::dbConnect()` call from the resolved libpq
parameters and passes no timeout of any kind (`R/frs_db_conn.R:59`). libpq's
`connect_timeout` defaults to no limit, and no keepalive or `tcp_user_timeout`
option is set either, so there are two unbounded waits:

- a connect to a database host that does not answer the handshake blocks in the
  connect phase;
- a connection that establishes and then stops carrying traffic blocks on its
  first query until the OS TCP stack gives up, which can be hours.

Neither raises promptly. `connect_timeout`, `keepalives*` and
`tcp_user_timeout` appear nowhere in `R/` or `tests/`.

## Why it matters: the test gate cannot fire

`skip_if_no_conn()` (`tests/testthat/helper-db.R:21`) wraps the connect and a
`SELECT 1` in `tryCatch(error = ...)` and skips on the error. A blocking
connect, or a blocking `SELECT 1`, never raises — so every gated integration
test queues behind it indefinitely rather than skipping.

That is the opposite of the documented contract. `CLAUDE.md`, "Testing on
alternate hosts": *"Failed connects become skips, not failures"*, and *"It skips
whenever that connection can't be made, so a set `PG_PASS_SHARE` with the server
unreachable skips instead of erroring."* Both hold for a host that **refuses**.
Neither holds for one that goes **silent**.

## Observed, 2026-11-10

A long validation run (`dev/mutation_sweep.R`, 25 sites, each a full test-suite
pass) completed 9 sites at about 19 minutes each, then spent 7 h 31 m inside
site 10 without finishing, and was killed.

| probe | reading |
|---|---|
| driver R process CPU | 10 min 17 s over 10 h 18 m elapsed — 1.7%, so blocked on I/O, not looping |
| its only socket | to the database on 5432: `SYN_SENT` at one sample, `ESTABLISHED` three minutes later |
| ICMP to the database host | 33% loss / 2446 ms avg, then 0% loss / 1524 ms avg / 3241 ms max, then 100% loss |
| ICMP to the local gateway, same minutes | 0% loss / 37 ms avg — so the local link was not the cause |
| log output rate | 240 lines/min over the first 9 sites, 5 lines/min during site 10 |

A second, independent client on the same machine could not acquire a connection
during the same window, so this was not one process's own state.

With a finite bound in place, that window would have produced an honest wall of
skips within minutes, instead of a run that could not end.

## The sweep's own guards cannot see this

`dev/mutation_sweep.R` refuses unless the baseline is 0 red and 0 skipped
(`:39`), and discards the whole table unless a second baseline afterwards still
reads 0 red and 0 skipped (`:50-51`). Both read a **reported** result. A blocked
run reports nothing, so neither guard fires. It never yields a wrong answer —
only no answer, with nothing bounding how long that takes.

## Proposal, for discussion

1. **A finite connect bound.** `frs_db_conn()` gains a `connect_timeout`
   argument resolved like every other field — explicit argument, then the
   environment (libpq reads `PGCONNECT_TIMEOUT`), then a package default — so a
   default cannot silently override a value the caller's environment already
   sets.
2. **A bound on an established-then-silent connection**, via `keepalives = 1`
   with `keepalives_idle` / `keepalives_interval` / `keepalives_count`, or
   `tcp_user_timeout`. This is the half that covers the case actually observed:
   the socket reached `ESTABLISHED`, so `connect_timeout` alone would not have
   helped.
3. `skip_if_no_conn()` needs no change and cannot be fixed on its own — R
   cannot interrupt a blocking call inside libpq, so the bound has to come from
   the connection parameters.

Precedent in the package: `frs_migration_trial()` sets
`SET LOCAL lock_timeout = '60s'` (`R/frs_migration_trial.R:100`) for exactly
this reason — it turns a hang into an error a caller can read.

## Not in scope

A server-side `statement_timeout`. The pipeline has queries that legitimately
run for many minutes, and bounding those is a separate question from bounding a
connection that is not carrying traffic at all.


## Plan-mode measurements (2026-11-20)

- macOS `sysctl net.inet.tcp.keepidle/keepintvl/keepcnt` = 7200000 ms / 75000 ms / 8: with libpq default keepalives on, a dead established socket fails after about 2 h 10 m.
- RPostgres 1.4.10 `dbConnect` signature takes `...`, forwarded to libpq as connection keywords.
- `frs_habitat()` workers reconnect via `DBI::dbConnect(conn_params)` from `.frs_conn_params()` (`R/frs_habitat.R:395`, `:581`), bypassing `frs_db_conn()`.
- Test helpers bypassing `frs_db_conn()`: `bcfp_conn()` (`test-frs_network_features-live.R:16`), `frs_fwapg_conn()` (`helper-db.R:39`). data-raw scripts also call `DBI::dbConnect` directly: `point_snap_tie_sweep.R`, `network_features_exists.R`, `network_features_prefilter.R`, `bcfishpass_falls.R`, `bcfishpass_crossings.R`.

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Fixture and keyword probes (2026-11-20)

- Silent listener (`serverSocket()` never accepted) against `DBI::dbConnect(host = "127.0.0.1", connect_timeout = 2L)`: `timeout expired` after 2.14 s. The same call with no `connect_timeout`, under GNU `timeout 25`: killed (exit 124). So the fixture reaches the unbounded wait and the bound ends it.
- Live connect to the local fwapg with `connect_timeout`, `keepalives`, `keepalives_idle`, `keepalives_interval`, `keepalives_count`, `tcp_user_timeout`: succeeds on macOS. An unknown keyword is refused (`invalid connection option "not_a_keyword"`), so a successful live connect proves libpq accepts each default.
- Red phase: before the implementation the silent-host test fails on its `timeout expired` match. `connect_timeout` is an unused argument there, which errors at once and is skipped, so the message assertion is what keeps the test from passing vacuously.
