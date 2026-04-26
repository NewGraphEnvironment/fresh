# Stitch known-habitat flags into a classified streams_habitat table

After
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
populates per-segment per-species habitat booleans from rules,
`frs_habitat_known()` ORs in additional TRUE flags from a wide-format
known-habitat table — capturing field observations / expert review /
manual additions that the rule-based classifier doesn't reach. Mirrors
the bcfishpass pipeline's blend of `habitat_linear_<sp>` (model) with
`streams_habitat_known` (knowns) into the published
`streams_habitat_linear`.

## Usage

``` r
frs_habitat_known(
  conn,
  table,
  known,
  species = NULL,
  habitat_types = c("spawning", "rearing", "lake_rearing", "wetland_rearing"),
  by = c("blue_line_key", "downstream_route_measure"),
  verbose = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- table:

  Character. Schema-qualified streams_habitat table to update in place.
  Must have columns `id_segment`, `species_code`, plus boolean columns
  named in `habitat_types`, plus the join keys in `by`.

- known:

  Character. Schema-qualified wide-format known-habitat table. Must have
  the join keys in `by`, plus per-species columns named
  `{habitat_type}_{species_lower}`.

- species:

  Character vector. Species codes to ingest. `NULL` (default) processes
  every species code present in `table`.

- habitat_types:

  Character vector. Habitat-type columns to OR in. Defaults to the four
  standard ones:
  `c("spawning", "rearing", "lake_rearing", "wetland_rearing")`. Must be
  a subset of the columns present in `table`.

- by:

  Character vector. Columns used to join `table` to `known`. Default
  `c("blue_line_key", "downstream_route_measure")`.

- verbose:

  Logical. Print per-species per-habitat summary. Default `TRUE`.

## Value

`conn` invisibly (for piping).

## Details

Known-habitat is **purely additive**: this function never sets a flag
from `TRUE` to `FALSE`. Callers wanting "known beats model" semantics
should preprocess the known table before calling.

Expects the known-habitat table to be wide-format with one row per
segment and a column per `{habitat_type}_{species_lower}` pair (e.g.
`spawning_sk`, `rearing_co`). Boolean or NULL. Missing columns are
skipped with a verbose message; they are not an error — many species
have known data only for certain habitat types.

Segments are matched between `table` and `known` using a join on the
columns named in `by` (default
`c("blue_line_key", "downstream_route_measure")`).

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
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md),
[`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
[`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md),
[`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# After frs_habitat_classify() populated working.streams_habitat,
# OR in known habitat from a CSV-loaded table.
frs_habitat_known(conn,
  table   = "working.streams_habitat",
  known   = "working.user_habitat_classification",
  species = c("CO", "SK", "CH"))
} # }
```
