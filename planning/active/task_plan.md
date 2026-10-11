# Task: docker/load.sh calls fwapg's db/create.sh, which fwapg removed (#253)

`docker/load.sh` stage 1 runs `bash create.sh` in a copy of fwapg's `db/`, then loads `sql/FWA_SlopeAlongInterval.sql`, `sql/FWA_SegmentAlongInterval.sql` and `sql/FWA_StreamProfile.sql` from there (the workaround in #68). fwapg removed `db/create.sh` and `db/sql/` in smnorris/fwapg#193. Its `db/` now holds `schema.sql` (a pg_dump), `migrate.sh` and `create_migration.sh`, and the documented load is `psql $DATABASE_URL -f db/schema.sql && ./load.sh`. So a loader run against a current fwapg checkout fails at stage 1 before it loads anything.

**Not in the issue:** the old `create.sh` also set the database `search_path` to `public,whse_basemapping,usgs,hydrosheds`. A pg_dump does not carry database settings, so upstream moved it into its db image (`docker/db/search_path.sh`), which fresh does not use. fresh calls `fwa_upstream()` unqualified, so the loader must set it.

## Phase 1: Stage 1 on fwapg's schema.sql
- [x] Validate: require `$FWAPG_DIR/db/schema.sql`, with an error naming the layout (a checkout from before smnorris/fwapg#193 has `db/create.sh` instead; pull it)
- [x] Stage 1: replace `cd db && bash create.sh` with `$PSQL -f db/schema.sql`, run from the tempdir copy
- [x] Stage 1: set the database `search_path` to `public,whse_basemapping,usgs,hydrosheds` (DB name from `current_database()`), with a comment that upstream does this in `docker/db/search_path.sh` and that `pg_dump` does not carry it
- [x] Drop the #68 workaround (the three `sql/FWA_*.sql` loads)
- [x] `docker/README.md` "What's loaded" stage 1 row: fwapg `db/schema.sql` + search_path
- [x] `bash -n docker/load.sh`

## Phase 2: Verify on a scratch database (operator choice: scratch DB on M1)
- [ ] Stamp: fwapg commit (branch `newgraph`, plus `origin/main` SHA), fresh SHA, free disk before
- [ ] `CREATE DATABASE fwapg_253` in fresh-db, then run the loader against it with `DATABASE_URL` overridden. Detached, logged to `data-raw/logs/docker_load_253/`, watched against disk free
- [ ] Post-conditions in `fwapg_253`: `search_path` set; `fwa_slopealonginterval` / `fwa_segmentalonginterval` resolve unqualified; key `whse_basemapping` row counts against the live `fwapg`; `working.falls` / `working.crossings` loaded
- [ ] One fresh call against `fwapg_253` that uses an unqualified `fwa_upstream()`, compared with the same call on `fwapg`
- [ ] `DROP DATABASE fwapg_253`, and confirm the disk is back

## Phase 3: Wrap
- [ ] NEWS entry: left to `/gh-pr-merge` (fresh writes NEWS at release; `docker/` is `.Rbuildignore`d, so no package change). PR body carries `Fixes #253`, `Fixes #68`
- [ ] Run summary in `findings.md` and the archive README (measurement + evidence prefix)

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean (each commit, or once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
