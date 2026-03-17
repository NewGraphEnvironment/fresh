# Query FWA PostgreSQL Database

Executes a SQL query on an open connection. Uses
[`sf::st_read()`](https://r-spatial.github.io/sf/reference/st_read.html)
so spatial columns are returned as sf geometry.

## Usage

``` r
frs_db_query(conn, query)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- query:

  Character. SQL query string.

## Value

An `sf` data frame (if the query returns geometry) or a plain data
frame.

## See also

Other database:
[`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()
frs_db_query(conn, "SELECT * FROM whse_basemapping.fwa_lakes_poly LIMIT 5")
DBI::dbDisconnect(conn)
} # }
```
