# Code check round 2: docker/load.sh + docker/README.md (#253)

## Clean

No issues found.

## What was checked

- **Real first run vs the scratch DB.** schema.sql uses `CREATE EXTENSION IF NOT EXISTS` for
  postgis / fuzzystrmatch / intarray / ltree, so the extensions initdb already installed are
  skipped. Its schemas (fwapg, hydrosheds, postgisftw, psf, usgs, whse_basemapping) do not
  collide with initdb's topology / tiger / tiger_data. Every table fwapg load.sh truncates
  exists in schema.sql. No `\i` or other meta-commands, so moving `cd` from `$WORK_DIR/db` to
  `$WORK_DIR` changes nothing. Stage 2 cds to `$WORK_DIR` itself; stage 3 uses absolute
  paths; stage 4 cds elsewhere.
- **`ALTER DATABASE "$DB_NAME"`.** `current_database()` is the database `$DATABASE_URL` names,
  which is also the one schema.sql went into and the one fwapg load.sh connects to. `-AtX`
  gives a bare name. A failed substitution aborts under `set -e`. The new form is safer than
  create.sh's `cut -d / -f 4`, which would have kept a `?query` suffix. Each later psql or
  ogr2ogr call opens a new session, so the setting reaches stage 2.
- **Quoting.** `$PSQL` stays unquoted, as on every other line before this change. The URL
  has no spaces.
- **search_path value.** It matches create.sh and fwapg's `docker/db/search_path.sh`.
- **README row.** Accurate.
- **migrate.sh comment.** Accurate: `db/migrate.sh` exists, and `db/migrations/` does not.

## One correction to the brief (not a defect)

The brief says this image "sets nothing on search_path". That is not right. The image's
`initdb-postgis.sh` creates `postgis_topology` and then `postgis_tiger_geocoder` in
`$POSTGRES_DB`. PostGIS 3.5 runs `topology.AddToSearchPath('topology')` and
`tiger.SetSearchPathForInstall('tiger')`, both of which `ALTER DATABASE <db> SET search_path`.
The `\c` in that initdb script exists for this reason (docker-postgis#288). So on a real
first run, `fwapg` already carries a database-level `search_path` of roughly
`"$user", public, topology, tiger`.

The loader's `ALTER DATABASE` replaces that value with `public,whse_basemapping,usgs,hydrosheds`.
The setting is `setrole = 0`, and no role-level setting shadows it, so it takes effect.
Unqualified topology and tiger names drop off the path. The old create.sh did exactly the same,
so behaviour is unchanged, and nothing in fresh or fwapg calls those functions unqualified.
The scratch-DB check and a real first run reach the same final search_path.
