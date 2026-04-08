# Run Habitat Pipeline

Orchestrate the full habitat pipeline: generate gradient access
barriers, segment the network via
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md),
classify habitat via
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md),
and persist results.

## Usage

``` r
frs_habitat(
  conn,
  wsg = NULL,
  aoi = NULL,
  species = NULL,
  label = NULL,
  to_streams = NULL,
  to_habitat = NULL,
  break_sources = NULL,
  gate = TRUE,
  label_block = "blocked",
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

  Character or `NULL`. One or more watershed group codes. When provided,
  species are auto-detected via
  [`frs_wsg_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_wsg_species.md).

- aoi:

  AOI specification or `NULL`. Overrides the spatial extent. Accepts
  anything
  [`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)
  handles: `sf` polygon, character WSG code, WHERE clause string, or
  named list. When `NULL` with `wsg`, uses the WSG polygon.

- species:

  Character or `NULL`. Species codes to classify (e.g. `c("CO", "BT")`).
  When `NULL` with `wsg`, auto-detected. Required when `wsg` is `NULL`.

- label:

  Character or `NULL`. Short label for working table names.
  Auto-generated from `wsg` when available. Required when `wsg` is
  `NULL` and `aoi` is provided.

- to_streams:

  Character or `NULL`. Schema-qualified table for persistent stream
  segments. Accumulates across runs.

- to_habitat:

  Character or `NULL`. Schema-qualified table for habitat
  classifications. Long format: one row per segment x species.

- break_sources:

  List of additional break source specs (falls, crossings, etc.), or
  `NULL`. Gradient access barriers are generated automatically from
  species parameters.

- workers:

  Integer. Number of parallel workers. Default `1`. Values \> 1 require
  the `mirai` package. Only used in WSG mode.

- password:

  Character. Database password for parallel workers.

- cleanup:

  Logical. Drop working tables when done. Default `TRUE`.

- verbose:

  Logical. Print progress. Default `TRUE`.

## Value

A data frame with columns `label`, `n_segments`, `n_species`,
`elapsed_s`.

## Details

Supports three modes:

- **WSG mode** (`wsg`): one or more watershed group codes. Species
  auto-detected. Parallelizes across WSGs.

- **Custom AOI** (`aoi` + `species`): any spatial extent with explicit
  species. For sub-basins, territories, or cross-WSG study areas.

- **WSG + custom AOI** (`wsg` + `aoi`): WSG for species lookup and table
  naming, custom AOI for spatial extent.

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

# WSG mode — species auto-detected
frs_habitat(conn, "BULK",
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat",
  break_sources = list(
    list(table = "working.falls", where = "barrier_ind = TRUE",
         label = "blocked")))

# Custom AOI — sub-basin via ltree filter
frs_habitat(conn,
  aoi = "wscode_ltree <@ '100.190442.999098'::ltree",
  species = c("BT", "CO"),
  label = "richfield",
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat")

# WSG + custom AOI — WSG for species, polygon for extent
frs_habitat(conn, "ADMS",
  aoi = my_study_area_polygon,
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat")

# Multiple WSGs, parallel
frs_habitat(conn, c("BULK", "MORR", "ZYMO"),
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat",
  workers = 4, password = "postgres",
  break_sources = list(
    list(table = "working.falls", label = "blocked")))

DBI::dbDisconnect(conn)
} # }
```
