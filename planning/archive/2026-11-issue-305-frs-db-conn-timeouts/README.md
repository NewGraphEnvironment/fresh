## Outcome

`frs_db_conn()` passed no timeout to libpq, so a database host that went silent blocked the caller forever, and the test gates, which only turn an *error* into a skip, could never fire: a mutation sweep spent 7 h 31 m inside one site on 2026-11-10. `frs_db_conn()` now takes `connect_timeout` (argument, then `PGCONNECT_TIMEOUT`, then 10 s) and `...` for further libpq keywords, and passes keepalive timing defaults (60 s idle, 10 s interval, 6 probes). `frs_habitat()`'s workers get the same bounds through `.frs_conn_params()`, and the two test helpers that bypass `frs_db_conn()` pass them too. The plan review and three code-check rounds changed the build three times: the bounds sit in `frs_db_conn()` rather than the resolver; whole doubles are converted before RPostgres prints them in e-notation; and the approved `tcp_user_timeout` default was dropped after round 1 showed libpq before 12 refuses the keyword. What was learned about libpq and RPostgres is in [`research/libpq_connection_bounds.md`](../../../research/libpq_connection_bounds.md). Follow-ups: #311 (pre-existing: `frs_fwapg_conn()` can be redirected by `PGHOSTADDR`), #312 (workers cannot carry a caller's own connection options).

## Measurement

- macOS keepalive defaults: `keepidle` 7,200,000 ms, `keepintvl` 75,000 ms, `keepcnt` 8, so libpq's default keepalives notice a dead established peer after about 2 h 10 m. The defaults now give about 2 minutes.
- Silent local listener: `timeout expired` in 2.14 s with `connect_timeout = 2`; with no bound, still blocked when killed at 25 s. The same holds through `skip_if_no_conn()`: the gate skips within the bound.
- Guard proof: with `connect_timeout` removed from the bounds, the silent-host test hung until killed at 60 s; restored, it passes in 5 s.
- Live: libpq 16.8 accepts every default keyword (and `tcp_user_timeout`), refuses an unknown one, and refuses `"3e+05"` as an integer value.
- Cost of a fully silent host now: 199 gate calls × up to 10 s per address, about 35 min (70 through `localhost`), down from unbounded.
- Full suite at 4b33a7e: 854 tests, 0 failed, 0 errors, 6 skipped, all environmental. `R CMD check --no-tests`: 0 errors, 0 warnings, 0 notes.

## Evidence

Review files in this directory: `review-305.md` (plan review), `review-round*.md`, `review-verdict.md`.

Closed by: PR for branch `305-frs-db-conn-sets-no-timeout-so-a-silent` (Fixes #305)
