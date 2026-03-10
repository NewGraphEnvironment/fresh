# Clip Spatial Features to an AOI Polygon

Clips an `sf` data frame to an area of interest polygon using
[`sf::st_intersection()`](https://r-spatial.github.io/sf/reference/geos_binary_ops.html).
Handles geometry type cleanup automatically — mixed geometry collections
from intersection are filtered to the original geometry type (e.g.
polygon, linestring).

## Usage

``` r
frs_clip(x, aoi)
```

## Arguments

- x:

  An `sf` data frame to clip.

- aoi:

  An `sf` or `sfc` polygon to clip to.

## Value

An `sf` data frame clipped to `aoi`, with geometry type matching the
input. Returns an empty `sf` with the same columns if no features
intersect.

## Details

Typical use: clip network query results (lakes, wetlands, streams) to a
watershed polygon from
[`frs_watershed_at_measure()`](https://newgraphenvironment.github.io/fresh/reference/frs_watershed_at_measure.md).

## Examples

``` r
if (FALSE) { # \dontrun{
# Clip wetlands to a subbasin watershed
aoi <- frs_watershed_at_measure(blk, drm, upstream_measure = urm)
wetlands <- frs_network(blk, drm, tables = list(
  wetlands = "whse_basemapping.fwa_wetlands_poly"
))
wetlands_clipped <- frs_clip(wetlands, aoi)
} # }
```
