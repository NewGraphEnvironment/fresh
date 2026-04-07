# Segment a Stream Network at Break Points

Build a segmented stream network by extracting base streams, enriching
with channel width, and splitting at break points from any number of
sources. Assigns a unique `id_segment` to each sub-segment.

## Usage

``` r
frs_network_segment(
  conn,
  aoi,
  to,
  source = "whse_basemapping.fwa_stream_networks_sp",
  break_sources = NULL,
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

- aoi:

  AOI specification passed to
  [`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md).
  Character watershed group code, `sf` polygon, or `NULL`.

- to:

  Character. Schema-qualified output table name (e.g.
  `"fresh.streams"`).

- source:

  Character. Source table for the stream network. Default
  `"whse_basemapping.fwa_stream_networks_sp"`.

- break_sources:

  List of break source specs, or `NULL` (no breaking). Each spec is a
  list with `table`, and optionally `where`, `label`, `label_col`,
  `label_map`, `col_blk`, `col_measure`. See
  [`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md)
  for details.

- overwrite:

  Logical. If `TRUE`, drop `to` before creating. Default `TRUE`.

- verbose:

  Logical. Print progress. Default `TRUE`.

## Value

`conn` invisibly, for pipe chaining.

## Details

This function is domain-agnostic — it segments a network at points
without knowing what those points represent. Use
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md)
to generate gradient barriers, then pass the result as a break source
alongside falls, crossings, or any other point table.

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
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# --- Full workflow: barriers → segment → classify ---
#
# Species codes: CO = Coho, CH = Chinook, SK = Sockeye,
#   ST = Steelhead, BT = Bull Trout, RB = Rainbow Trout

# 1. Generate gradient access barriers at each species threshold.
#    CO/CH/SK can't pass 15%, ST can't pass 20%, BT/RB can't pass 25%.
#    Thresholds come from parameters_fresh.csv (access_gradient_max).
#    frs_break_find needs an extracted network table to get BLK list.
frs_extract(conn,
  from = "whse_basemapping.fwa_stream_networks_sp",
  to = "working.tmp_bulk",
  where = "watershed_group_code = 'BULK'")

frs_break_find(conn, "working.tmp_bulk",
  attribute = "gradient", threshold = 0.15,
  to = "working.barriers_15")
frs_break_find(conn, "working.tmp_bulk",
  attribute = "gradient", threshold = 0.20,
  to = "working.barriers_20")
frs_break_find(conn, "working.tmp_bulk",
  attribute = "gradient", threshold = 0.25,
  to = "working.barriers_25")

# 2. Segment the network at ALL barrier points + falls.
#    One table, one copy of geometry, shared across all species.
#    Labels control which species each barrier blocks — gradient_15
#    blocks CO but not BT; gradient_25 blocks both.
#    Falls (from inst/extdata/falls.csv, loaded to working.falls)
#    block all species.
frs_network_segment(conn, aoi = "BULK",
  to = "fresh.streams",
  break_sources = list(
    list(table = "working.barriers_15", label = "gradient_15"),
    list(table = "working.barriers_20", label = "gradient_20"),
    list(table = "working.barriers_25", label = "gradient_25"),
    list(table = "working.falls",
         where = "barrier_ind = TRUE", label = "blocked")
  ))

# 3. Classify habitat — see frs_habitat_classify() for details.
#    Writes to fresh.streams_habitat (long format, no geometry).
#    id_segment links back to fresh.streams for mapping.
frs_habitat_classify(conn,
  table = "fresh.streams",
  to = "fresh.streams_habitat",
  species = c("CO", "BT", "ST"))

# Check results
DBI::dbGetQuery(conn, "
  SELECT species_code,
         count(*) FILTER (WHERE accessible) as accessible,
         count(*) FILTER (WHERE spawning) as spawning
  FROM fresh.streams_habitat
  GROUP BY species_code")

DBI::dbDisconnect(conn)
} # }
```
