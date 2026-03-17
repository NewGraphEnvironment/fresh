# Validate Breaks Against Upstream Evidence

Filter break points by checking for upstream evidence. For each break,
counts rows in `evidence_table` that are upstream on the same
`blue_line_key`. Breaks with count \>= `count_threshold` are removed.

## Usage

``` r
frs_break_validate(
  conn,
  breaks,
  evidence_table,
  where = NULL,
  count_threshold = 1L
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- breaks:

  Character. Table name containing break points with `blue_line_key` and
  `downstream_route_measure` columns.

- evidence_table:

  Character. Schema-qualified table with evidence features. Must have
  `blue_line_key` and `downstream_route_measure` columns.

- where:

  Character or `NULL`. SQL predicate to filter the evidence table
  (without leading AND/WHERE). Column references use alias `e`.
  Examples: `"e.species_code IN ('CO','CH')"`,
  `"e.observation_date >= '1990-01-01'"`.

- count_threshold:

  Integer. Minimum upstream evidence count to remove a break. Default
  `1` (any evidence removes the break).

## Value

`conn` invisibly, for pipe chaining.

## Details

This is generic — the evidence table can contain any point features with
`blue_line_key` and `downstream_route_measure` columns (fish
observations, water quality stations, SAR sightings, etc.). Use `where`
to filter the evidence to relevant records.

## See also

Other habitat:
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
[`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Remove gradient breaks where coho or chinook were observed upstream
conn |>
  frs_break_validate("working.breaks",
    evidence_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
    where = "e.species_code IN ('CO', 'CH')")

# Remove breaks with 5+ recent observations of any species upstream
conn |>
  frs_break_validate("working.breaks",
    evidence_table = "bcfishobs.fiss_fish_obsrvtn_events_vw",
    where = "e.observation_date >= '1990-01-01'",
    count_threshold = 5)

# Generic: validate against any point evidence table
conn |>
  frs_break_validate("working.breaks",
    evidence_table = "working.water_quality_sites",
    where = "e.conductivity > 100")

DBI::dbDisconnect(conn)
} # }
```
