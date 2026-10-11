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
