# Locate a Point on the FWA Stream Network

Given a blue line key and downstream route measure, return the point
geometry on the stream network. Wraps fwapg `fwa_locatealong()`.

## Usage

``` r
frs_point_locate(conn, blue_line_key, downstream_route_measure)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- blue_line_key:

  Integer. Blue line key of the stream.

- downstream_route_measure:

  Numeric. Downstream route measure in metres.

## Value

An `sf` data frame with a single point geometry.

## See also

Other index:
[`frs_point_snap()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_snap.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()
pt <- frs_point_locate(conn, blue_line_key = 360873822,
  downstream_route_measure = 1000)
DBI::dbDisconnect(conn)
} # }
```
