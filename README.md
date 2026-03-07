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

Connect via SSH tunnel to a remote instance or run locally. See the [db-newgraph skill](https://github.com/NewGraphEnvironment/soul) for connection patterns.

## Ecosystem

`fresh` is the data layer in a family of packages:

- **fresh** — fetch and query FWA network data (this package)
- **[flooded](https://github.com/NewGraphEnvironment/flooded)** — floodplain delineation from DEM and stream network
- **[drift](https://github.com/NewGraphEnvironment/drift)** — land cover change detection within floodplains
- **[fly](https://github.com/NewGraphEnvironment/fly)** — interactive mapping and layer toggle
- **[diggs](https://github.com/NewGraphEnvironment/diggs)** — Shiny app front-end

Pipeline: `fresh` (network data) → `flooded` (delineate) → `drift` (classify) → `fly` (map) → `diggs` (Shiny UI)

## License

MIT
