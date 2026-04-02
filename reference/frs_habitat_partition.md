# Prepare a Partition for Habitat Classification

Extract a stream network subset, enrich with channel width, and
pre-compute access and habitat gradient breaks. Returns a list of
species classification jobs ready for
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md).

## Usage

``` r
frs_habitat_partition(
  conn,
  aoi,
  label,
  species,
  params_all,
  params_fresh,
  source = "whse_basemapping.fwa_stream_networks_sp",
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- aoi:

  AOI specification passed to
  [`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md).
  Character watershed group code, `sf` polygon, named list, or `NULL`.

- label:

  Character. Short label for table naming (e.g. `"bulk"`,
  `"study_area"`). Used in table names like `working.streams_{label}`,
  `working.breaks_access_{label}_{thr}`.

- species:

  Data frame with columns `species_code`, `access_gradient`, and
  `spawn_gradient_max`. One row per species.

- params_all:

  Named list from
  [`frs_params()`](https://newgraphenvironment.github.io/fresh/reference/frs_params.md).

- params_fresh:

  Data frame from `parameters_fresh.csv`.

- source:

  Character. Source table for the stream network. Default
  `"whse_basemapping.fwa_stream_networks_sp"`.

- verbose:

  Logical. Print progress. Default `TRUE`.

## Value

A list with:

- jobs:

  List of job specs for
  [`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md)

- cleanup_tables:

  Character vector of intermediate table names

## Details

A partition is any spatial subset of a stream network — a watershed
group, a custom polygon, a study area. The function does not assume the
partition is a BC watershed group; that fish-specific lookup happens in
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
before calling this function.

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
[`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()
params_all <- frs_params(csv = system.file("extdata",
  "parameters_habitat_thresholds.csv", package = "fresh"))
params_fresh <- read.csv(system.file("extdata",
  "parameters_fresh.csv", package = "fresh"))

# Prepare BULK partition
species <- data.frame(
  species_code = c("CO", "BT"),
  access_gradient = c(0.15, 0.25),
  spawn_gradient_max = c(0.0549, 0.0549))

prep <- frs_habitat_partition(conn, aoi = "BULK", label = "bulk",
  species = species, params_all = params_all,
  params_fresh = params_fresh)

# Run one species from the prepared jobs
job <- prep$jobs[[1]]
frs_habitat_species(conn, job$species_code, job$base_tbl,
  breaks = job$acc_tbl, breaks_habitat = job$hab_tbl,
  params_sp = job$params_sp, fresh_sp = job$fresh_sp,
  to = job$to)

DBI::dbDisconnect(conn)
} # }
```
