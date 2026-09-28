# Code-check: Phases 3-4 (#229), round 2

## Clean

No real issues found.

Checked:
- **Gate connection leak (tunnel up):** `on.exit(DBI::dbDisconnect(conn))` inside the `tryCatch()` expression attaches to `skip_if_no_conn()`'s frame, so the probe connection closes on normal return and when `skip()` unwinds. If `connect()` throws, `on.exit` was never registered, so there is no reference to an unbound `conn`. Nothing leaks.
- **Gate vs. test login mismatch:** the gate and all three tests call the same `bcfp_conn()` with the same env reads. There is no divergence.
- **`PG_PASS_SHARE` unset, so `password = ""`:** libpq treats the empty value as unset and falls back to `PGPASSWORD` from `~/.Renviron` (the local Docker password). There is no `~/.pgpass` on this host. `host`, `port` and `dbname` are explicit (`localhost:63333/bcfishpass`) and override `PG*` env, so the fallback can only change the credential used against the intended tunnel DB. It can never redirect to a different DB. Outcomes: auth fails and the file skips (reason shown), or auth succeeds against the right DB and the tests run correctly. Neither is harmful.
- **Hang:** with the tunnel down the connection is refused fast (verified). A hang could only happen when something accepts on 63333 but never answers, which is the accepted no-`connect_timeout` tradeoff.
- **Top-level skip:** `skip_if_no_conn()` at file top level, after `skip_on_cran()` / `skip_on_ci()`, skips the whole file. CI never attempts the connect.

Verified by run on this host (tunnel down):
- `PG_PASS_SHARE` set: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 0 ]`, reason "Connection refused"
- `PG_PASS_SHARE=""`: `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 0 ]`
