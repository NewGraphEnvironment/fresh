# Convert Columns to PostgreSQL Generated Columns from Geometry

Replace static columns with PostgreSQL `GENERATED ALWAYS` columns
derived from the table's LineStringZM geometry. After this, any
operation that modifies geometry (e.g.
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md))
will auto-recompute gradient, route measures, and length — no manual
recalculation needed.

## Usage

``` r
frs_col_generate(conn, table, geom_col = "geom")
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- table:

  Character. Schema-qualified working table name (from
  [`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)).

- geom_col:

  Character. Name of the geometry column. Default `"geom"`.

## Value

`conn` invisibly, for pipe chaining.

## Details

This mirrors the `bcfishpass.streams` table design where `gradient`,
`downstream_route_measure`, `upstream_route_measure`, and `length_metre`
are all `GENERATED ALWAYS AS (...)` from the geometry.

Converts these columns (drops if they exist, re-adds as generated):

- `gradient`:

  `round(((ST_Z(end) - ST_Z(start)) / ST_Length(geom))::numeric, 4)`

- `downstream_route_measure`:

  `ST_M(ST_PointN(geom, 1))`

- `upstream_route_measure`:

  `ST_M(ST_PointN(geom, -1))`

- `length_metre`:

  `ST_Length(geom)`

Requires LineStringZM geometry (Z for elevation, M for route measures).
FWA stream networks have this by default.

## See also

Other habitat:
[`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
[`frs_categorize()`](https://newgraphenvironment.github.io/fresh/reference/frs_categorize.md),
[`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md),
[`frs_col_join()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_join.md),
[`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md),
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md),
[`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md)

## Examples

``` r
# --- Why generated columns matter (bundled data) ---
# When you split a 500m segment at 10% average gradient, the two
# pieces have different actual gradients. Generated columns auto-compute
# the correct value from each piece's geometry.

d <- readRDS(system.file("extdata", "byman_ailport.rds", package = "fresh"))
streams <- d$streams

# FWA streams carry Z (elevation) and M (route measure) on every vertex
head(sf::st_coordinates(streams[1, ]))
#>             X       Y    Z         M L1
#> [1,] 990484.4 1062687 1270  58.03441  1
#> [2,] 990509.5 1062667 1270  89.87584  1
#> [3,] 990524.9 1062656 1270 108.99646  1

if (FALSE) { # \dontrun{
# --- Live DB: extract, generate, break ---
conn <- frs_db_conn()
aoi <- d$aoi

# 1. Extract FWA streams (static columns)
conn |> frs_extract(
  from = "whse_basemapping.fwa_stream_networks_sp",
  to = "working.demo_gen",
  aoi = aoi, overwrite = TRUE)

# 2. Convert to generated columns
conn |> frs_col_generate("working.demo_gen")

# 3. Break — gradient auto-recomputes on new segments
conn |> frs_break("working.demo_gen",
  attribute = "gradient", threshold = 0.08)

# Verify: all segments have gradient (no NULLs, all accurate)
result <- frs_db_query(conn,
  "SELECT gradient, geom FROM working.demo_gen")
summary(result$gradient)
plot(result["gradient"], main = "Gradient (auto-computed after break)")

# Clean up
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.demo_gen")
DBI::dbExecute(conn, "DROP TABLE IF EXISTS working.breaks")
DBI::dbDisconnect(conn)
} # }
```
