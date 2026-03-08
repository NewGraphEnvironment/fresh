# Watershed at Measure

Delineate a watershed polygon at a point on the stream network, defined
by blue line key and downstream route measure. Wraps the fwapg
`fwa_watershedatmeasure()` function.

## Usage

``` r
frs_watershed_at_measure(
  blue_line_key,
  downstream_route_measure,
  upstream_measure = NULL,
  ...
)
```

## Arguments

- blue_line_key:

  Integer. FWA blue line key identifying the stream.

- downstream_route_measure:

  Numeric. Route measure of the downstream point (metres).

- upstream_measure:

  Numeric or `NULL`. Route measure of an upstream point. When provided,
  returns the watershed between the two measures (downstream minus
  upstream).

- ...:

  Additional arguments passed to
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md).

## Value

An `sf` data frame with a single polygon geometry.

## Details

When `upstream_measure` is provided, returns the difference between the
downstream and upstream watersheds — the subbasin *between* the two
points.

## Examples

``` r
if (FALSE) { # \dontrun{
# Watershed upstream of a single point
ws <- frs_watershed_at_measure(360873822, 208877)

# Subbasin between two points (network subtraction)
aoi <- frs_watershed_at_measure(360873822, 208877, upstream_measure = 233564)
} # }
```
