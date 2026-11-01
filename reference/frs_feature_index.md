# Index Upstream/Downstream Features for Stream Segments

For each segment in a stream table, find which features from a feature
table are upstream or downstream on the network. Stores results as
feature ID arrays — enabling queries like "which crossings are between
this segment and the ocean?"

## Usage

``` r
frs_feature_index(
  conn,
  segments,
  features,
  direction = "downstream",
  col_segment_id = "id_segment",
  col_feature_id = "feature_id",
  to = "working.feature_index",
  label_filter = NULL,
  overwrite = TRUE,
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- segments:

  Character. Schema-qualified segmented streams table (from
  [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)).
  Must carry `watershed_group_code`, which is carried through to `to`; a
  table without it is refused before anything is written.

- features:

  Character. Schema-qualified feature table (from
  [`frs_feature_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_find.md)).

- direction:

  Character. `"downstream"` (features between segment and ocean) or
  `"upstream"` (features above segment). Default `"downstream"`.

- col_segment_id:

  Character. Segment ID column. Default `"id_segment"`.

- col_feature_id:

  Character. Feature ID column. Default `"feature_id"`. If the feature
  table has no ID column, uses row position.

- to:

  Character. Output table name. Default `"working.feature_index"`.

- label_filter:

  Character or `NULL`. SQL predicate to filter features by label before
  indexing (e.g. `"label = 'blocked'"`).

- overwrite:

  Logical. Drop `to` before creating. Default `TRUE`.

- verbose:

  Logical. Print progress. Default `TRUE`.

## Value

`conn` invisibly, for pipe chaining. `to` holds `id_segment`,
`watershed_group_code` and `features_dnstr` (or `features_upstr`), an
array of feature IDs ordered by route measure, `NULL` where a segment
has none, indexed on `(id_segment, watershed_group_code)`.

## Details

Uses `fwa_upstream()` or `fwa_downstream()` for network-aware traversal
via ltree codes.

The output is keyed on `id_segment` and `watershed_group_code`, one row
per segment of `segments`: `id_segment` is unique only within a
watershed group, so a table holding several groups (a persisted
`fresh.streams`) repeats values across them, and a join back on
`id_segment` alone would cross them (fresh#218, fresh#277). Join on
both.

## See also

Other habitat:
[`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
[`frs_categorize()`](https://newgraphenvironment.github.io/fresh/reference/frs_categorize.md),
[`frs_channel_width()`](https://newgraphenvironment.github.io/fresh/reference/frs_channel_width.md),
[`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md),
[`frs_cluster()`](https://newgraphenvironment.github.io/fresh/reference/frs_cluster.md),
[`frs_col_generate()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_generate.md),
[`frs_col_join()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_join.md),
[`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md),
[`frs_feature_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_find.md),
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md),
[`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md),
[`frs_habitat_overlay()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_overlay.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_predicates()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_predicates.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md),
[`frs_near_river()`](https://newgraphenvironment.github.io/fresh/reference/frs_near_river.md),
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Which crossings are downstream of each segment?
frs_feature_index(conn,
  segments = "fresh.streams",
  features = "working.features_crossings",
  direction = "downstream",
  to = "working.crossings_dnstr")

# Query: segments with confirmed barriers downstream. Join on both key
# columns: `id_segment` is unique only within a watershed group, and
# `fresh.streams` holds many (fresh#218).
DBI::dbGetQuery(conn, "
  SELECT s.id_segment, s.watershed_group_code, i.features_dnstr
  FROM fresh.streams s
  JOIN working.crossings_dnstr i
    ON s.id_segment = i.id_segment
   AND s.watershed_group_code = i.watershed_group_code
  WHERE array_length(i.features_dnstr, 1) > 0
  LIMIT 10")

# Fish observations upstream of each segment
frs_feature_index(conn,
  segments = "fresh.streams",
  features = "working.features_fish_obs",
  direction = "upstream",
  col_feature_id = "fish_observation_point_id",
  to = "working.fish_obs_upstr")

DBI::dbDisconnect(conn)
} # }
```
