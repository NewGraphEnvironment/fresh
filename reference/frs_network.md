# Query Multiple Tables Upstream or Downstream of a Network Position

Point at any position on the FWA stream network and retrieve features
from one or more tables — streams, crossings, barriers, fish
observations, lakes, wetlands, or any table with ltree watershed codes.
Tables with `localcode_ltree` are queried directly via `fwa_upstream()`
/ `fwa_downstream()`. Tables without (like `fwa_lakes_poly`) are queried
via the waterbody_key bridge through the stream network.

## Usage

``` r
frs_network(
  blue_line_key,
  downstream_route_measure,
  upstream_measure = NULL,
  upstream_blk = NULL,
  tables = NULL,
  direction = "upstream",
  ...
)
```

## Arguments

- blue_line_key:

  Integer. Blue line key of the reference point.

- downstream_route_measure:

  Numeric. Downstream route measure of the downstream boundary.

- upstream_measure:

  Numeric or `NULL`. Downstream route measure of the upstream boundary.
  When provided, returns features between the two measures (network
  subtraction). Only valid with `direction = "upstream"`.

- upstream_blk:

  Integer or `NULL`. Blue line key for the upstream point. Defaults to
  `blue_line_key` (same stream). Use when the upstream point is on a
  tributary.

- tables:

  A named list of table specifications. Each element can be:

  - A character string (table name) — uses default columns

  - A list with any of: `table`, `cols`, `wscode_col`, `localcode_col`,
    `extra_where`

  If `NULL` (default), queries FWA streams only.

- direction:

  Character. `"upstream"` (default) or `"downstream"`.

- ...:

  Additional arguments passed to
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md).

## Value

A named list of `sf` data frames (or plain data frames for tables
without geometry). If only one table is queried, returns the data frame
directly.

## Details

When `upstream_measure` is provided, returns only features *between* the
two points — network subtraction (upstream of A minus upstream of B)
with no spatial clipping needed. The upstream point can be on a
different blue line key (e.g. a tributary) by specifying `upstream_blk`.

## See also

Other traverse:
[`frs_network_downstream()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_downstream.md),
[`frs_network_upstream()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_upstream.md),
[`frs_waterbody_network()`](https://newgraphenvironment.github.io/fresh/reference/frs_waterbody_network.md)

## Examples

``` r
if (FALSE) { # \dontrun{
blk <- 360873822

# Everything upstream of a point
streams <- frs_network(blk, 166030)

# Between two points (subbasin): upstream of Byman minus upstream of Ailport
result <- frs_network(blk, 208877, upstream_measure = 233564, tables = list(
  streams = "whse_basemapping.fwa_stream_networks_sp",
  lakes = "whse_basemapping.fwa_lakes_poly",
  crossings = "bcfishpass.crossings",
  observations = list(
    table = "bcfishpass.observations_vw",
    wscode_col = "wscode",
    localcode_col = "localcode"
  )
))
} # }
```
