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

## Verification run (attempt 2), 2026-10-11T23:35Z to 2026-10-12T05:27Z

- **Loader exit 0** in 5 h 52 min, into scratch DB `fwapg_253` from NewGraphEnvironment/fwapg `origin/newgraph` `b010209` (worktree). No error lines in `loader.log`; stage 1 set `search_path`, stage 3 loaded falls and crossings. Network-bound: per-WSG parquet over `/vsicurl/` at roughly 0.4 MB/s.
- **Disk:** 70 GB free before, 28 GB at the end (`fwapg_253` reached 40 GB), 68 GB after `DROP DATABASE`. The 10 GB guard never fired.
- **Post-conditions** (`postconditions.txt`):
  - database `search_path` identical to the live `fwapg`;
  - 14 key tables match the live DB exactly, except channel width (+12 rows of 4.9 M) and order parent (−1 of 1.5 M): drift from a months-old live load;
  - fwapg#9 tables `pcic_fwa_crosswalk` 48,716 and `fwa_stream_networks_discharge_monthly` 40,524,444, same as live;
  - `fwa_downstreamtrace(360873822, 166030)` 1,567 rows / 590,498 m on both; fresh's unqualified `fwa_upstream()` form 8,876 on both.
- **`whse_basemapping.fwa_watershedatmeasure()` fails on its non-lake path** in `fwapg_253`: `relation "exbc" does not exist`, at a Bulkley River point inside BC (live: 231,944.7 ha). Its `postgisftw` copy returns 231,944.7, and a lake point (360457111, 924.5) returns 11.5 ha on both DBs.
  - Cause: smnorris/fwapg `3c43bdd` (Xborder, 2026-01-15) deleted the `exbc` CTE from the non-lake branch and kept its `FROM exbc`. Still present at smnorris/fwapg `8b3904e` and NewGraphEnvironment/fwapg `9a64ce3`. The live DB was loaded before it. Evidence: `fwa_watershedatmeasure.diff`.
  - Not this change: `schema.sql` carries the function body verbatim. fresh's exported `frs_watershed_at_measure()` calls the broken copy, so a DB built with this loader from current fwapg has it broken.
  - Already tracked as NewGraphEnvironment/fwapg#1. That body said only cross-border points fail; corrected 2026-10-12 to "every non-lake call", with the measurements, and with the note that restoring the CTE as written stops the error but reads `hydrosheds` / `usgs` tables that `load.sh` no longer fills (0 rows even live).
- **Tests** (`devtools::test()` on the branch, default `fwapg`): 1487 pass, 0 fail, 3 skip.

## /code-check round 4 (2026-10-12): the post-run edits

Scope: the reworded migrations comment in `docker/load.sh`, and `postconditions.sh`'s non-fatal `probe()`.

| Round | Findings | Fixed | Accepted | Inside previous fix? |
|-------|----------|-------|----------|----------------------|
| 4 | 1 (fragile) | 1 | 0 | y |

- Comment claims verified by the reviewer against fwapg `origin/newgraph` `9a64ce3`: no `db/migrations/`; `migrate.sh` seeds `fwapg.db_version` with `'0'`; `schema.sql` never creates `db_version`.
- Finding: the first `probe()` printed nothing for a non-SQL failure or a zero-row result, so a probe could drop out of the evidence. Fixed: those print `NO RESULT:` and the first line of output.
- Ended by enumeration, not by another round: `probe()` has four output paths (row, SQL error, connection/docker failure, zero rows), each run against a stub (`select 'row', 1`; a missing table; a missing database; `where false`) and each printed one line. Paths 1 and 2 print what the earlier version printed, so the recorded `postconditions.txt` is unchanged by the fix.
