# Findings — frs_db_conn(): default to standard libpq env vars instead of PG_*_SHARE (#213)

## Issue context

## Problem
`frs_db_conn()` hardcodes `PG_*_SHARE` env vars as its defaults
(`PG_DB_SHARE`, `PG_HOST_SHARE`, ...) and `stop()`s if they aren't set. This bakes
New Graph's internal "shared DB" deployment vocabulary into a general-purpose package
and locks every caller onto that one profile — there's no clean way to point it at a
different database (e.g. the local fwapg Docker DB from `fresh/docker/`) without passing
every argument explicitly.

## Proposed solution
Default to the **standard libpq env vars** that `RPostgres::Postgres()` already honors
(`PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`), plus explicit args. Then the
function connects to whatever the caller's standard env/args point at — local Docker fwapg
or a remote DB — with no org-specific profile concept.

Back-compat: existing callers rely on the `PG_*_SHARE` defaults. Provide a transition —
fall back to `PG_*_SHARE` when the standard vars are unset (with a deprecation note), or
document the env rename — so current pipelines keep working.


## Exploration (2026-09-26)

- `~/.Renviron` on m4 sets both groups: `PG_*_SHARE` -> tunnel (localhost:63333, db bcfishpass); `PGHOST/PGPORT/PGDATABASE/PGUSER` -> local Docker fwapg (5432, fwapg). Precedence decides where a bare `frs_db_conn()` lands.
- Local fwapg has `whse_basemapping`, `bcfishobs`, `fresh` schemas; no `bcfishpass`. Tests reading `bcfishpass.*` via default conn: test-frs_break.R, test-frs_extract.R, test-frs_network_upstream.R, test-frs_network.R.
- 21 `skip_if(Sys.getenv("PG_DB_SHARE") == "")` guards across 11 test files; `.frs_db_available()` (R/utils.R:633) already exists as a connect-probe.
- `.frs_conn_params()` + mirai workers in frs_habitat.R pass explicit params — unaffected.
- link's `lnk_db_conn()` (link/R/lnk_db_conn.R:38) prefers PG_*_SHARE then PG* — will diverge from fresh after this change.
- Group-level resolution (not per-field) avoids mixing tunnel dbname with a local host.

## Plan-agent review (2026-09-26) — folded into task_plan

- **Blocker:** `test-frs_params.R` live tests call `frs_params(conn)` → default `bcfishpass.parameters_habitat_thresholds` (`R/frs_params.R:62`). Added to schema-skip list.
- ~45 `.frs_db_available()`-gated tests silently move tunnel → local; rely on `working` schema from `docker/load.sh:70`.
- `frs_habitat()` workers: `password = ""` → libpq uses worker `PGPASSWORD`; wrong for SHARE-fallback tunnel runs unless `password` passed. Pre-existing; documented.
- libpq honours `PGPASSWORD` / `.pgpass` when password omitted; RPostgres drops NULL args. SHARE group must pass `PG_PASS_SHARE` explicitly (libpq never reads `*_SHARE`).
- No positional-arg callers (only external named-arg use in stewardship_upper_wedzin_kwa). CI (pkgdown only) has no DB.
- `PGSERVICE` / `PGHOSTADDR` added to standard-group trigger set.
- Bare `frs_db_conn()` callers needing bcfishpass (data-raw scripts, vignette .Rmd.orig) get "relation does not exist" on hosts with both groups set → NEWS flags behaviour change.

## Draft link issue (not filed — awaiting user OK)

**Title:** lnk_db_conn(): prefer standard PG* env vars to match fresh 0.36.0

**If done:** `lnk_db_conn()` and `fresh::frs_db_conn()` connect to the same database in the same environment. **If never:** on hosts that set both groups, a bare `lnk_db_conn()` goes to the `PG_*_SHARE` target (the bcfishpass tunnel) while `frs_db_conn()` goes to the `PG*` target (local fwapg). A pipeline mixing the two helpers reads from one DB and writes to another.

fresh#213 (fresh 0.36.0) changed `frs_db_conn()` to resolve explicit args → standard libpq vars → legacy `PG_*_SHARE` (deprecated, message once) → libpq defaults, and never mixes the groups. `lnk_db_conn()` (`R/lnk_db_conn.R:38`) still does `PG_*_SHARE` first, then `PG*`, then hardcoded defaults, per field. Its roxygen says it "works identically to `frs_db_conn()`", which is no longer true.

Proposed: have `lnk_db_conn()` delegate to `fresh::frs_db_conn()`, or mirror its resolver. Bump the fresh minimum to 0.36.0.
