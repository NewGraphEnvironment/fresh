# Get Pruned Upstream Network

Like
[`frs_network_upstream()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_upstream.md)
but with additional filters: minimum stream order, maximum gradient, and
watershed group restriction. Filtering happens in SQL for efficiency.

## Usage

``` r
frs_network_prune(
  blue_line_key,
  downstream_route_measure,
  stream_order_min = NULL,
  gradient_max = NULL,
  watershed_group_code = NULL,
  extra_where = NULL,
  include_all = FALSE,
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

- stream_order_min:

  Integer. Minimum Strahler stream order. Default `NULL`.

- gradient_max:

  Numeric. Maximum gradient (rise/run). Default `NULL`.

- watershed_group_code:

  Character. Restrict to a watershed group. Default `NULL`.

- extra_where:

  Character vector of additional SQL predicates (applied to alias `s`).
  Default `NULL`.

- include_all:

  Logical. If `TRUE`, include placeholder streams (999 wscode) and
  unmapped tributaries (NULL localcode). Default `FALSE` filters these
  out. Only applied when querying the FWA base table.

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

An `sf` data frame of filtered upstream stream segments.

## See also

Other prune:
[`frs_order_filter()`](https://newgraphenvironment.github.io/fresh/reference/frs_order_filter.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Upstream network from FWA base table, order >= 3
pruned <- frs_network_prune(
  blue_line_key = 360873822,
  downstream_route_measure = 166030,
  stream_order_min = 3,
  gradient_max = 0.05
)

# Coho rearing/spawning upstream of Neexdzii Kwa confluence
co_habitat <- frs_network_prune(
  blue_line_key = 360873822,
  downstream_route_measure = 166030.4,
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
} # }
```
