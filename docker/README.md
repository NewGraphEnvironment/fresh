# Local fwapg (Docker)

Local PostGIS instance with BC Freshwater Atlas data for running the fresh habitat pipeline without the remote DB. Everything runs in containers — no need for local ogr2ogr, psql, or bcdata.

## Prerequisites

- Docker Desktop
- Local clone of [smnorris/fwapg](https://github.com/smnorris/fwapg) (default: `../../fwapg` sibling directory)
- Optional: local clone of [smnorris/bcfishobs](https://github.com/smnorris/bcfishobs) for fish observation queries

## Quick start (first time — empty `postgres-data/`)

```bash
cd docker

# Start PostGIS
docker compose up -d db

# Load fwapg data + falls (runs in loader container)
# First run builds the loader image (~5 min), data load takes a while (~hours)
docker compose run --rm loader

# Optional: also load bcfishobs
docker compose run --rm loader --bcfishobs
```

## Restart after stop (data already loaded)

If `postgres-data/` is already populated from a previous run, **don't re-run the loader** — just start the DB:

```bash
cd docker
docker compose up -d db

# Wait a few seconds, then verify
docker exec fresh-db pg_isready -U postgres -d fwapg
docker exec fresh-db psql -U postgres -d fwapg -c "\dn"
```

The schema list should include `whse_basemapping`, `bcfishpass_ref`, `bcfishobs`, `fwapg`, `cabd`, `fresh`, `psf`, etc. If you only see `public` and the postgis system schemas, the loader hasn't been run — go back to "Quick start" above.

## Connect from QGIS

Data Source Manager → PostgreSQL → **New**:

| Field | Value |
|---|---|
| Name | `fresh-local` (or anything) |
| Host | `localhost` |
| Port | `5432` |
| Database | `fwapg` |
| Username | `postgres` |
| Password | `postgres` |
| SSL mode | `disable` |

Test Connection → Save. The fwapg schemas (`whse_basemapping.fwa_*`, `bcfishpass_ref.*`, `bcfishobs.*`, etc.) appear under the connection in the Browser panel.

## Directory layout

Default layout assumes sibling repos under a common parent:

```
repo/
  fresh/          # this package
  fwapg/          # smnorris/fwapg
  bcfishobs/      # smnorris/bcfishobs (optional)
```

Override with env vars if your layout differs:

```bash
FWAPG_DIR=/path/to/fwapg docker compose run --rm loader
```

## Connect from R

```r
conn <- DBI::dbConnect(
  RPostgres::Postgres(),
  host = "localhost", port = 5432,
  dbname = "fwapg", user = "postgres", password = "postgres"
)

# Run habitat pipeline — use working.falls instead of bcfishpass.falls_vw
frs_habitat(conn, "ADMS", falls = "working.falls")
```

## Ports

The database listens on 5432 unless `FRESH_DB_PORT` says otherwise (next section).

## A second instance

To build or try a database beside the one you use (a new image, a rebuild from current fwapg), give the second its own compose project, container names, port and data directory. The defaults are the first instance's, so a plain `docker compose` never touches the second:

```bash
cd docker
export FRESH_DB_CONTAINER=fresh-db-2 FRESH_LOADER_CONTAINER=fresh-loader-2 \
  FRESH_DB_PORT=5433 FRESH_DB_DATA=./postgres-data-2
docker compose -p fresh-2 up -d db
docker compose -p fresh-2 run --rm loader
```

Both share the machine's memory, so size the second with a `command:` override (`docker compose -p fresh-2 -f docker-compose.yml -f second.yml ...`; see `tuning.md`). `postgres-data*/` is gitignored.

## Image

`imresamu/postgis:17-3.5.3-bookworm`: PostgreSQL 17, PostGIS 3.5, GEOS 3.11, as upstream fwapg's own db image (PostGIS 3.5 on bookworm). Up to 2026-11 it was `17-3.5-bullseye`, whose GEOS 3.9.0 returns an empty intersection for a line lying wholly inside a box and simplifies a polygon differently from one call to the next (`data-raw/logs/docker_rebuild_324/image_probe.txt`). The data directory format did not change, so `up` over an existing bullseye directory starts, but on different GEOS answers and a new glibc collation version (text indexes need a `REINDEX`): move an existing database deliberately, not by a routine `up`.

## What's loaded

| Stage | Source | Contents |
|-------|--------|----------|
| 1 | fwapg `db/schema.sql`, then `db/migrate.sh` | Extensions (PostGIS, ltree), schemas, tables, SQL functions; the database `search_path` (`public,whse_basemapping,usgs,hydrosheds`), which `schema.sql` does not carry; then every migration in `db/migrations/` (function fixes made since the snapshot), recorded in `fwapg.db_version` |
| 2 | fwapg `load.sh` | Stream networks, lakes, wetlands, watersheds, channel width, discharge, precip lookups |
| 3 | `inst/extdata/falls.csv` | 3,294 barrier falls → `working.falls` table |
| 4 | bcfishobs (optional) | Fish observation events → `bcfishobs` schema |

## Managing data

```bash
# Stop container (data persists in postgres-data/)
docker compose down

# Stop and delete all data
docker compose down -v
rm -rf postgres-data

# Rebuild loader image after Dockerfile changes
docker compose build loader
```

## Updating falls data

Falls are shipped as `inst/extdata/falls.csv`, sourced from `bcfishpass.falls_vw` on the remote DB. To refresh:

```r
source("data-raw/bcfishpass_falls.R")
```

Requires a connection to a database holding `bcfishpass`. Commit the updated CSV.

## Container details

The loader image (`docker/Dockerfile`) includes:

- GDAL 3.12 (`ogr2ogr` for loading spatial data from BC object storage)
- PostgreSQL client 17 (`psql` for SQL execution)
- bcdata (Python, for BC Data Catalogue downloads)
- AWS CLI (for S3 cached lookups)

Same toolchain as fwapg and bcfishpass, portable across machines.
