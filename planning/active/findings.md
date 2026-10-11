# Findings — docker/load.sh calls fwapg's db/create.sh, which fwapg removed (#253)

## Issue context

## Problem

`docker/load.sh` stage 1 runs `bash create.sh` in a copy of fwapg's `db/`, then loads `sql/FWA_SlopeAlongInterval.sql`, `sql/FWA_SegmentAlongInterval.sql` and `sql/FWA_StreamProfile.sql` from there (the workaround in #68). fwapg removed `db/create.sh` and `db/sql/` in smnorris/fwapg#193. Its `db/` now holds `schema.sql` (a pg_dump), `migrate.sh` and `create_migration.sh`, and the documented load is `psql $DATABASE_URL -f db/schema.sql && ./load.sh`. So a loader run against a current fwapg checkout (`FWAPG_DIR`, default `../../fwapg`) fails at stage 1 before it loads anything.

Found while planning NewGraphEnvironment/fwapg#9, which adds two tables to fwapg's `load.sh`. That work was verified without a full rebuild.

## Proposed solution

- [ ] Stage 1: replace `bash create.sh` with `$PSQL -f db/schema.sql` (run from the copy of fwapg)
- [ ] Drop the #68 workaround where `schema.sql` covers it: it defines `fwa_slopealonginterval` and `fwa_segmentalonginterval`; `FWA_StreamProfile` is not in it, so check whether fresh still calls it
- [ ] One full loader run on an empty volume to confirm


## Exploration (2026-10-11)

- fwapg `db/schema.sql` (pg_dump --schema-only, PG 16.9) creates schemas `fwapg, hydrosheds, postgisftw, psf, usgs, whse_basemapping`, extensions `fuzzystrmatch, intarray, ltree, postgis` (IF NOT EXISTS), and `fwa_slopealonginterval` / `fwa_segmentalonginterval` in both `whse_basemapping` and `postgisftw`. No `fwa_streamprofile`; no fresh code calls it.
- Old `create.sh` (fwapg `9d3bfa9^`) ran `ALTER DATABASE :db SET search_path TO public,whse_basemapping,usgs,hydrosheds`. Upstream moved that to `docker/db/search_path.sh` (initdb script in its own db image). fresh uses `imresamu/postgis:17-3.5-bullseye`, so without the loader setting it, unqualified `fwa_upstream(` calls in `R/frs_habitat_classify.R`, `R/frs_feature_index.R`, `R/frs_wsg_drainage.R` fail. Live M1 DB carries the setting.
- `schema.sql` uses plain `CREATE SCHEMA`: stage 1 is first-run only, as the README already says.
- No `db/migrations/`; fwapg's documented load does not call `migrate.sh`.
- smnorris/fwapg#189 fixed in `c19293d`, so #68 closes with this.
- Live `fwapg` DB on M1: 178 GB; `whse_basemapping` 39 GB, `fwapg` schema 1 GB. Colima disk 70 GB free.

## Errors Encountered

| Error | Resolution |
|-------|------------|

## Plan review (Plan agent, 2026-10-11), verified

- **Parity of objects:** old `create.sh` + `db/sql/*` against `schema.sql`: same functions and aggregates, same tables, 176 indexes on both sides, no views; new adds `fuzzystrmatch`. `FWA_StreamProfile.sql` was an ad hoc SELECT on one blue line key, not a function.
- **Why search_path, corrected:** fwapg's `load/*.sql` and `fixes.sql` qualify everything (grep found no unqualified `fwa_*(` call). The dependency is fwapg's function bodies: `fwa_downstreamtrace` calls `fwa_downstream(` (schema.sql ~2304), `fwa_watershedatmeasure` calls `FWA_SliceWatershedAtPoint(` (~3882), plus `fwa_slopealonginterval`, `fwa_networktrace`, `fwa_upstreamtrace`. A pg_dump keeps bodies verbatim with `check_function_bodies = false`. fresh also calls `fwa_upstream(` unqualified in more files than first listed (`R/frs_habitat.R`, `R/frs_classify.R` among them). Comment fixed in `92cb8e3`.
- **Stale checkout (confirmed):** local fwapg `newgraph` was `f9718cb`, 22 commits behind `origin/newgraph` `b010209`, whose `load.sh` adds a PG >= 15 guard and `load/pcic_fwa_crosswalk.sql` / `load/fwa_stream_networks_discharge_monthly.sql` (fwapg#9). Attempt 1 stopped; attempt 2 uses a worktree at `b010209` so the shared checkout another session reads is not moved.
- **Stage 4 (bcfishobs) is broken on its own:** `docker/load.sh` runs `make all`, and bcfishobs has had no Makefile since `ba52e62` (2024-10-17); confirmed no `Makefile` in the local clone. Out of scope; follow-up issue drafted.
- **Migrations:** none shipped; comment added for when they are.

## /code-check branch (2026-10-11)

| Round | Findings | Fixed | Accepted | Inside previous fix? |
|-------|----------|-------|----------|----------------------|
| 1 | 0 | 0 | 0 | — |
| 2 | 0 | 0 | 0 | n |
| 3 | 0 | 0 | 0 | n |

Ended on a clean round 3 with no inside-a-fix finding. Round 3 enumerated old `db/sql/*` against `schema.sql`: 41 / 41 tables, 44 / 44 functions and aggregates by signature, all 156 old indexes among 176, same six schemas. Round 2: a real first run starts with the image's database path (`"$user", public, topology, tiger`) and the loader replaces it, as `create.sh` did.

Pending, after the run (load.sh is mounted into the running loader and must not be edited mid-run): round 3 notes the migrations comment would mislead. `schema.sql` has no `fwapg.db_version`, so `migrate.sh` on a fresh install starts from 0 and would re-apply migrations the dump already holds. Reword the comment, then review that change.
