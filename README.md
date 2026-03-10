# fresh <img src="man/figures/logo.png" align="right" height="139" alt="fresh hex sticker" />

> FWA-Referenced Spatial Hydrology

Stream network-aware spatial operations via direct SQL against [fwapg](https://github.com/smnorris/fwapg) and [bcfishpass](https://github.com/smnorris/bcfishpass). Snap points to streams, delineate watersheds, query fish observations, and fetch network-referenced features from the BC Freshwater Atlas.

## Installation

```r
pak::pak("NewGraphEnvironment/fresh")
```

## Prerequisites

`fresh` requires PostgreSQL with the following extensions loaded:

- [fwapg](https://github.com/smnorris/fwapg) — BC Freshwater Atlas in PostgreSQL
- [bcfishpass](https://github.com/smnorris/bcfishpass) — fish passage and habitat modelling
- [bcfishobs](https://github.com/smnorris/bcfishobs) — fish observation data

Connection is configured via `PG_*_SHARE` environment variables
(`PG_HOST_SHARE`, `PG_PORT_SHARE`, `PG_DB_SHARE`, `PG_USER_SHARE`) or
passed directly to `frs_db_conn()`.

## Example

Query all network features between two points on the same blue line key
using watershed code subtraction — no spatial clipping needed:

```r
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

See the [subbasin vignette](https://newgraphenvironment.github.io/fresh/articles/subbasin-query.html)
for a full worked example with map output.

## Ecosystem

fresh is one piece of a larger watershed analysis workflow:

| Package | Role |
|---------|------|
| **fresh** | FWA-referenced spatial hydrology (this package) |
| [breaks](https://github.com/NewGraphEnvironment/breaks) | Delineate sub-basins from break points on stream networks |
| [flooded](https://github.com/NewGraphEnvironment/flooded) | Delineate floodplain extents from DEMs and stream networks |
| [drift](https://github.com/NewGraphEnvironment/drift) | Track land cover change within floodplains over time |
| [fly](https://github.com/NewGraphEnvironment/fly) | Estimate airphoto footprints and select optimal coverage for a study area |
| [diggs](https://github.com/NewGraphEnvironment/diggs) | Interactive explorer for [fly](https://github.com/NewGraphEnvironment/fly) airphoto selections (Shiny app) |

Pipeline: fresh (network data) &rarr; breaks (sub-basins) &rarr; flooded (floodplains) &rarr; drift (land cover change)

## License

MIT
