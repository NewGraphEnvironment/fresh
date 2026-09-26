# Connect to FWA PostgreSQL Database

Opens a connection to a PostgreSQL database containing fwapg (and
optionally bcfishpass / bcfishobs). Connection parameters follow the
standard libpq conventions, so `frs_db_conn()` connects to whatever the
caller's environment points at, e.g. the local fwapg Docker database in
`docker/`, or a remote host.

## Usage

``` r
frs_db_conn(
  dbname = NULL,
  host = NULL,
  port = NULL,
  user = NULL,
  password = NULL
)
```

## Arguments

- dbname:

  Database name. Default `NULL` (resolved as above).

- host:

  Host name. Default `NULL`.

- port:

  Port number. Default `NULL`.

- user:

  User name. Default `NULL`.

- password:

  Password. Default `NULL`.

## Value

A
[DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
object.

## Details

Parameters resolve in this order:

1.  Explicit arguments, field by field.

2.  Standard libpq environment variables (`PGHOST`, `PGPORT`,
    `PGDATABASE`, `PGUSER`, `PGPASSWORD`, `PGSERVICE`, ...). If any of
    `PGHOST`, `PGHOSTADDR`, `PGPORT`, `PGDATABASE`, `PGUSER` or
    `PGSERVICE` is set, libpq resolves the unset fields itself and the
    legacy variables below are ignored.

3.  Legacy `PG_*_SHARE` variables (`PG_DB_SHARE`, `PG_HOST_SHARE`,
    `PG_PORT_SHARE`, `PG_USER_SHARE`, `PG_PASS_SHARE`), used only when
    none of the standard variables are set. Deprecated: a message is
    shown once per session.

4.  libpq defaults (local socket or `localhost`, OS user name,
    `~/.pgpass`, `~/.pg_service.conf`).

The two variable groups are never mixed, so a legacy database name can
not be paired with a standard host.

## See also

Other database:
[`frs_db_query()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_query.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Standard libpq env vars, e.g. in ~/.Renviron:
#   PGHOST=localhost PGPORT=5432 PGDATABASE=fwapg PGUSER=postgres
conn <- frs_db_conn()
DBI::dbDisconnect(conn)

# Explicit arguments override the environment per field
conn <- frs_db_conn(port = 63333, dbname = "bcfishpass")
DBI::dbDisconnect(conn)
} # }
```
