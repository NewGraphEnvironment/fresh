# Locate a Point on the FWA Stream Network

Given a blue line key and downstream route measure, return the point
geometry on the stream network. Wraps fwapg `fwa_locatealong()`.

## Usage

``` r
frs_point_locate(blue_line_key, downstream_route_measure, ...)
```

## Arguments

- blue_line_key:

  Integer. Blue line key of the stream.

- downstream_route_measure:

  Numeric. Downstream route measure in metres.

- ...:

  Additional arguments passed to
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md).

## Value

An `sf` data frame with a single point geometry.

## See also

Other index:
[`frs_point_snap()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_snap.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Get the point at measure 1000 on a stream
pt <- frs_point_locate(blue_line_key = 360873822, downstream_route_measure = 1000)
} # }
```
