# Classify Habitat for Multiple Species

Classify segments in a segmented stream network for one or more species.
Produces a long-format output table with one row per segment x species,
containing accessibility and habitat type booleans.

## Usage

``` r
frs_habitat_classify(
  conn,
  table,
  to,
  species,
  params = NULL,
  params_fresh = NULL,
  gate = TRUE,
  blocking_labels = "blocked",
  overwrite = TRUE,
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- table:

  Character. Schema-qualified segmented streams table (from
  [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)).

- to:

  Character. Schema-qualified output table for habitat classifications
  (e.g. `"fresh.streams_habitat"`).

- species:

  Character vector. Species codes to classify (e.g. `c("CO", "BT")`).

- params:

  Named list from
  [`frs_params()`](https://newgraphenvironment.github.io/fresh/reference/frs_params.md).
  Default reads from bundled CSV.

- params_fresh:

  Data frame from `parameters_fresh.csv`. Default reads from bundled
  CSV.

- gate:

  Logical. If `TRUE` (default), breaks restrict classification —
  segments downstream of blocking breaks are marked inaccessible. If
  `FALSE`, all segments are classified regardless of breaks (raw habitat
  potential).

- blocking_labels:

  Character vector. Labels that always block access. Default
  `"blocked"`. Gradient labels (`gradient_15`, etc.) are always
  threshold-aware regardless of this parameter. Set to
  `c("blocked", "potential")` for conservative analysis.

- overwrite:

  Logical. If `TRUE`, replace existing rows for these species in the
  output table. Default `TRUE`.

- verbose:

  Logical. Print progress. Default `TRUE`.

## Value

`conn` invisibly, for pipe chaining.

## Details

Requires a segmented streams table (from
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md))
with `id_segment`, gradient, channel width, and ltree columns, plus a
breaks table (`{streams_table}_breaks`) for accessibility checks.

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
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md),
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Assumes fresh.streams built by frs_network_segment() with
# gradient barriers labeled "gradient_15", "gradient_20", "gradient_25".
# See frs_network_segment() for the full setup.

# Classify CO, BT, ST — each gets species-specific accessibility.
# CO (15% access) is blocked by gradient_15, gradient_20, gradient_25.
# BT (25% access) is only blocked by gradient_25.
# Result: BT has ~2x the accessible habitat of CO on the same network.
frs_habitat_classify(conn,
  table = "fresh.streams",
  to = "fresh.streams_habitat",
  species = c("CO", "BT", "ST"))

# Query results — one table, all species, no geometry
DBI::dbGetQuery(conn, "
  SELECT species_code,
         count(*) FILTER (WHERE accessible) as accessible,
         count(*) FILTER (WHERE spawning) as spawning,
         count(*) FILTER (WHERE rearing) as rearing
  FROM fresh.streams_habitat
  GROUP BY species_code")

# Join geometry back for mapping — id_segment links the two tables
DBI::dbExecute(conn, "
  CREATE OR REPLACE VIEW fresh.streams_co_vw AS
  SELECT s.*, h.accessible, h.spawning, h.rearing, h.lake_rearing
  FROM fresh.streams s
  JOIN fresh.streams_habitat h ON s.id_segment = h.id_segment
  WHERE h.species_code = 'CO'")

# Re-running is safe — existing rows for these species are replaced.
# Run more WSGs later and both tables accumulate.

DBI::dbDisconnect(conn)
} # }
```
