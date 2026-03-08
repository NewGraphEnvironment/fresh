# fresh

> FWA-Referenced Spatial Hydrology

Stream network-aware spatial operations via direct SQL against
[fwapg](https://github.com/smnorris/fwapg) and
[bcfishpass](https://github.com/smnorris/bcfishpass). Snap points to
streams, delineate watersheds, query fish observations, and fetch
network-referenced features from the BC Freshwater Atlas.

## Installation

``` r
pak::pak("NewGraphEnvironment/fresh")
```

## Prerequisites

`fresh` requires PostgreSQL with the following extensions loaded:

- [fwapg](https://github.com/smnorris/fwapg) — BC Freshwater Atlas in
  PostgreSQL
- [bcfishpass](https://github.com/smnorris/bcfishpass) — fish passage
  and habitat modelling
- [bcfishobs](https://github.com/smnorris/bcfishobs) — fish observation
  data

Connection is configured via `PG_*_SHARE` environment variables
(`PG_HOST_SHARE`, `PG_PORT_SHARE`, `PG_DB_SHARE`, `PG_USER_SHARE`) or
passed directly to
[`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md).

## Example

Query all network features between two points on the same blue line key
using watershed code subtraction — no spatial clipping needed:

``` r
library(fresh)

result <- frs_network(
  blue_line_key = 360873822,
  downstream_route_measure = 208877,
  upstream_measure = 233564,
  tables = list(
    streams = "whse_basemapping.fwa_stream_networks_sp",
    lakes   = "whse_basemapping.fwa_lakes_poly",
    fish_obs = "bcfishobs.fiss_fish_obsrvtn_events_vw",
    falls   = "bcfishpass.falls_vw"
  )
)
```

See the [subbasin
vignette](https://newgraphenvironment.github.io/fresh/articles/subbasin-query.html)
for a full worked example with map output.

## Ecosystem

`fresh` is the data layer in a family of packages:

- **fresh** — fetch and query FWA network data (this package)
- **[flooded](https://github.com/NewGraphEnvironment/flooded)** —
  floodplain delineation from DEM and stream network
- **[drift](https://github.com/NewGraphEnvironment/drift)** — land cover
  change detection within floodplains
- **[fly](https://github.com/NewGraphEnvironment/fly)** — airphoto
  footprint estimation and coverage selection
- **[diggs](https://github.com/NewGraphEnvironment/diggs)** — BC
  Historic Airphoto Explorer (interactive Shiny app)

Pipeline: `fresh` (network data) → `flooded` (delineate) → `drift`
(classify)

## License

MIT
