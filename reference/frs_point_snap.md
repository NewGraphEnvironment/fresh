# Snap a Point to the Nearest FWA Stream

Wraps the fwapg `fwa_indexpoint()` function to snap x/y coordinates to
the nearest stream segment. Returns the snapped point with its blue line
key, downstream route measure, and distance to stream.

## Usage

``` r
frs_point_snap(x, y, srid = 4326L, tolerance = 5000, num_features = 1L, ...)
```

## Arguments

- x:

  Numeric. Longitude or easting.

- y:

  Numeric. Latitude or northing.

- srid:

  Integer. Spatial reference ID of the input coordinates. Default `4326`
  (WGS84 lon/lat).

- tolerance:

  Numeric. Maximum search distance in metres. Default `5000`.

- num_features:

  Integer. Number of candidate matches to return. Default `1`.

- ...:

  Additional arguments passed to
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md).

## Value

An `sf` data frame with columns: `linear_feature_id`, `gnis_name`,
`blue_line_key`, `downstream_route_measure`, `distance_to_stream`, and
snapped point `geom`.

## See also

Other index:
[`frs_point_locate()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_locate.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Snap a lon/lat point to the nearest stream
snapped <- frs_point_snap(x = -126.5, y = 54.5)
snapped$blue_line_key
snapped$downstream_route_measure
} # }
```
