# Find Features on a Stream Network

Locate features from a database table or sf object on the stream
network. Produces a table with `blue_line_key`,
`downstream_route_measure`, `label`, and `source` columns, suitable for
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_feature_index()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_index.md),
or as a break source in
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md).

## Usage

``` r
frs_feature_find(
  conn,
  table,
  to = "working.features",
  points_table = NULL,
  points = NULL,
  where = NULL,
  col_blk = "blue_line_key",
  col_measure = "downstream_route_measure",
  col_id = NULL,
  label = NULL,
  label_col = NULL,
  label_map = NULL,
  overwrite = TRUE,
  append = FALSE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- table:

  Character. Working streams table (for BLK scoping).

- to:

  Character. Destination table name. Default `"working.features"`.

- points_table:

  Character or `NULL`. Schema-qualified table with network-referenced
  features.

- points:

  An `sf` object or `NULL`. User-provided points to snap to the network
  via
  [`frs_point_snap()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_snap.md).

- where:

  Character or `NULL`. SQL predicate to filter `points_table`.

- col_blk:

  Character. Column name for stream identifier in `points_table`.
  Default `"blue_line_key"`.

- col_measure:

  Character. Column name for route measure in `points_table`. Default
  `"downstream_route_measure"`.

- col_id:

  Character or `NULL`. Column name for feature ID. When provided,
  included in output for joining back to source.

- label:

  Character or `NULL`. Static label for all features.

- label_col:

  Character or `NULL`. Column name to read labels from.

- label_map:

  Named character vector or `NULL`. Maps `label_col` values to output
  labels.

- overwrite:

  Logical. Drop `to` before creating. Default `TRUE`.

- append:

  Logical. INSERT INTO existing `to` table. Default `FALSE`.

## Value

`conn` invisibly, for pipe chaining.

## Details

Unlike
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md)
which is specific to gradient threshold detection, this function handles
any point features on the network: crossings, fish observations, water
quality stations, flow gauges, territory boundaries, etc.

## See also

Other habitat:
[`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
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
[`frs_feature_index()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_index.md),
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md),
[`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md),
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Crossings with severity labels
frs_feature_find(conn, "working.streams",
  points_table = "working.crossings",
  col_id = "aggregated_crossings_id",
  label_col = "barrier_status",
  label_map = c("BARRIER" = "blocked", "POTENTIAL" = "potential"),
  to = "working.features_crossings")

# Fish observations
frs_feature_find(conn, "working.streams",
  points_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
  col_id = "fish_observation_point_id",
  label_col = "species_code",
  to = "working.features_fish_obs")

# Use as break source in habitat pipeline
frs_habitat(conn, "BULK", break_sources = list(
  list(table = "working.features_crossings",
       label_col = "label")))

DBI::dbDisconnect(conn)
} # }
```
