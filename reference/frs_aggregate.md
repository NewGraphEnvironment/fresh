# Aggregate Features Along the Network from Points

For each point in a table, traverse the stream network upstream or
downstream and aggregate features (streams, lakes, etc.) found on that
network. Wraps `fwa_upstream()` / `fwa_downstream()` with `GROUP BY`
aggregation.

## Usage

``` r
frs_aggregate(
  conn,
  points,
  features,
  metrics,
  id_col = c("blue_line_key", "downstream_route_measure"),
  direction = "upstream",
  where = NULL,
  to = NULL,
  overwrite = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- points:

  Character. Table of locations to aggregate from. Must have
  `blue_line_key` and `downstream_route_measure` columns (or the
  equivalents set via
  [`options()`](https://rdrr.io/r/base/options.html)), plus a unique ID
  column.

- features:

  Character. Table of features to aggregate (e.g. classified streams,
  lakes). Must have wscode/localcode columns.

- metrics:

  Named character vector. Names are output column names, values are SQL
  expressions. Example:
  `c(length_m = "SUM(ST_Length(f.geom))", count = "COUNT(*)")`.

- id_col:

  Character vector. Column(s) that uniquely identify each point, used in
  SELECT and GROUP BY. Default
  `c("blue_line_key", "downstream_route_measure")`.

- direction:

  Character. `"upstream"` (default) or `"downstream"`.

- where:

  Character or `NULL`. Optional SQL predicate to filter features before
  aggregating (alias `f`). Example: `"f.accessible IS TRUE"` or
  `"f.co_spawning IS TRUE"`.

- to:

  Character or `NULL`. If provided, write results to this table. If
  `NULL` (default), return a data.frame to R.

- overwrite:

  Logical. If `TRUE`, drop `to` before writing. Default `TRUE`.

## Value

If `to` is provided, `conn` invisibly (for piping). Otherwise, a
data.frame with one row per point and one column per metric.

## See also

Other habitat:
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
[`frs_categorize()`](https://newgraphenvironment.github.io/fresh/reference/frs_categorize.md),
[`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md),
[`frs_cluster()`](https://newgraphenvironment.github.io/fresh/reference/frs_cluster.md),
[`frs_col_generate()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_generate.md),
[`frs_col_join()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_join.md),
[`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md),
[`frs_feature_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_find.md),
[`frs_feature_index()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_index.md),
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md),
[`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md),
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
# --- What frs_aggregate output looks like ---
# frs_aggregate returns a data.frame: one row per point, one col per metric.
# This is what you'd get from the Richfield Creek example below:
example_result <- data.frame(
  blue_line_key = 360788426,
  total_km = 20.1,
  spawning_km = 3.2,
  rearing_km = 8.7,
  n_segments = 52
)
print(example_result)
#>   blue_line_key total_km spawning_km rearing_km n_segments
#> 1     360788426     20.1         3.2        8.7         52
# Read: "Upstream of the falls on Richfield Creek, there are 20.1 km of
# stream, of which 3.2 km is coho spawning and 8.7 km is rearing habitat."

if (FALSE) { # \dontrun{
# --- Live DB: full pipeline ending with aggregate ---
# Question: "How much CO habitat is blocked by the Richfield Creek falls?"
conn <- frs_db_conn()
options(fresh.wscode_col = "wscode",
        fresh.localcode_col = "localcode")

params <- frs_params(csv = system.file("testdata", "test_params.csv",
  package = "fresh"))

# 1. Extract Richfield Creek from fwapg
richfield <- frs_db_query(conn,
  "SELECT ST_Union(geom) AS geom
   FROM whse_basemapping.fwa_stream_networks_sp
   WHERE blue_line_key = 360788426")

conn |>
  frs_extract("whse_basemapping.fwa_streams_vw",
    "working.demo_agg",
    cols = c("linear_feature_id", "blue_line_key",
             "downstream_route_measure", "upstream_route_measure",
             "wscode", "localcode",
             "gradient", "channel_width", "geom"),
    aoi = richfield, overwrite = TRUE)

# 2. Break at falls, classify accessibility + CO habitat
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_agg_breaks")
DBI::dbExecute(conn,
  "CREATE TABLE working.demo_agg_breaks AS
   SELECT 360788426 AS blue_line_key,
          3460.97::double precision AS downstream_route_measure")

co_ranges <- params$CO$ranges$spawn[c("gradient", "channel_width")]
co_rear <- params$CO$ranges$rear[c("gradient", "channel_width")]

conn |>
  frs_classify("working.demo_agg", label = "accessible",
    breaks = "working.demo_agg_breaks") |>
  frs_classify("working.demo_agg", label = "co_spawning",
    ranges = co_ranges) |>
  frs_classify("working.demo_agg", label = "co_rearing",
    ranges = co_rear)

# 3. Aggregate: how much habitat is upstream of the falls (blocked)?
blocked <- frs_aggregate(conn,
  points = "working.demo_agg_breaks",
  features = "working.demo_agg",
  metrics = c(
    total_km = "ROUND(SUM(ST_Length(f.geom))::numeric / 1000, 1)",
    spawning_km = "ROUND(SUM(CASE WHEN f.co_spawning
      THEN ST_Length(f.geom) ELSE 0 END)::numeric / 1000, 1)",
    rearing_km = "ROUND(SUM(CASE WHEN f.co_rearing
      THEN ST_Length(f.geom) ELSE 0 END)::numeric / 1000, 1)",
    n_segments = "COUNT(*)"
  ),
  direction = "upstream")

message("Blocked by Richfield Creek falls:")
message("  Total: ", blocked$total_km, " km")
message("  CO spawning: ", blocked$spawning_km, " km")
message("  CO rearing: ", blocked$rearing_km, " km")

# Clean up
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_agg")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_agg_breaks")
DBI::dbDisconnect(conn)
} # }
```
