# Connect to FWA PostgreSQL Database

Opens a connection to a PostgreSQL database containing fwapg,
bcfishpass, and bcfishobs. Connection parameters default to environment
variables matching the `PG_*_SHARE` convention used by fpr.

## Usage

``` r
frs_db_conn(
  dbname = Sys.getenv("PG_DB_SHARE"),
  host = Sys.getenv("PG_HOST_SHARE"),
  port = Sys.getenv("PG_PORT_SHARE"),
  user = Sys.getenv("PG_USER_SHARE"),
  password = Sys.getenv("PG_PASS_SHARE")
)
```

## Arguments

- dbname:

  Database name. Default: `Sys.getenv("PG_DB_SHARE")`.

- host:

  Host name. Default: `Sys.getenv("PG_HOST_SHARE")`.

- port:

  Port number. Default: `Sys.getenv("PG_PORT_SHARE")`.

- user:

  User name. Default: `Sys.getenv("PG_USER_SHARE")`.

- password:

  Password. Default: `Sys.getenv("PG_PASS_SHARE")`.

## Value

A
[DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
object.

## See also

Other database:
[`frs_db_query()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_query.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()
DBI::dbDisconnect(conn)
} # }
```
