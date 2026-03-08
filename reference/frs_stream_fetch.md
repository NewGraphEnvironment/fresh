# Fetch FWA Stream Network Segments

Retrieve stream segments from a stream network table. Filter by
watershed group code, blue line key, and/or bounding box.

## Usage

``` r
frs_stream_fetch(
  watershed_group_code = NULL,
  blue_line_key = NULL,
  bbox = NULL,
  stream_order_min = NULL,
  table = "whse_basemapping.fwa_stream_networks_sp",
  cols = c("linear_feature_id", "blue_line_key", "waterbody_key", "edge_type",
    "gnis_name", "stream_order", "stream_magnitude", "gradient",
    "downstream_route_measure", "upstream_route_measure", "length_metre",
    "watershed_group_code", "wscode_ltree", "localcode_ltree", "geom"),
  limit = NULL,
  ...
)
```

## Arguments

- watershed_group_code:

  Character. Watershed group code (e.g. `"BULK"`). Default `NULL`.

- blue_line_key:

  Integer. Blue line key for a specific stream. Default `NULL`.

- bbox:

  Numeric vector of length 4 (`xmin`, `ymin`, `xmax`, `ymax`) in BC
  Albers (EPSG:3005). Default `NULL`.

- stream_order_min:

  Integer. Minimum Strahler stream order to return. Default `NULL` (all
  orders).

- table:

  Character. Fully qualified table name. Default
  `"whse_basemapping.fwa_stream_networks_sp"`.

- cols:

  Character vector of column names to select. Default includes the most
  commonly used FWA stream attributes.

- limit:

  Integer. Maximum rows to return. Default `NULL` (no limit).

- ...:

  Additional arguments passed to
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md).

## Value

An `sf` data frame of stream segments.

## See also

Other fetch:
[`frs_lake_fetch()`](https://newgraphenvironment.github.io/fresh/reference/frs_lake_fetch.md),
[`frs_wetland_fetch()`](https://newgraphenvironment.github.io/fresh/reference/frs_wetland_fetch.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# All streams in the Bulkley watershed group
streams <- frs_stream_fetch(watershed_group_code = "BULK")

# Streams with order >= 4
streams <- frs_stream_fetch(watershed_group_code = "BULK", stream_order_min = 4)

# Custom columns and table
streams <- frs_stream_fetch(
  watershed_group_code = "BULK",
  cols = c("blue_line_key", "gnis_name", "stream_order", "geom")
)
} # }
```
