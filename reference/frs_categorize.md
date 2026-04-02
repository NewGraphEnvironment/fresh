# Categorize Features by Priority-Ordered Boolean Columns

Collapse multiple boolean classification columns into a single
categorical column. The first `TRUE` column wins — order of `cols`
defines priority. Useful for mapping codes (QGIS categorized renderer),
reporting categories, and style registry integration (gq).

## Usage

``` r
frs_categorize(conn, table, label, cols, values, default = "NONE")
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- table:

  Character. Working schema table to update.

- label:

  Character. Column name for the categorical result.

- cols:

  Character vector. Boolean columns to check, in priority order. First
  `TRUE` wins.

- values:

  Character vector. Category values corresponding to each column in
  `cols`. Must be the same length as `cols`.

- default:

  Character. Value for rows where no column is `TRUE`. Default `"NONE"`.

## Value

`conn` invisibly, for pipe chaining.

## Details

Pipeable after
[`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md):

    conn |>
      frs_classify("working.streams", label = "co_spawning", ...) |>
      frs_classify("working.streams", label = "co_rearing", ...) |>
      frs_categorize("working.streams", label = "habitat_type",
        cols = c("co_spawning", "co_rearing", "accessible"),
        values = c("CO_SPAWNING", "CO_REARING", "ACCESSIBLE"),
        default = "INACCESSIBLE")

## See also

Other habitat:
[`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
[`frs_break()`](https://newgraphenvironment.github.io/fresh/reference/frs_break.md),
[`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
[`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
[`frs_break_validate()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_validate.md),
[`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md),
[`frs_col_generate()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_generate.md),
[`frs_col_join()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_join.md),
[`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md),
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md),
[`frs_habitat_access()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_access.md),
[`frs_habitat_partition()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_partition.md),
[`frs_habitat_species()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_species.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# After classifying habitat, collapse to a single mapping code
conn |>
  frs_categorize("working.streams",
    label = "habitat_type",
    cols = c("co_spawning", "co_rearing", "co_lake_rearing", "accessible"),
    values = c("CO_SPAWNING", "CO_REARING", "CO_LAKE_REARING", "ACCESSIBLE"),
    default = "INACCESSIBLE")

DBI::dbDisconnect(conn)
} # }
```
