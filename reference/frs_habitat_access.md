# Compute Access Breaks at a Gradient Threshold

Find gradient-based access breaks and append break points from external
sources (e.g. falls, crossings, dams). This is the expensive step in the
habitat pipeline — `fwa_slopealonginterval()` runs on every blue line
key. Species that share the same `access_gradient_max` can reuse the
same breaks table, avoiding redundant computation.

## Usage

``` r
frs_habitat_access(
  conn,
  table,
  threshold,
  to = "working.breaks_access",
  break_sources = NULL
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- table:

  Character. Working schema table with the stream network (from
  [`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)).

- threshold:

  Numeric. Access gradient threshold (e.g. `0.15` for 15%).

- to:

  Character. Destination table for break points. Default
  `"working.breaks_access"`.

- break_sources:

  List of break source specs, or `NULL` to skip external sources
  (gradient-only). Each spec is a list with:

  table

  :   Schema-qualified table name with `blue_line_key` and
      `downstream_route_measure` columns.

  where

  :   SQL predicate to filter rows (optional).

  label

  :   Static label string for all rows (optional).

  label_col

  :   Column name to read labels from (optional).

  label_map

  :   Named character vector mapping `label_col` values to output labels
      (optional).

## Value

`conn` invisibly, for pipe chaining.

## See also

Other habitat:
[`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
[`frs_categorize()`](https://newgraphenvironment.github.io/fresh/reference/frs_categorize.md),
[`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md),
[`frs_col_generate()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_generate.md),
[`frs_col_join()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_join.md),
[`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md),
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md),
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md),
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Gradient-only (no external break sources)
frs_habitat_access(conn, "working.streams_bulk", threshold = 0.15,
  to = "working.breaks_access_bulk_015")

# With falls and PSCIS crossings
frs_habitat_access(conn, "working.streams_bulk", threshold = 0.15,
  to = "working.breaks_access_bulk_015",
  break_sources = list(
    list(table = "working.falls", where = "barrier_ind = TRUE",
         label = "blocked"),
    list(table = "working.pscis",
         label_col = "barrier_status",
         label_map = c("BARRIER" = "blocked",
                       "POTENTIAL" = "potential"))
  ))

DBI::dbDisconnect(conn)
} # }
```
