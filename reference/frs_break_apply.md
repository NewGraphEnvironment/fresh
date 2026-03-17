# Apply Break Points to Split Stream Geometry

Split stream segments in a working table at break point locations using
`ST_LocateBetween()` (PostGIS linear referencing). This follows the
bcfishpass `break_streams()` pattern: shorten original segments and
insert new segments at the break measures.

## Usage

``` r
frs_break_apply(conn, table, breaks, segment_id = "linear_feature_id")
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- table:

  Character. Working schema table to split (from
  [`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)).

- breaks:

  Character. Table name containing break points with `blue_line_key` and
  `downstream_route_measure` columns (from
  [`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md)).

- segment_id:

  Character. Column name used as the segment identifier in `table`.
  Default `"linear_feature_id"` (FWA base table). Use
  `"segmented_stream_id"` for bcfishpass tables.

## Value

`conn` invisibly, for pipe chaining.

## Details

Break points within 1m of existing segment endpoints are skipped.

## See also

Other habitat:
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
[`frs_col_generate()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_generate.md),
[`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)

## Examples

``` r
# --- Before vs after breaking (bundled data) ---
d <- readRDS(system.file("extdata", "byman_ailport.rds", package = "fresh"))
streams <- d$streams

# Visualize: segments that would be split at gradient > 8%
steep <- !is.na(streams$gradient) & streams$gradient > 0.08
streams$would_break <- ifelse(steep, "split here", "keep")
message(sum(steep), " of ", nrow(streams), " segments would be split")
#> 259 of 2167 segments would be split

plot(streams["would_break"],
     main = "Segments split by frs_break_apply()",
     pal = c("grey80", "red"), key.pos = 1)


if (FALSE) { # \dontrun{
# --- Live DB: copy-paste to see before/after ---
conn <- frs_db_conn()
aoi <- d$aoi

# 1. Extract FWA base streams to working schema
conn |> frs_extract(
  from = "whse_basemapping.fwa_stream_networks_sp",
  to = "working.demo_break",
  cols = c("linear_feature_id", "blue_line_key",
           "downstream_route_measure", "upstream_route_measure",
           "gradient", "geom"),
  aoi = aoi, overwrite = TRUE)

# 2. Plot BEFORE
before <- frs_db_query(conn,
  "SELECT gradient, geom FROM working.demo_break")
plot(before["gradient"], main = paste("Before:", nrow(before), "segments"))

# 3. Break where gradient > 8% (sampled at 100m intervals)
conn |> frs_break("working.demo_break",
  attribute = "gradient", threshold = 0.08)

# 4. Plot AFTER — more segments where gradient splits occurred
after <- frs_db_query(conn,
  "SELECT gradient, geom FROM working.demo_break")
plot(after["gradient"],
  main = paste("After:", nrow(after), "segments (+",
               nrow(after) - nrow(before), "from breaks)"))

# Clean up
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_break")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.breaks")
DBI::dbDisconnect(conn)
} # }
```
