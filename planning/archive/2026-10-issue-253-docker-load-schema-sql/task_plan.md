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
- [x] Stamp: fwapg commit, fresh SHA, free disk before (`data-raw/logs/docker_load_253/stamp.txt`). Attempt 1 ran on a stale local fwapg (`f9718cb`, 22 behind `origin/newgraph`), passed stage 1 and was stopped; attempt 2 runs on a worktree at `origin/newgraph` `b010209`, which carries the fwapg#9 `load.sh` additions
- [x] `CREATE DATABASE fwapg_253` in fresh-db, then run the loader against it with `DATABASE_URL` overridden. Detached, logged to `data-raw/logs/docker_load_253/`, watched against disk free. Deviation from the issue: a template1 database, not an empty volume (the image's initdb extensions are absent; schema.sql uses `CREATE EXTENSION IF NOT EXISTS`, so the empty-volume path only skips those)
- [x] Post-conditions in `fwapg_253` ran (`postconditions.txt`): `search_path` set; 14 key tables match the live `fwapg` row for row, except channel width +12 rows and order parent -1; the fwapg#9 tables are populated (48,716 and 40,524,444 rows); `working.falls` 3,294 and `working.crossings` 533,291; `fwa_downstreamtrace()` matches (1,567 rows, 590,498 m). **`whse_basemapping.fwa_watershedatmeasure()` fails on its non-lake path** (`relation "exbc" does not exist`): an upstream defect in fwapg's source since smnorris/fwapg `3c43bdd`, not this change, tracked in NewGraphEnvironment/fwapg#1. Its `postgisftw` copy and its lake path return the live values
- [x] fresh's unqualified `fwa_upstream()` form, as SQL in `postconditions.sh` (the form `R/frs_classify.R` writes), on `fwapg_253` and `fwapg`: 8876 on both. Not an R call
- [x] `DROP DATABASE fwapg_253`, and confirm the disk is back (68 GB free; fwapg worktree removed)

## Phase 3: Wrap
- [ ] NEWS entry: left to `/gh-pr-merge` (fresh writes NEWS at release; `docker/` is `.Rbuildignore`d, so no package change). PR body carries `Fixes #253`, `Fixes #68`
- [x] Run summary in `findings.md` (archive README with measurement + evidence prefix at `/planning-archive`)

## Validation

- [x] Tests pass: 1487 pass, 0 fail, 3 skip (against the default `fwapg`, so they check nothing broke; the scratch-DB checks are the verification of this change)
- [x] `/code-check` clean: `/code-check branch` rounds 1-3 Clean; round 4 on the post-run edits found one fragile `probe()` case, fixed, ended by enumeration (`findings.md`)
- [x] PWF checkboxes match landed work
- [x] `/planning-archive` on completion
