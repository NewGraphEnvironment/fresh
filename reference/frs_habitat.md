# Run Habitat Pipeline for Watershed Groups

Orchestrate the full habitat pipeline for all species present in one or
more watershed groups. Calls
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md)
per WSG to extract the base network and pre-compute breaks, then
flattens all (WSG, species) pairs and classifies them via
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md).
Both phases parallelize with
[`mirai::mirai_map()`](https://mirai.r-lib.org/reference/mirai_map.html)
when `workers > 1`.

## Usage

``` r
frs_habitat(
  conn,
  wsg,
  workers = 1L,
  break_sources = NULL,
  to_prefix = NULL,
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

- workers:

  Integer. Number of parallel workers. Default `1` (sequential). Values
  \> 1 require the `mirai` package. Each worker opens its own database
  connection (params extracted from `conn`). Used for both Phase 1
  (partition prep across WSGs) and Phase 2 (species classification).

- break_sources:

  List of break source specs passed to
  [`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
  or `NULL` for gradient-only. Each spec is a list with `table`, and
  optionally `where`, `label`, `label_col`, `label_map`. See
  [`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md)
  for details.

- to_prefix:

  Character or `NULL`. When provided, persist species output tables with
  this prefix (e.g. `"fresh.streams"` creates `fresh.streams_co`,
  `fresh.streams_bt`). Existing rows for the same WSG are replaced
  (delete + insert). Default `NULL` (no persistence, working tables
  only).

- password:

  Character. Database password for parallel workers. Required when
  `workers > 1` and the database uses password auth. Not needed for
  trust auth or `.pgpass`.

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

# With break sources (falls, crossings, etc.)
result <- frs_habitat(conn, "ADMS", break_sources = list(
  list(table = "working.falls", where = "barrier_ind = TRUE",
       label = "blocked"),
  list(table = "working.pscis",
       label_col = "barrier_status",
       label_map = c("BARRIER" = "blocked", "POTENTIAL" = "potential"))
))

# Persist to output tables (accumulate across runs)
result <- frs_habitat(conn, "BULK",
  to_prefix = "fresh.streams",
  break_sources = list(
    list(table = "working.falls", label = "blocked")))
# Creates: fresh.streams_co, fresh.streams_bt, etc.
# Re-run with "MORR" — appends to same tables

# Gradient-only (no external break sources)
result <- frs_habitat(conn, "ADMS")

DBI::dbDisconnect(conn)
} # }
```
