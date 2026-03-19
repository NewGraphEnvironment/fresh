# Snap a Point to the Nearest FWA Stream

Snaps x/y coordinates to the nearest stream segment. When no
`blue_line_key` is given, wraps fwapg `fwa_indexpoint()`. When
`blue_line_key` is provided, uses KNN against `fwa_stream_networks_sp`
filtered to that stream, with measure derivation and boundary clamping
(following the bcfishpass pattern).

## Usage

``` r
frs_point_snap(
  conn,
  x,
  y,
  srid = 4326L,
  tolerance = 5000,
  num_features = 1L,
  blue_line_key = NULL,
  stream_order_min = NULL,
  exclude_edge_types = 1425L
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

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

- blue_line_key:

  Integer. Optional. When provided, snap only to this stream. Bypasses
  `fwa_indexpoint()` and uses KNN against `fwa_stream_networks_sp` with
  measure derivation and boundary clamping.

- stream_order_min:

  Integer. Optional. Minimum stream order for snap candidates. Ignored
  when `blue_line_key` is provided. Forces KNN path.

- exclude_edge_types:

  Integer vector or `NULL`. Edge types to exclude from snap candidates.
  Default `1425L` (subsurface flow — underground conduits). Set to
  `NULL` to snap to all edge types. Only applies to KNN path (when
  `blue_line_key` or `stream_order_min` is provided). See
  [`frs_edge_types()`](https://newgraphenvironment.github.io/fresh/reference/frs_edge_types.md)
  for the full lookup table.

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
conn <- frs_db_conn()

# Snap to nearest stream (any)
snapped <- frs_point_snap(conn, x = -126.5, y = 54.5)

# Snap to a specific stream (Bulkley River)
snapped <- frs_point_snap(conn, x = -126.5, y = 54.5,
  blue_line_key = 360873822)

# Snap to order 4+ streams only
snapped <- frs_point_snap(conn, x = -126.5, y = 54.5, stream_order_min = 4)
DBI::dbDisconnect(conn)
} # }
```
