# Code review, round 1 (#253): docker/load.sh + docker/README.md

## Clean

No issues found.

Checked, and why each is fine:

- `db/schema.sql` (current fwapg, `b010209`) has no psql meta-commands (no `\restrict`), no GRANT/OWNER/ROLE
  statements, and only `CREATE EXTENSION IF NOT EXISTS`, so it loads with psql 17 into the postgis 17 image
  whether postgis is pre-installed (image's `fwapg` DB) or not (scratch DB from `CREATE DATABASE` off template1).
- It defines `fwa_slopealonginterval` / `fwa_segmentalonginterval` (whse_basemapping and postgisftw), so dropping
  the #68 workaround loses nothing. `FWA_StreamProfile.sql` was an ad hoc SELECT, not a function; nothing in
  fresh references it.
- The dump sets `search_path` to '' for its own session only and `check_function_bodies = false`, so the
  function bodies' unqualified calls are not resolved at load. `ALTER DATABASE ... SET search_path` runs right
  after, and every later `$PSQL` / ogr2ogr connection (stage 2 onward) is a new session that picks it up.
  The comment's examples (`fwa_downstreamtrace` -> `fwa_downstream(`, `fwa_watershedatmeasure` ->
  `FWA_SliceWatershedAtPoint(`) are unqualified in the dump, as stated.
- `current_database()` is a sturdier source of the name than the old `cut -d/ -f4` of `DATABASE_URL`
  (survives query params, and follows a scratch DATABASE_URL); the name is double-quoted in the ALTER.
- Same path list as upstream's own `docker/db/search_path.sh` (`public,whse_basemapping,usgs,hydrosheds`).
- "fwapg ships no db/migrations yet" holds on both smnorris/fwapg and NewGraphEnvironment/fwapg default
  branches (`db/` = README.md, create_migration.sh, migrate.sh, schema.sql), and schema.sql carries no
  `fwapg.db_version` table, so not running `migrate.sh` drops nothing today.
- New `schema.sql` presence guard sits after the `db/` guard, so each failure gets its own message;
  `cd "$WORK_DIR"` under `set -e` aborts on failure; stage 2 re-`cd`s to the same place, so the cwd change
  from `$WORK_DIR/db` to `$WORK_DIR` affects nothing.
- No other tracked file outside `planning/` still names `create.sh` or `db/sql/`.
