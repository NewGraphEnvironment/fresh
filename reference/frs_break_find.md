# Find Break Locations on a Stream Network

Identify break points where the stream network should be split. Supports
three modes: attribute threshold (e.g. gradient \> 0.05), existing point
table (e.g. falls, dams), or user-provided sf points (snapped via
[`frs_point_snap()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_snap.md)).

## Usage

``` r
frs_break_find(
  conn,
  table,
  to = "working.breaks",
  attribute = NULL,
  threshold = NULL,
  interval = 100L,
  distance = 100L,
  points_table = NULL,
  points = NULL,
  where = NULL,
  aoi = NULL,
  label = NULL,
  label_col = NULL,
  label_map = NULL,
  col_blk = "blue_line_key",
  col_measure = "downstream_route_measure",
  overwrite = TRUE,
  append = FALSE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- table:

  Character. Working schema table to find breaks on (from
  [`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)).

- to:

  Character. Destination table for break points. Default
  `"working.breaks"`.

- attribute:

  Character or `NULL`. Column name for threshold-based breaks. Currently
  only `"gradient"` is supported — uses `fwa_slopealonginterval()` to
  compute slope at fine resolution and find where it exceeds
  `threshold`.

- threshold:

  Numeric or `NULL`. Threshold value — intervals where computed
  `attribute > threshold` generate a break point.

- interval:

  Integer. Sampling interval in metres for attribute mode. Default
  `100`. Smaller values find more precise break locations but take
  longer.

- distance:

  Integer. Upstream distance in metres over which to compute slope for
  attribute mode. Default `100`. Should generally equal `interval`.

- points_table:

  Character or `NULL`. Schema-qualified table name containing existing
  break points with `blue_line_key` and `downstream_route_measure`
  columns (e.g. falls, dams, crossings).

- points:

  An `sf` object or `NULL`. User-provided points to snap to the stream
  network via
  [`frs_point_snap()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_snap.md).

- where:

  Character or `NULL`. SQL predicate to filter rows from `points_table`.
  Example: `"barrier_ind = TRUE"`. Only used with `points_table` mode.

- aoi:

  AOI specification for filtering (passed to `.frs_resolve_aoi()`). Only
  used with `points_table` mode.

- label:

  Character or `NULL`. Static label for all break points from this
  source (e.g. `"blocked"`, `"potential"`). Only used with
  `points_table` mode. Ignored if `label_col` is provided.

- label_col:

  Character or `NULL`. Column name in `points_table` to read labels
  from. Values are passed through as-is, or remapped via `label_map`.
  Only used with `points_table` mode.

- label_map:

  Named character vector or `NULL`. Maps values in `label_col` to output
  labels (e.g. `c("BARRIER" = "blocked")`). Only used with `label_col`.

- col_blk:

  Character. Column name for the stream identifier in `points_table`.
  Default `"blue_line_key"`.

- col_measure:

  Character. Column name for the route measure in `points_table`.
  Default `"downstream_route_measure"`.

- overwrite:

  Logical. If `TRUE`, drop `to` before creating. Default `TRUE`.

- append:

  Logical. If `TRUE`, INSERT INTO existing `to` table instead of CREATE.
  Use to combine multiple break sources. Default `FALSE`.

## Value

`conn` invisibly, for pipe chaining.

## Details

All modes produce the same output shape: a table with `blue_line_key`
and `downstream_route_measure` columns, suitable for
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md).

## See also

Other habitat:
[`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
[`frs_categorize()`](https://newgraphenvironment.github.io/fresh/reference/frs_categorize.md),
[`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md),
[`frs_col_generate()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_generate.md),
[`frs_col_join()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_join.md),
[`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md),
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md),
[`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md)

## Examples

``` r
# --- Where breaks occur (bundled data) ---
# Break points are locations where a stream attribute exceeds a threshold.
# Here: segments with gradient > 5% (potential barriers to fish passage).

d <- readRDS(system.file("extdata", "byman_ailport.rds", package = "fresh"))
streams <- d$streams

# Which segments exceed 5% gradient?
is_steep <- streams$gradient > 0.05
message(sum(is_steep, na.rm = TRUE), " of ", nrow(streams),
        " segments exceed 5% gradient")
#> 546 of 2167 segments exceed 5% gradient

# Plot: steep segments (red) are where breaks would be placed
plot(sf::st_geometry(streams), col = "grey80",
     main = "Break locations: gradient > 5%")
plot(sf::st_geometry(streams[which(is_steep), ]), col = "red", add = TRUE)
legend("topright", legend = c("below threshold", "above threshold (break)"),
       col = c("grey80", "red"), lwd = 2, cex = 0.8)


if (FALSE) { # \dontrun{
# --- Live DB usage ---
conn <- frs_db_conn()

# Attribute mode: break where gradient exceeds 5%
conn |>
  frs_extract("bcfishpass.streams_vw", "working.streams", aoi = "BULK") |>
  frs_break_find("working.streams", attribute = "gradient", threshold = 0.05)

# Table mode: break at known falls locations
conn |> frs_break_find("working.streams",
  points_table = "whse_basemapping.fwa_obstructions_sp")

DBI::dbDisconnect(conn)
} # }
```
