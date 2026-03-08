# Get Stream Segments Downstream of a Network Position

Returns all FWA stream segments downstream of a given blue line key and
downstream route measure. Uses the fwapg `fwa_downstream()` ltree
comparison.

## Usage

``` r
frs_network_downstream(
  blue_line_key,
  downstream_route_measure,
  table = "whse_basemapping.fwa_stream_networks_sp",
  cols = c("linear_feature_id", "blue_line_key", "waterbody_key", "edge_type",
    "gnis_name", "stream_order", "stream_magnitude", "gradient",
    "downstream_route_measure", "upstream_route_measure", "length_metre",
    "watershed_group_code", "wscode_ltree", "localcode_ltree", "geom"),
  wscode_col = "wscode_ltree",
  localcode_col = "localcode_ltree",
  ...
)
```

## Arguments

- blue_line_key:

  Integer. Blue line key of the reference point.

- downstream_route_measure:

  Numeric. Downstream route measure of the reference point.

- table:

  Character. Fully qualified table name. Default
  `"whse_basemapping.fwa_stream_networks_sp"`.

- cols:

  Character vector of column names to select. Default includes the most
  commonly used FWA stream attributes.

- wscode_col:

  Character. Name of the watershed code ltree column. Default
  `"wscode_ltree"`. Use `"wscode"` for bcfishpass views.

- localcode_col:

  Character. Name of the local code ltree column. Default
  `"localcode_ltree"`. Use `"localcode"` for bcfishpass views.

- ...:

  Additional arguments passed to
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md).

## Value

An `sf` data frame of downstream stream segments.

## See also

Other traverse:
[`frs_network_upstream()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_upstream.md),
[`frs_waterbody_network()`](https://newgraphenvironment.github.io/fresh/reference/frs_waterbody_network.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Get all streams downstream of a point
downstream <- frs_network_downstream(
  blue_line_key = 360873822,
  downstream_route_measure = 166030
)
} # }
```
