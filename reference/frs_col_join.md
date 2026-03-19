# Join Columns from a Lookup Table onto a Working Table

Add columns from any lookup table to a working table via SQL
`UPDATE ... SET ... FROM`. This is the generic enrichment step in the
habitat pipeline — join channel width for intrinsic potential, upstream
area and precipitation for flooded's bankfull regression, or any custom
model output.

## Usage

``` r
frs_col_join(conn, table, from, cols, by = "linear_feature_id")
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- table:

  Character. Schema-qualified working table to enrich.

- from:

  Character. Source table (or subquery wrapped in parentheses)
  containing the columns to join.

- cols:

  Character vector. Column names to add from the source table.

- by:

  Character vector. Join key(s). Unnamed elements match the same column
  in both tables. Named elements map working table column (name) to
  source column (value): `c(linear_feature_id = "lid")`. Default
  `"linear_feature_id"`.

## Value

`conn` invisibly, for pipe chaining.

## Details

Pipeable between
[`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)
and
[`frs_col_generate()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_generate.md):

    conn |>
      frs_extract(...) |>
      frs_col_join("working.streams",
        from = "fwa_stream_networks_channel_width",
        cols = c("channel_width", "channel_width_source"),
        by = "linear_feature_id") |>
      frs_col_generate("working.streams")

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
[`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Channel width — direct join by linear_feature_id
conn |>
  frs_col_join("working.streams",
    from = "fwa_stream_networks_channel_width",
    cols = c("channel_width", "channel_width_source"),
    by = "linear_feature_id")

# MAD (mean annual discharge) — same pattern
conn |>
  frs_col_join("working.streams",
    from = "fwa_stream_networks_discharge",
    cols = "mad_m3s",
    by = "linear_feature_id")

# Upstream area — two-hop join via subquery
conn |>
  frs_col_join("working.streams",
    from = "(SELECT l.linear_feature_id, ua.upstream_area_ha
             FROM fwa_streams_watersheds_lut l
             JOIN fwa_watersheds_upstream_area ua
               ON l.watershed_feature_id = ua.watershed_feature_id) sub",
    cols = "upstream_area_ha",
    by = "linear_feature_id")

# MAP (mean annual precipitation) — composite key
conn |>
  frs_col_join("working.streams",
    from = "fwa_stream_networks_mean_annual_precip",
    cols = "map_upstream",
    by = c("wscode_ltree", "localcode_ltree"))

DBI::dbDisconnect(conn)
} # }
```
