# Fetch FWA Wetlands

Retrieve wetland polygons from an FWA wetlands table. Filter by
watershed group code, blue line key, and/or bounding box.

## Usage

``` r
frs_wetland_fetch(
  conn,
  watershed_group_code = NULL,
  blue_line_key = NULL,
  bbox = NULL,
  area_ha_min = NULL,
  table = "whse_basemapping.fwa_wetlands_poly",
  cols = c("waterbody_poly_id", "waterbody_key", "waterbody_type", "area_ha",
    "gnis_name_1", "blue_line_key", "watershed_group_code", "geom"),
  limit = NULL
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

  Integer. Blue line key for wetlands on a specific stream. Default
  `NULL`.

- bbox:

  Numeric vector of length 4 (`xmin`, `ymin`, `xmax`, `ymax`) in BC
  Albers (EPSG:3005). Default `NULL`.

- area_ha_min:

  Numeric. Minimum wetland area in hectares. Default `NULL`.

- table:

  Character. Fully qualified table name. Default
  `"whse_basemapping.fwa_wetlands_poly"`.

- cols:

  Character vector of column names to select. Default includes the most
  commonly used FWA wetland attributes.

- limit:

  Integer. Maximum rows to return. Default `NULL` (no limit).

## Value

An `sf` data frame of wetland polygons.

## See also

Other fetch:
[`frs_lake_fetch()`](https://newgraphenvironment.github.io/fresh/reference/frs_lake_fetch.md),
[`frs_stream_fetch()`](https://newgraphenvironment.github.io/fresh/reference/frs_stream_fetch.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()
wetlands <- frs_wetland_fetch(conn, watershed_group_code = "BULK")
wetlands_big <- frs_wetland_fetch(conn, watershed_group_code = "BULK",
  area_ha_min = 5)
DBI::dbDisconnect(conn)
} # }
```
