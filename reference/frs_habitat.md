# Run Habitat Pipeline for Watershed Groups

Orchestrate the full habitat pipeline for all species present in one or
more watershed groups. Calls
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md)
per WSG to extract the base network and pre-compute breaks, then
flattens all (WSG, species) pairs and classifies them via
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md).
Both phases parallelize with
[`furrr::future_map()`](https://furrr.futureverse.org/reference/future_map.html)
when `workers > 1`.

## Usage

``` r
frs_habitat(conn, wsg, workers = 1L, cleanup = TRUE, verbose = TRUE)
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

- workers:

  Integer. Number of parallel workers. Default `1` (sequential). Values
  \> 1 require the `furrr` package. Each worker opens its own database
  connection. Used for both Phase 1 (partition prep across WSGs) and
  Phase 2 (species classification).

- cleanup:

  Logical. Drop intermediate tables (base network, break tables) when
  done. Default `TRUE`.

- verbose:

  Logical. Print progress and timing. Default `TRUE`.

## Value

A data frame with one row per (WSG, species) pair and columns
`partition`, `species_code`, `access_threshold`, `habitat_threshold`,
`elapsed_s`, and `table_name`.

## Details

Output tables are WSG-scoped: `working.streams_bulk_co`,
`working.streams_morr_bt`, etc.

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
[`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Single watershed group
result <- frs_habitat(conn, "BULK")

# Multiple watershed groups, 4 parallel workers
result <- frs_habitat(conn, c("BULK", "MORR"), workers = 4)

DBI::dbDisconnect(conn)
} # }
```
