# Get Waterbody Polygons Upstream or Downstream of a Network Position

Returns lake or wetland polygons upstream or downstream of a given blue
line key and downstream route measure. Polygon tables (`fwa_lakes_poly`,
`fwa_wetlands_poly`) have NULL `localcode_ltree`, so `fwa_upstream()` /
`fwa_downstream()` can't query them directly. This function bridges
through the stream network: it runs the traversal on stream segments
(which have `localcode_ltree`), extracts distinct `waterbody_key`
values, then joins to the polygon table.

## Usage

``` r
frs_waterbody_network(
  conn,
  blue_line_key,
  downstream_route_measure,
  table = "whse_basemapping.fwa_lakes_poly",
  cols = c("waterbody_key", "waterbody_type", "gnis_name_1", "area_ha", "blue_line_key",
    "watershed_group_code", "geom"),
  direction = "upstream"
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- blue_line_key:

  Integer. Blue line key of the reference point.

- downstream_route_measure:

  Numeric. Downstream route measure of the reference point.

- table:

  Character. Fully qualified polygon table name. Default
  `"whse_basemapping.fwa_lakes_poly"`.

- cols:

  Character vector of column names to select from the polygon table.
  Default includes the most commonly used attributes.

- direction:

  Character. `"upstream"` (default) or `"downstream"`.

## Value

An `sf` data frame of waterbody polygons.

## Details

See [fresh#8](https://github.com/NewGraphEnvironment/fresh/issues/8) for
background.

## See also

Other traverse:
[`frs_network()`](https://newgraphenvironment.github.io/fresh/reference/frs_network.md),
[`frs_network_downstream()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_downstream.md),
[`frs_network_upstream()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_upstream.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Upstream lakes from the Neexdzii Kwa / Wedzin Kwa confluence
lakes <- frs_waterbody_network(conn,
  blue_line_key = 360873822,
  downstream_route_measure = 166030
)

# Upstream wetlands
wetlands <- frs_waterbody_network(conn,
  blue_line_key = 360873822,
  downstream_route_measure = 166030,
  table = "whse_basemapping.fwa_wetlands_poly"
)
DBI::dbDisconnect(conn)
} # }
```
