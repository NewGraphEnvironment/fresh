# Snap Points to the Nearest Stream

Snaps a whole dataset of points to the stream network in one query and
returns each point's network position: `blue_line_key`,
`downstream_route_measure`, `watershed_group_code`, `linear_feature_id`,
`wscode_ltree`, `localcode_ltree`. Each point is matched by a lateral
nearest-neighbour search against the network table, so 10,000 points
cost one snap query, not 10,000.

## Usage

``` r
frs_point_snap(
  conn,
  points,
  ...,
  to = NULL,
  col_id = NULL,
  col_x = "x",
  col_y = "y",
  col_geom = "geom",
  srid = 4326L,
  col_blk = NULL,
  tolerance = 100,
  num_features = 1L,
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

- points:

  The points to snap. One of:

  - a data frame with coordinate columns `col_x` / `col_y` in `srid`;

  - an `sf` object with POINT geometry (its CRS gives the SRID);

  - a schema-qualified table name with geometry column `col_geom` (Point
    or MultiPoint; the first part of a MultiPoint is used, and the
    geometry's own SRID applies, so `srid` is ignored). `col_id` is
    required for a table.

  Rows with missing coordinates are dropped, as are points farther than
  `tolerance` from any candidate segment. In a geographic CRS (e.g.
  4326, 4269), coordinates outside lon/lat range are dropped with a
  message.

- ...:

  Must be empty. Catches the pre-0.40.0 `x =` / `y =` call.

- to:

  Character or `NULL`. Schema-qualified destination table. When given,
  the result is written there (dropped and recreated) and `conn` is
  returned invisibly. Default `NULL` returns an `sf` object.

- col_id:

  Character or `NULL`. Column that identifies each point. Values must be
  unique and non-missing. Carried into the output under the same name.
  `NULL` (data frame / `sf` only) numbers the rows in a column named
  `id_point`.

- col_x, col_y:

  Character. Coordinate columns of a data frame. Default `"x"`, `"y"`.

- col_geom:

  Character. Geometry column of a table input. Default `"geom"`.

- srid:

  Integer. SRID of `col_x` / `col_y` for a data frame. Default `4326`
  (WGS84 lon/lat).

- col_blk:

  Character or `NULL`. Column holding a per-point `blue_line_key` hint.
  A point with a hint snaps only to that stream; a point whose hint is
  missing snaps to any stream.

- tolerance:

  Numeric. Maximum snap distance in metres. Default `100`, the distance
  bcfishobs accepts for its A/B matches.

- num_features:

  Integer. Candidates kept per point. Default `1`. When greater than 1
  the output gains `candidate_rank` (1 = nearest).

- stream_order_min:

  Integer or `NULL`. Minimum stream order of a candidate segment.

- exclude_edge_types:

  Integer vector or `NULL`. Edge types that are never candidates.
  Default `1425L` (subsurface flow). `NULL` excludes none. See
  [`frs_edge_types()`](https://newgraphenvironment.github.io/fresh/reference/frs_edge_types.md).

## Value

Without `to`, an `sf` object (EPSG:3005) with one row per point ×
candidate: the id column, `linear_feature_id`, `blue_line_key`,
`downstream_route_measure`, `watershed_group_code`, `wscode_ltree`,
`localcode_ltree`, `gnis_name`, `distance_to_stream`, `candidate_rank`
(when `num_features > 1`) and the snapped point `geom`. With `to`,
`conn` invisibly.

## Details

Candidates are network segments within `tolerance` of the point, nearest
first (ties broken by `linear_feature_id`). Placeholder (`999.*`) and
unmapped (NULL local code) segments are never candidates;
`exclude_edge_types` drops more. The measure is a whole metre, following
bcfishpass (`04_pscis.sql`): the position rounded down, but never below
the segment's start rounded up, so a point in a segment's first
fractional metre (or on a segment shorter than a metre) gets that
rounded-up start. To score and pick among several candidates per point,
write them to a table (`num_features > 1`, `to = `) and pass it to
[`frs_candidates_pick()`](https://newgraphenvironment.github.io/fresh/reference/frs_candidates_pick.md).

The network table and its column names come from the `fresh.*` options
(see `tbl_network`, `blk_col`, `segment_id_col`, `measure_ds_col`,
`measure_us_col`, `wscode_col`, `localcode_col`). A custom network table
also needs `watershed_group_code`, `gnis_name`, `edge_type`,
`stream_order` and `length_metre` columns.

Data frame and `sf` points travel to the database as a temporary table,
which needs one session for the whole call. That holds for a plain
connection and for each mirai worker; it does not hold behind a pooler
that switches backends per statement (pgbouncer transaction pooling).

## See also

Other index:
[`frs_point_locate()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_locate.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Three sampling sites, snapped in one query
sites <- data.frame(
  site = c("upper", "middle", "lower"),
  x = c(-126.52, -126.61, -126.70),
  y = c(54.49, 54.58, 54.41)
)
snapped <- frs_point_snap(conn, sites, col_id = "site", tolerance = 500)
snapped[, c("site", "blue_line_key", "downstream_route_measure",
            "watershed_group_code", "distance_to_stream")]

# Up to three candidate streams per site, ranked by distance
frs_point_snap(conn, sites, col_id = "site", tolerance = 1000,
  num_features = 3)

# A table of crossings, written to a table for frs_candidates_pick()
frs_point_snap(conn, "whse_fish.pscis_assessment_svw",
  col_id = "stream_crossing_id", tolerance = 150, num_features = 5,
  to = "working.pscis_candidates")

DBI::dbDisconnect(conn)
} # }
```
