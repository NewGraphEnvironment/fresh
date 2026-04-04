# Local fwapg (Docker)

Local PostGIS instance with BC Freshwater Atlas data for running the fresh habitat pipeline without the remote DB. Everything runs in containers — no need for local ogr2ogr, psql, or bcdata.

## Prerequisites

- Docker Desktop
- Local clone of [smnorris/fwapg](https://github.com/smnorris/fwapg) (default: `../../fwapg` sibling directory)
- Optional: local clone of [smnorris/bcfishobs](https://github.com/smnorris/bcfishobs) for fish observation queries

## Quick start

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

| Port | Service |
|------|---------|
| 5432 | Local Docker fwapg |
| 63333 | SSH tunnel to remote fwapg (existing) |

## What's loaded

| Stage | Source | Contents |
|-------|--------|----------|
| 1 | fwapg `db/create.sh` | Extensions (PostGIS, ltree), schemas, 23 SQL functions |
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

Requires SSH tunnel on port 63333. Commit the updated CSV.

## Container details

The loader image (`docker/Dockerfile`) includes:

- GDAL 3.12 (`ogr2ogr` for loading spatial data from BC object storage)
- PostgreSQL client 17 (`psql` for SQL execution)
- bcdata (Python, for BC Data Catalogue downloads)
- AWS CLI (for S3 cached lookups)

Same toolchain as fwapg and bcfishpass — portable across dev machines and ready for awshak deployment.
