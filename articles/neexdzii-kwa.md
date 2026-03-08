# Neexdzii Kwa Stream Network

This vignette demonstrates `fresh` on a real watershed analysis task:
extracting the coho rearing/spawning stream network upstream of the
Neexdzii Kwa (Upper Bulkley River) / Wedzin Kwa confluence, with lakes
and wetlands. This is the same scoping used in the
[restoration_wedzin_kwa_2024](https://github.com/NewGraphEnvironment/restoration_wedzin_kwa_2024)
land cover change analysis. Stream colours come from the
[gq](https://github.com/NewGraphEnvironment/gq) style registry.

## Coho rearing network

Query `bcfishpass.streams_co_vw` — the coho-specific habitat model view
— for rearing/spawning streams (order 4+) upstream of the Neexdzii Kwa /
Wedzin Kwa confluence. The `table`, `cols`, `wscode_col`, and
`localcode_col` parameters let us target this view directly with
[`frs_network_prune()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_prune.md).

``` r
library(fresh)
library(sf)
#> Linking to GEOS 3.13.0, GDAL 3.8.5, PROJ 9.5.1; sf_use_s2() is TRUE

# Neexdzii Kwa / Wedzin Kwa confluence on Bulkley mainstem
blk <- 360873822
drm <- 166030.4

co_habitat <- frs_network_prune(
  blue_line_key = blk,
  downstream_route_measure = drm,
  stream_order_min = 4,
  watershed_group_code = "BULK",
  extra_where = "(s.rearing > 0 OR s.spawning > 0)",
  table = "bcfishpass.streams_co_vw",
  cols = c("segmented_stream_id", "blue_line_key", "waterbody_key",
           "gnis_name", "stream_order", "channel_width", "mapping_code",
           "rearing", "spawning", "access", "geom"),
  wscode_col = "wscode",
  localcode_col = "localcode"
)

nrow(co_habitat)
#> [1] 1027
sort(unique(co_habitat$stream_order))
#> [1] 4 5 6
table(co_habitat$mapping_code)
#> 
#>  REAR;ASSESSED  REAR;MODELLED      REAR;NONE SPAWN;ASSESSED SPAWN;MODELLED 
#>             28              9            147            103              7 
#>     SPAWN;NONE 
#>            733
```

## Lakes and wetlands

Lake and wetland polygon tables (`fwa_lakes_poly`, `fwa_wetlands_poly`)
have NULL `localcode_ltree`, so `fwa_upstream()` can’t query them
directly. The bridge is `waterbody_key` — stream segments flowing
through waterbodies carry the same key. We run `fwa_upstream()` on the
stream network (which has `localcode_ltree`), extract distinct
`waterbody_key` values, then join to the polygon tables. See
[fresh#8](https://github.com/NewGraphEnvironment/fresh/issues/8).

``` r
# Upstream waterbody_key bridge: fwa_upstream() on streams → join to polygons
wb_sql <- sprintf(paste0(
  "WITH ref AS (\n",
  "  SELECT wscode_ltree, localcode_ltree\n",
  "  FROM whse_basemapping.fwa_stream_networks_sp\n",
  "  WHERE blue_line_key = %s\n",
  "    AND downstream_route_measure <= %s\n",
  "  ORDER BY downstream_route_measure DESC\n",
  "  LIMIT 1\n",
  "),\n",
  "upstream_wbkeys AS (\n",
  "  SELECT DISTINCT s.waterbody_key\n",
  "  FROM whse_basemapping.fwa_stream_networks_sp s, ref\n",
  "  WHERE whse_basemapping.fwa_upstream(\n",
  "    ref.wscode_ltree, ref.localcode_ltree,\n",
  "    s.wscode_ltree, s.localcode_ltree\n",
  "  )\n",
  "  AND s.waterbody_key IS NOT NULL\n",
  ")\n"
), blk, drm)

lakes <- frs_db_query(paste0(
  wb_sql,
  "SELECT l.waterbody_key, l.gnis_name_1, l.area_ha, l.geom\n",
  "FROM whse_basemapping.fwa_lakes_poly l\n",
  "JOIN upstream_wbkeys u ON l.waterbody_key = u.waterbody_key"
))

wetlands <- frs_db_query(paste0(
  wb_sql,
  "SELECT w.waterbody_key, w.gnis_name_1, w.area_ha, w.geom\n",
  "FROM whse_basemapping.fwa_wetlands_poly w\n",
  "JOIN upstream_wbkeys u ON w.waterbody_key = u.waterbody_key"
))

nrow(lakes)
#> [1] 363
nrow(wetlands)
#> [1] 1293
if (nrow(lakes) > 0) head(lakes[order(-lakes$area_ha), c("gnis_name_1", "area_ha")], 10)
#> Simple feature collection with 10 features and 2 fields
#> Geometry type: MULTIPOLYGON
#> Dimension:     XY
#> Bounding box:  xmin: 955155.1 ymin: 1018170 xmax: 995940.4 ymax: 1065884
#> Projected CRS: NAD83 / BC Albers
#>       gnis_name_1   area_ha                           geom
#> 10     Maxan Lake 654.20608 MULTIPOLYGON (((993644.5 10...
#> 11       Day Lake 316.79508 MULTIPOLYGON (((981685.4 10...
#> 12     Elwin Lake 287.88098 MULTIPOLYGON (((980130.3 10...
#> 13    Goosly Lake 239.17266 MULTIPOLYGON (((975714 1020...
#> 14   Bulkley Lake 233.40513 MULTIPOLYGON (((993264.4 10...
#> 15 McQuarrie Lake 230.06659 MULTIPOLYGON (((956158.2 10...
#> 16     Swans Lake 179.93733 MULTIPOLYGON (((977344.9 10...
#> 17       Nez Lake 174.64798 MULTIPOLYGON (((991369.5 10...
#> 18    Sunset Lake 130.58687 MULTIPOLYGON (((975322.1 10...
#> 20    Conrad Lake  63.40472 MULTIPOLYGON (((994679.2 10...
```

## Map with gq colours

Colour streams by `mapping_code` using the
[gq](https://github.com/NewGraphEnvironment/gq) style registry — no
hardcoded hex values.

``` r
reg <- gq::gq_reg_main()
cls <- gq::gq_tmap_classes(reg$layers$streams_salmon)

# Match mapping_code to gq colours
co_habitat$col <- cls$values[co_habitat$mapping_code]
co_habitat$col[is.na(co_habitat$col)] <- "#999999"

# Line width: spawning thicker than rearing (gq convention)
co_habitat$lwd <- ifelse(co_habitat$spawning > 0, 1.7, 1.0)

# Lake and wetland styles from registry
lake_style <- gq::gq_tmap_style(reg$layers$lake)
wetland_style <- gq::gq_tmap_style(reg$layers$wetland)

plot(
  st_geometry(co_habitat),
  col = co_habitat$col,
  lwd = co_habitat$lwd,
  main = ""
)

if (nrow(lakes) > 0) {
  plot(
    st_geometry(lakes),
    col = lake_style$fill,
    border = lake_style$col,
    add = TRUE
  )
}

if (nrow(wetlands) > 0) {
  plot(
    st_geometry(wetlands),
    col = wetland_style$fill,
    border = wetland_style$col,
    add = TRUE
  )
}

# Legend from gq registry — show only codes present in the data
present <- names(cls$values) %in% unique(co_habitat$mapping_code)
legend(
  "topright",
  legend = c(cls$labels[present], "Lake", "Wetland"),
  col = c(cls$values[present], lake_style$col, wetland_style$col),
  pch = c(rep(NA, sum(present)), 15, 15),
  lwd = c(rep(2, sum(present)), NA, NA),
  pt.cex = c(rep(NA, sum(present)), 1.5, 1.5),
  cex = 0.7,
  bg = "white"
)
```

![Coho rearing and spawning habitat upstream of the Neexdzii Kwa
confluence (order 4+), with lakes and wetlands. Stream colours from the
gq style registry.](figure/plot-co-habitat-1.png)

Coho rearing and spawning habitat upstream of the Neexdzii Kwa
confluence (order 4+), with lakes and wetlands. Stream colours from the
gq style registry.

The network contains 1027 coho habitat segments across orders 4, 5, 6,
with 363 lakes and 1293 wetlands.

Named streams: Ailport Creek, Aitken Creek, Barren Creek, Buck Creek,
Bulkley River, Byman Creek, Cesford Creek, Crow Creek, Dungate Creek,
Foxy Creek, Johnny David Creek, Klo Creek, Maxan Creek, McKilligan
Creek, McQuarrie Creek, North Ailport Creek, Perow Creek, Raspberry
Creek, Richfield Creek, Robert Hatch Creek.

## Summary

| Step     | Function                                                                                                                                                                                                                                                                                              | What it does                        |
|----------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------|
| Snap     | [`frs_point_snap()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_snap.md)                                                                                                                                                                                                         | Index a point to the nearest stream |
| Fetch    | [`frs_stream_fetch()`](https://newgraphenvironment.github.io/fresh/reference/frs_stream_fetch.md), [`frs_lake_fetch()`](https://newgraphenvironment.github.io/fresh/reference/frs_lake_fetch.md), [`frs_wetland_fetch()`](https://newgraphenvironment.github.io/fresh/reference/frs_wetland_fetch.md) | Retrieve FWA features               |
| Traverse | [`frs_network_upstream()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_upstream.md), [`frs_network_downstream()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_downstream.md)                                                                              | Walk the network                    |
| Prune    | [`frs_network_prune()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_prune.md), [`frs_order_filter()`](https://newgraphenvironment.github.io/fresh/reference/frs_order_filter.md)                                                                                                | Filter by order, gradient           |
| Fish     | [`frs_fish_obs()`](https://newgraphenvironment.github.io/fresh/reference/frs_fish_obs.md), [`frs_fish_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_fish_habitat.md)                                                                                                          | Observations and habitat model      |

All functions accept `table` and `cols` parameters. Traverse functions
also accept `wscode_col` and `localcode_col` to work with any table that
has ltree watershed codes (e.g. `bcfishpass.streams_co_vw` uses
`wscode`/`localcode` instead of `wscode_ltree`/`localcode_ltree`).
