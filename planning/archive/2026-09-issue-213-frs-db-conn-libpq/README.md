## Outcome

`frs_db_conn()` now resolves explicit args first, then the standard libpq env vars (`PGHOST`/`PGPORT`/`PGDATABASE`/`PGUSER`/`PGPASSWORD`/`PGSERVICE`), then legacy `PG_*_SHARE`, then libpq defaults.
- `PG_*_SHARE` is used only when no standard var is set, and shows a deprecation message once per session.
- The two groups are never mixed.
- The `stop()`s on unset vars are gone.

On hosts that set both groups, as m4's `~/.Renviron` does, a bare `frs_db_conn()` now reaches local Docker fwapg (5432) instead of the bcfishpass tunnel (63333). NEWS flags this as a behaviour change.

Test-suite changes:
- The 21 `PG_DB_SHARE` skip guards now use `.frs_db_available()`.
- The new `skip_if_no_schema()` helper covers the two live `frs_params(conn)` tests. Local fwapg has no `bcfishpass` schema.
- Every other `bcfishpass.*` reference in tests turned out to be mocked SQL.

`/code-check` ran four rounds. Round 3 caught a doc recipe that would silently skip every test because the tunnel user was wrong. Round 4 found a defect inside that fix: `fresh:::` before `load_all` calls the installed package, which still reads SHARE vars. That was closed by enumeration: both recipes were executed against good and bad targets.

The follow-up for link's `lnk_db_conn()`, which still prefers SHARE, is drafted in `findings.md` and not yet filed.

## Measurement

Full `devtools::test()` against local fwapg:

| Run | Pass | Skip | Fail |
|-----|------|------|------|
| main (SHARE override pointed at local) | 495 | — | 6 |
| branch (default `~/.Renviron` → `PG*` → local) | 503 | 2 | 4 |

- The 2 skips are the `bcfishpass` `frs_params` tests.
- All 4 branch failures are pre-existing:
  - 3 in `test-frs_network_features-live.R`, which hardcodes the tunnel, and the tunnel was down
  - 1 is the `frs_params` CO rear-rule count (#223/#202)
- The tunnel-side fallback run was not possible because 63333 refused connections all session. The SHARE fallback was verified live against local 5432: the message fired once over two calls and the connection succeeded.

Closed by: PR (see branch `213-frs-db-conn-default-to-standard-libpq-en`)
