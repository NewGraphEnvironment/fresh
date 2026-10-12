# Code review, round 3 (#253): docker/load.sh stage 1 on fwapg db/schema.sql

Angle: list every observable effect of the old stage 1 and check each against the new one.
Old stage 1 = `9d3bfa9^:db/create.sh`, plus fresh's three extra `sql/FWA_*.sql` loads, plus
`cd "$WORK_DIR/db"`. New = `db/schema.sql` (identical in the mounted checkout `fwapg@f9718cb`
and in `fwapg_253_wt@b010209`), then `ALTER DATABASE ... SET search_path`.

## Clean

No issues found.

## What the old stage 1 did, and whether the new one does it

| Old effect | New stage 1 | Verdict |
|---|---|---|
| `set -x` tracing, from inside create.sh | none | Log noise only |
| Extensions postgis, ltree, intarray (`IF NOT EXISTS`, schema public) | same three, plus `fuzzystrmatch` (`IF NOT EXISTS`; the postgis image already installs it) | Reproduced |
| Schemas fwapg (plain `create schema`, so the old path was first-run only too), whse_basemapping, usgs, psf, hydrosheds, postgisftw | same six, all plain `CREATE SCHEMA` | Reproduced; first-run only either way |
| Tables | 41 names parsed from each side, identical set | Reproduced |
| `serial` columns (4) | 4 sequences, `OWNED BY` and `SET DEFAULT nextval` | Reproduced |
| Generated `wscode_ltree` / `localcode_ltree` columns | same expressions, schema-qualified | Reproduced |
| Indexes | 156 old index/table pairs, all present in the new 176 (the one apparent miss, `fwa_watershed_groups_watershed_group_code_idx`, is at schema.sql:6835 and my regex missed it) | Superset |
| Functions and aggregates (old 23 files loaded, `FWA_StreamsAsMVT` never) | 44 vs 44 after normalising name, schema and IN argument types; only the old-syntax `last(basetype=anyelement)` against `last(anyelement)` differs, and those are the same aggregate | Reproduced |
| Duplicate loads of SlopeAlongInterval, SegmentAlongInterval, StreamProfile | already in schema.sql | Loss harmless (they were `CREATE OR REPLACE` no-ops) |
| `COMMENT ON` for functions and tables | pg_dump carries comments | Metadata only |
| `set search_path to public` in CDB_MakeHexagon.sql and ST_Safe_Repair.sql | none | Session-level, so it never persisted; functions still land in `public` |
| `ALTER DATABASE <name from cut -d/ -f4 of URL> SET search_path TO public,whse_basemapping,usgs,hydrosheds` | the same value, with the name taken from `current_database()` and quoted | Reproduced; sturdier, since `cut` broke on a URL carrying `?params` |
| Function-level `SET` / `SECURITY DEFINER` | none on either side | n/a |
| cwd `$WORK_DIR/db` left behind | stage 2 does `cd "$WORK_DIR"` on its own | Loss harmless |

The new path sets search_path *after* creating the functions, and the old path set it *before*.
That makes no difference: schema.sql sets `check_function_bodies = false`, the bodies resolve
names at call time, and every later psql and ogr2ogr session (stage 2 onward, and R) is a new
session that picks up the database setting.

## Stage 2 interaction

- `load/*.sql`, `fixes/fixes.sql` and `load.sh` at f9718cb have no unguarded
  `CREATE TABLE`, `CREATE INDEX`, `CREATE FUNCTION` or `CREATE SCHEMA` that would collide
  with an object schema.sql now creates up front.
- The only DDL there is two `DROP TABLE`s on temp/staging tables that the scripts create
  themselves.
- This is also upstream's own order (`docker/db/Dockerfile`: schema.sql, then search_path).

## fresh's references (R/, data-raw/, tests/)

- Every `fwa_*` / `st_safe*` / `cdb*` / `hydroshed*` function fresh calls exists in schema.sql.
- These schema-qualified names have no definition in schema.sql:
  - `whse_basemapping.fwa_streams_vw` (roxygen examples in frs_aggregate.R and frs_classify.R);
  - `gba_railway_tracks_sp` and `transport_line` (data-raw example);
  - a `whse_basemapping.fwa_` string prefix.
- None of them was created by the old path either. `fwa_streams_vw` was dropped upstream in fwapg #175.
- So the diff loses nothing that fresh uses.

## Checked and not a finding

- The comment's claims hold:
  - schema.sql's `fwa_downstreamtrace` calls `fwa_downstream(` unqualified;
  - `fwa_watershedatmeasure` calls `FWA_SliceWatershedAtPoint(` unqualified;
  - fresh calls `fwa_upstream(` unqualified (frs_habitat_classify.R:253, 468).
- The guard at load.sh:29 tests the file stage 1 actually consumes, so it is the property,
  not a proxy. The old layout had `db/sql/schema.sql`, not `db/schema.sql`, so the guard
  separates the two layouts.
- The dump comes from pg_dump 16.13 and carries no `\restrict` lines. The loader installs
  pgdg `postgresql-client-17` (current 17.x), which would accept them anyway if a future
  regeneration added them.
- The search_path value now lives in three places: fwapg's `docker/db/search_path.sh`,
  fresh's load.sh and fresh's README. That is a copy, not a derivation, so it can drift if
  upstream adds a schema. The old create.sh had the same copy. Fragility only; no failure today.
- schema.sql has no `fwapg.db_version` table. When upstream adds migrations, the future
  `db/migrate.sh` step that the comment proposes would bootstrap at `'0'` and replay every
  migration on top of a schema.sql that may already contain them. That is upstream design
  and a comment, not code in this diff.
