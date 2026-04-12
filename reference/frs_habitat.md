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
  breaks_gradient = NULL,
  gate = TRUE,
  label_block = "blocked",
  rules = NULL,
  gradient_recompute = TRUE,
  measure_precision = 0L,
  barrier_overrides = NULL,
  params = NULL,
  params_fresh = NULL,
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

- breaks_gradient:

  Numeric vector or `NULL`. Extra gradient thresholds at which to break
  the network for sub-segment resolution (in addition to species access
  thresholds, which are always generated). Three modes:

  - `NULL` (default) — auto-derive from `spawn_gradient_max` and
    `rear_gradient_max` in `params`. Captures every biologically
    meaningful threshold for the species being classified.

  - Numeric vector — explicit list (e.g. `c(0.06, 0.12)`). Replaces
    auto-derivation.

  - `numeric(0)` — disable extras. Only access thresholds are generated
    (the fresh 0.9.0 behavior).

  Auto-derived breaks give cluster analysis
  ([`frs_cluster()`](https://newgraphenvironment.github.io/fresh/reference/frs_cluster.md))
  the gradient resolution to detect within-segment steep sections that
  would otherwise be hidden by averaging.

- rules:

  Character path to a habitat rules YAML, `FALSE`, or `NULL`. Default
  `NULL` uses the bundled `inst/extdata/parameters_habitat_rules.yaml`.
  Pass a path string to load a custom rules file (e.g. one shipped by
  the `link` package). Pass `FALSE` to disable rules entirely and use
  only the CSV ranges path (the pre-0.12.0 behavior).

  Only consulted when `params = NULL`. If you pass your own `params`
  from
  [`frs_params()`](https://newgraphenvironment.github.io/fresh/reference/frs_params.md),
  the rules are baked into that object and `rules` here is ignored.

  See
  [`frs_params()`](https://newgraphenvironment.github.io/fresh/reference/frs_params.md)
  for the rules format.

- gradient_recompute:

  Logical. If `TRUE` (default), recompute gradient from DEM vertices
  after splitting segments. If `FALSE`, child segments inherit the
  parent gradient. See
  [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)
  for details.

- barrier_overrides:

  Character or `NULL`. Schema-qualified table of barrier overrides
  prepared by link via `lnk_barrier_overrides()`. Must have columns
  `blue_line_key`, `downstream_route_measure`, `species_code`. When
  provided, matched barriers are excluded from per-species access
  gating. Default `NULL` (no overrides).

- params:

  Named list from
  [`frs_params()`](https://newgraphenvironment.github.io/fresh/reference/frs_params.md),
  or `NULL` to use bundled `parameters_habitat_thresholds.csv` and rules
  YAML.

- params_fresh:

  Data frame from `parameters_fresh.csv`, or `NULL` to use bundled
  default.

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
[`frs_cluster()`](https://newgraphenvironment.github.io/fresh/reference/frs_cluster.md),
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

# Custom parameters — project-specific thresholds override bundled
# defaults. Use when species have different gradient/channel width
# ranges for your study area, or when adding species not in the
# default parameter set.
frs_habitat(conn, "BULK",
  params = frs_params(csv = "path/to/my_thresholds.csv"),
  params_fresh = read.csv("path/to/my_fresh_params.csv"),
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat")

# --- Custom habitat rules YAML ---

# Default: ships parameters_habitat_rules.yaml with NGE-derived
# multi-rule species (SK lake-only, CO wetland carve-out, all
# anadromous waterbody_type=R spawn). Behavior matches what
# consumers like the `link` package expect.

# Custom rules from a project: pass a path string
frs_habitat(conn, "BULK",
  rules = "path/to/project_habitat_rules.yaml",
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat")

# Disable rules entirely (pre-0.12.0 behavior — only CSV ranges)
frs_habitat(conn, "BULK",
  rules = FALSE,
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat")

# --- Controlling gradient resolution with breaks_gradient ---

# Default: auto-derive breaks from spawn_gradient_max +
# rear_gradient_max in params. For BULK with CO/BT/ST that's
# roughly: 0.0449, 0.0549, 0.0849, 0.1049 plus access (0.15, 0.20,
# 0.25). Every biologically meaningful threshold is captured.
# Recommended — gives frs_cluster() the resolution to find
# within-segment steep sections.
frs_habitat(conn, "BULK",
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat")

# Custom override: explicit list. Use when you have project-specific
# gradient thresholds (e.g. local channel-type classification scheme)
# that aren't tied to a species threshold.
frs_habitat(conn, "BULK",
  breaks_gradient = c(0.03, 0.06, 0.10, 0.15),
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat")

# Disable extras: only species access thresholds (15/20/25). Faster
# but coarser — fresh 0.9.0 behavior. Not recommended unless you
# specifically don't want sub-segment gradient resolution.
frs_habitat(conn, "BULK",
  breaks_gradient = numeric(0),
  to_streams = "fresh.streams",
  to_habitat = "fresh.streams_habitat")

DBI::dbDisconnect(conn)
} # }
```
