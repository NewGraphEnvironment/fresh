# Classify Habitat for One Species

Copy a base stream network, apply pre-computed access barriers, then
classify spawning, rearing, and lake rearing habitat for a single
species. Each species gets its own output table because break points
modify segment geometry.

## Usage

``` r
frs_habitat_species(
  conn,
  species_code,
  base_tbl,
  breaks,
  breaks_habitat = NULL,
  params_sp,
  fresh_sp,
  to = NULL
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- species_code:

  Character. Uppercase species code (e.g. `"CO"`, `"BT"`).

- base_tbl:

  Character. Schema-qualified base table with the enriched stream
  network (from
  [`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md) +
  [`frs_col_join()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_join.md)).

- breaks:

  Character. Schema-qualified access breaks table from
  [`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md).

- breaks_habitat:

  Character or `NULL`. Schema-qualified habitat gradient breaks table.
  When provided, skips the per-species gradient scan and applies this
  pre-computed table instead. Default `NULL` computes on the fly.

- params_sp:

  Named list. Species parameters from
  [`frs_params()`](https://newgraphenvironment.github.io/fresh/reference/frs_params.md)
  (e.g. `frs_params()$CO`).

- fresh_sp:

  Data frame row. Species row from `parameters_fresh.csv` with
  `access_gradient_max`, `spawn_gradient_min`.

- to:

  Character or `NULL`. Output table name. Default `NULL` uses
  `working.streams_{sp}`.

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
[`frs_feature_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_find.md),
[`frs_feature_index()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_index.md),
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md),
[`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()
params <- frs_params(csv = system.file("extdata",
  "parameters_habitat_thresholds.csv", package = "fresh"))
fresh <- read.csv(system.file("extdata",
  "parameters_fresh.csv", package = "fresh"))

frs_habitat_species(conn, "CO", "working.streams_bulk",
  breaks = "working.breaks_access_bulk_015",
  breaks_habitat = "working.breaks_habitat_bulk_00549",
  params_sp = params$CO,
  fresh_sp = fresh[fresh$species_code == "CO", ],
  to = "working.streams_bulk_co")

DBI::dbDisconnect(conn)
} # }
```
