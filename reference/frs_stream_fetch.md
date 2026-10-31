# Fetch FWA Stream Network Segments

Retrieve stream segments from a stream network table. Filter by
watershed group code, blue line key, bounding box and/or area of
interest.

## Usage

``` r
frs_stream_fetch(
  conn,
  watershed_group_code = NULL,
  blue_line_key = NULL,
  bbox = NULL,
  stream_order_min = NULL,
  table = "whse_basemapping.fwa_stream_networks_sp",
  cols = c("linear_feature_id", "blue_line_key", "waterbody_key", "edge_type",
    "gnis_name", "stream_order", "stream_magnitude", "gradient",
    "downstream_route_measure", "upstream_route_measure", "length_metre",
    "watershed_group_code", "wscode_ltree", "localcode_ltree", "geom"),
  include_all = FALSE,
  limit = NULL,
  aoi = NULL,
  simplify_m = NULL,
  order_by = "linear_feature_id"
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- watershed_group_code:

  Character. Watershed group code (e.g. `"BULK"`). Default `NULL`.

- blue_line_key:

  Integer. Blue line key for a specific stream. Default `NULL`.

- bbox:

  Numeric vector of length 4 (`xmin`, `ymin`, `xmax`, `ymax`) in BC
  Albers (EPSG:3005). Matches on envelope overlap (`&&`), so a segment
  whose envelope touches the box is returned even when the segment does
  not; use `aoi` for exact intersection. Default `NULL`.

- stream_order_min:

  Integer. Minimum Strahler stream order to return. Default `NULL` (all
  orders).

- table:

  Character. Fully qualified table name. Default
  `"whse_basemapping.fwa_stream_networks_sp"`.

- cols:

  Character vector of column names to select. Default includes the most
  commonly used FWA stream attributes.

- include_all:

  Logical. If `TRUE`, include placeholder streams (999 wscode) and
  unmapped tributaries (NULL localcode). Default `FALSE` filters these
  out. Only applied when querying the FWA base table.

- limit:

  Integer. Maximum rows to return. Default `NULL` (no limit).

- aoi:

  Area of interest. An `sf`/`sfc` polygon (transformed to EPSG:3005, so
  it must carry a CRS) filters with `ST_Intersects()`. For WKT, pass
  `sf::st_as_sfc(wkt, crs = 3005)`. Also accepts the other forms of
  [`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)'s
  `aoi`; its character form (watershed group codes) is an envelope
  prefilter, so use `watershed_group_code` to select groups. Default
  `NULL`.

- simplify_m:

  Numeric. Simplification tolerance in metres, applied in the database.
  Drops M coordinates. Default `NULL` (full resolution).

- order_by:

  Character vector. Columns to order rows by. Default
  `"linear_feature_id"`, the FWA table's unique key; give another
  table's unique key (one or more columns) when `table` is changed, or
  `NULL` for no `ORDER BY`. With `limit`, the first `limit` rows in this
  order are returned.

## Value

An `sf` data frame of stream segments.

## Details

Rows come back ordered by `order_by` (the table's unique key by
default), so the same database returns the same `sf` on every call. For
map layers, `simplify_m` simplifies in the database with
`ST_SimplifyPreserveTopology(geom, simplify_m)`. Unlike the polygon
fetchers it is not wrapped in `ST_Normalize()`, which would reverse any
line whose first vertex sorts after its last, so segments keep their
digitized (downstream to upstream) direction. `length_metre` is the
stored, unsimplified length. Two databases on different GEOS versions
can still simplify a line differently, so a caller that saves the result
should record `postgis_full_version()` with it.

## See also

Other fetch:
[`frs_lake_fetch()`](https://newgraphenvironment.github.io/fresh/reference/frs_lake_fetch.md),
[`frs_wetland_fetch()`](https://newgraphenvironment.github.io/fresh/reference/frs_wetland_fetch.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# All streams in the Bulkley watershed group
streams <- frs_stream_fetch(conn, watershed_group_code = "BULK")

# Streams with order >= 4
streams <- frs_stream_fetch(conn, watershed_group_code = "BULK",
  stream_order_min = 4)

# Map layer: inside a watershed polygon, simplified to 25 m
ws <- frs_watershed_at_measure(conn, 360873822, 208877, simplify_m = 25)
streams_map <- frs_stream_fetch(conn, aoi = ws, stream_order_min = 3,
  simplify_m = 25)
DBI::dbDisconnect(conn)
} # }
```
