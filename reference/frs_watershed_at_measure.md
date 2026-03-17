# Watershed at Measure

Delineate a watershed polygon at a point on the stream network, defined
by blue line key and downstream route measure. Wraps the fwapg
`fwa_watershedatmeasure()` function.

## Usage

``` r
frs_watershed_at_measure(
  conn,
  blue_line_key,
  downstream_route_measure,
  upstream_measure = NULL,
  upstream_blk = NULL
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- blue_line_key:

  Integer. FWA blue line key identifying the stream.

- downstream_route_measure:

  Numeric. Route measure of the downstream point (metres).

- upstream_measure:

  Numeric or `NULL`. Route measure of an upstream point. When provided,
  returns the watershed between the two measures (downstream minus
  upstream).

- upstream_blk:

  Integer or `NULL`. Blue line key for the upstream point. Defaults to
  `blue_line_key` (same stream). Use when the upstream point is on a
  tributary.

## Value

An `sf` data frame with a single polygon geometry.

## Details

When `upstream_measure` is provided, returns the difference between the
downstream and upstream watersheds — the subbasin *between* the two
points. The upstream point can be on a different blue line key (e.g. a
tributary) by specifying `upstream_blk`.

## See also

Other watershed:
[`frs_watershed_split()`](https://newgraphenvironment.github.io/fresh/reference/frs_watershed_split.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Watershed upstream of a single point
ws <- frs_watershed_at_measure(conn, 360873822, 208877)

# Subbasin between two points on the same stream
aoi <- frs_watershed_at_measure(conn, 360873822, 208877,
  upstream_measure = 233564)

# Subbasin with upstream point on a tributary (different BLK)
aoi <- frs_watershed_at_measure(conn, 360873822, 165115,
  upstream_measure = 838, upstream_blk = 360886221)
DBI::dbDisconnect(conn)
} # }
```
