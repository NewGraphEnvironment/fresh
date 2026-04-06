# Break Stream Network at Threshold or Point Locations

Convenience wrapper that calls
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
optionally
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
then
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md)
in sequence.

## Usage

``` r
frs_break(
  conn,
  table,
  to = "working.breaks",
  attribute = NULL,
  threshold = NULL,
  interval = 100L,
  distance = 100L,
  points_table = NULL,
  points = NULL,
  points_where = NULL,
  aoi = NULL,
  overwrite = TRUE,
  evidence_table = NULL,
  where = NULL,
  count_threshold = 1L,
  segment_id = "linear_feature_id"
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

- points_where:

  Character or `NULL`. SQL predicate to filter rows from `points_table`
  (e.g. `"barrier_ind = TRUE"`). Passed to
  [`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md)
  as `where`.

- aoi:

  AOI specification for filtering (passed to `.frs_resolve_aoi()`). Only
  used with `points_table` mode.

- overwrite:

  Logical. If `TRUE`, drop `to` before creating. Default `TRUE`.

- evidence_table:

  Character or `NULL`. If provided, validate breaks against upstream
  evidence before applying. Passed to
  [`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md).

- where:

  Character or `NULL`. SQL predicate to filter evidence (e.g.
  `"e.species_code IN ('CO','CH')"`). Passed to
  [`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md).

- count_threshold:

  Integer. Minimum upstream evidence count to remove a break. Default
  `1`.

- segment_id:

  Character. Column name used as segment identifier. Passed to
  [`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md).
  Default `"linear_feature_id"`.

## Value

`conn` invisibly, for pipe chaining.

## See also

Other habitat:
[`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
[`frs_categorize()`](https://newgraphenvironment.github.io/fresh/reference/frs_categorize.md),
[`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md),
[`frs_col_generate()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_generate.md),
[`frs_col_join()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_join.md),
[`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md),
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md),
[`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md),
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
# --- Concept: what frs_break does (bundled data) ---
d <- readRDS(system.file("extdata", "byman_ailport.rds", package = "fresh"))
streams <- d$streams

# Steep segments are where breaks get placed
steep <- !is.na(streams$gradient) & streams$gradient > 0.08
plot(sf::st_geometry(streams), col = "grey80",
     main = "Gradient breaks (> 8%)")
plot(sf::st_geometry(streams[steep, ]), col = "red", add = TRUE)
legend("topright",
       legend = c("below threshold", "above (break here)"),
       col = c("grey80", "red"), lwd = 2, cex = 0.8)


if (FALSE) { # \dontrun{
# --- Live DB: copy-paste to see before/after ---
conn <- frs_db_conn()
aoi <- d$aoi  # Byman-Ailport sf polygon from bundled data

# 1. Extract FWA base streams (unsegmented) to working schema
conn |> frs_extract(
  from = "whse_basemapping.fwa_stream_networks_sp",
  to = "working.demo_streams",
  cols = c("linear_feature_id", "blue_line_key",
           "downstream_route_measure", "upstream_route_measure",
           "gradient", "geom"),
  aoi = aoi,
  overwrite = TRUE
)

# 2. Plot BEFORE — original segments
before <- frs_db_query(conn,
  "SELECT gradient, geom FROM working.demo_streams")
n_before <- nrow(before)
plot(before["gradient"], main = paste("Before:", n_before, "segments"))

# 3. Convert to generated columns — gradient auto-recomputes after break
conn |> frs_col_generate("working.demo_streams")

# 4. Break at gradient > 8%
conn |> frs_break("working.demo_streams",
  attribute = "gradient", threshold = 0.08)

# 5. Plot AFTER — more segments, gradient recomputed per sub-segment
after <- frs_db_query(conn,
  "SELECT gradient, geom FROM working.demo_streams")
n_after <- nrow(after)
plot(after["gradient"],
     main = paste("After:", n_after, "segments (+",
                  n_after - n_before, "from breaks)"))

# Clean up
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_streams")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.breaks")
DBI::dbDisconnect(conn)
} # }
```
