# Query FWA PostgreSQL Database

Connects via
[`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md),
executes a SQL query, disconnects, and returns the result. Uses
[`sf::st_read()`](https://r-spatial.github.io/sf/reference/st_read.html)
so spatial columns are returned as sf geometry.

## Usage

``` r
frs_db_query(query, ...)
```

## Arguments

- query:

  Character. SQL query string.

- ...:

  Additional arguments passed to
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md).

## Value

An `sf` data frame (if the query returns geometry) or a plain data
frame.

## See also

Other database:
[`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)

## Examples

``` r
if (FALSE) { # \dontrun{
frs_db_query("SELECT * FROM whse_basemapping.fwa_lakes_poly LIMIT 5")
} # }
```
