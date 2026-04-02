# Compute Access Barriers at a Gradient Threshold

Find gradient-based access barriers and barrier falls, write them to a
breaks table. This is the expensive step in the habitat pipeline —
`fwa_slopealonginterval()` runs on every blue line key. Species that
share the same `access_gradient_max` can reuse the same breaks table,
avoiding redundant computation.

## Usage

``` r
frs_habitat_access(
  conn,
  table,
  threshold,
  to = "working.breaks_access",
  falls = "bcfishpass.falls_vw",
  falls_where = "barrier_ind = TRUE",
  aoi = NULL
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

- falls:

  Character or `NULL`. Schema-qualified table of falls with
  `barrier_ind` column. Default `"bcfishpass.falls_vw"`. Set to `NULL`
  to skip falls barriers.

- falls_where:

  Character. SQL predicate to filter falls. Default
  `"barrier_ind = TRUE"`.

- aoi:

  AOI specification for filtering falls (passed to
  [`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md)).
  Default `NULL`.

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
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Compute access barriers at 15% gradient
frs_habitat_access(conn, "working.streams_bulk", threshold = 0.15,
  to = "working.breaks_access_bulk_015", aoi = "BULK")

DBI::dbDisconnect(conn)
} # }
```
