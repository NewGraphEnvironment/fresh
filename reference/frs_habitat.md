# Run Habitat Pipeline for Watershed Groups

Orchestrate the full habitat pipeline for one or more watershed groups.
Per WSG: generates gradient access barriers, segments the network via
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md),
classifies habitat via
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md),
and persists results. Parallelizes across WSGs with
[`mirai::mirai_map()`](https://mirai.r-lib.org/reference/mirai_map.html)
when `workers > 1`.

## Usage

``` r
frs_habitat(
  conn,
  wsg,
  to_streams = NULL,
  to_habitat = NULL,
  break_sources = NULL,
  workers = 1L,
  password = "",
  cleanup = TRUE,
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- wsg:

  Character. One or more watershed group codes (e.g. `"BULK"`,
  `c("BULK", "MORR")`).

- to_streams:

  Character or `NULL`. Schema-qualified table for persistent stream
  segments (e.g. `"fresh.streams"`). Accumulates across runs — existing
  rows for the same WSG are replaced.

- to_habitat:

  Character or `NULL`. Schema-qualified table for habitat
  classifications (e.g. `"fresh.streams_habitat"`). Long format: one row
  per segment x species.

- break_sources:

  List of additional break source specs (falls, crossings, etc.), or
  `NULL`. Gradient access barriers are generated automatically from
  species parameters. See
  [`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md)
  for spec format.

- workers:

  Integer. Number of parallel workers. Default `1`. Values \> 1 require
  the `mirai` package.

- password:

  Character. Database password for parallel workers.

- cleanup:

  Logical. Drop working tables when done. Default `TRUE`.

- verbose:

  Logical. Print progress. Default `TRUE`.

## Value

A data frame with one row per WSG and columns `wsg`, `n_segments`,
`n_species`, `elapsed_s`.

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
[`frs_feature_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_find.md),
[`frs_feature_index()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_index.md),
[`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md),
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Single WSG — gradient barriers auto-generated from species params
frs_habitat(conn, "BULK",
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat",
  break_sources = list(
    list(table = "working.falls", where = "barrier_ind = TRUE",
         label = "blocked")))

# Multiple WSGs, parallel — results accumulate in same tables
frs_habitat(conn, c("BULK", "MORR", "ZYMO"),
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat",
  workers = 4, password = "postgres",
  break_sources = list(
    list(table = "working.falls", where = "barrier_ind = TRUE",
         label = "blocked"),
    list(table = "working.crossings",
         label_col = "barrier_status",
         label_map = c("BARRIER" = "blocked",
                       "POTENTIAL" = "potential"))))

DBI::dbDisconnect(conn)
} # }
```
