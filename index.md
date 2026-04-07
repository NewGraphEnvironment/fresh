# fresh

> FWA-Referenced Spatial Hydrology

Stream network-aware spatial operations via direct SQL against
[fwapg](https://github.com/smnorris/fwapg). Segment networks, classify
habitat, aggregate upstream features, and query the BC Freshwater Atlas.

## Installation

``` r
pak::pak("NewGraphEnvironment/fresh")
```

## Prerequisites

PostgreSQL with [fwapg](https://github.com/smnorris/fwapg) loaded. A
local Docker setup is included:

``` bash
cd docker
docker compose up -d db
docker compose run --rm loader
```

See `docker/README.md` for details. Connection via
[`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)
or direct
[`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).

## Example

Segment a stream network at gradient barriers and classify habitat for
multiple species:

``` r
library(fresh)

conn <- DBI::dbConnect(RPostgres::Postgres(),
  host = "localhost", port = 5432,
  dbname = "fwapg", user = "postgres", password = "postgres")

# 1. Generate gradient access barriers
frs_break_find(conn, "working.tmp",
  attribute = "gradient", threshold = 0.15,
  to = "working.barriers_15")

# 2. Segment network at barriers + falls
frs_network_segment(conn, aoi = "BULK",
  to = "fresh.streams",
  break_sources = list(
    list(table = "working.barriers_15", label = "gradient_15"),
    list(table = "working.falls", label = "blocked")))

# 3. Classify habitat per species
frs_habitat_classify(conn,
  table = "fresh.streams",
  to = "fresh.streams_habitat",
  species = c("CO", "BT", "ST"))
```

Or use the orchestrator for multi-WSG runs:

``` r
frs_habitat(conn, c("BULK", "MORR", "ZYMO"),
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat",
  workers = 4, password = "postgres",
  break_sources = list(
    list(table = "working.falls", label = "blocked")))
```

See the [pkgdown site](https://newgraphenvironment.github.io/fresh/) for
vignettes and function reference.

## Ecosystem

| Package                                                   | Role                                                                      |
|-----------------------------------------------------------|---------------------------------------------------------------------------|
| **fresh**                                                 | Network segmentation + habitat classification (this package)              |
| [link](https://github.com/NewGraphEnvironment/link)       | Crossing connectivity interpretation — scoring, overrides, prioritization |
| [breaks](https://github.com/NewGraphEnvironment/breaks)   | Delineate sub-basins from break points on stream networks                 |
| [flooded](https://github.com/NewGraphEnvironment/flooded) | Delineate floodplain extents from DEMs and stream networks                |
| [drift](https://github.com/NewGraphEnvironment/drift)     | Track land cover change within floodplains over time                      |

Pipeline: fresh (network data) → breaks (sub-basins) → flooded
(floodplains) → drift (land cover change)

## License

MIT
