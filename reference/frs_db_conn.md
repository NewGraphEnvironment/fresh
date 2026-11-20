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
  password = NULL,
  connect_timeout = NULL,
  ...
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

- connect_timeout:

  Seconds libpq waits for each connection attempt, a whole number; `0`
  waits without limit. Default `NULL`: libpq reads `PGCONNECT_TIMEOUT`
  when it is set, otherwise 10. See Timeouts.

- ...:

  Further libpq connection keywords, passed to
  [`DBI::dbConnect()`](https://dbi.r-dbi.org/reference/dbConnect.html).
  A keyword given here replaces the default of the same name
  (`keepalives = 0` turns keepalives off), and `NULL` removes it,
  leaving the value to libpq and the operating system.

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

## Timeouts

libpq waits without limit by default, so a host that stops answering
blocks the call instead of raising an error. `frs_db_conn()` bounds both
waits, so a silent host fails the same way a refusing one does:

- **Connecting.** `connect_timeout` seconds per host address tried
  (libpq counts each address, and treats 1 as 2). Resolved like the
  other fields: the argument, then `PGCONNECT_TIMEOUT`, then 10.

- **An established connection that goes silent.** TCP keepalives
  (`keepalives_idle = 60`, `keepalives_interval = 10`,
  `keepalives_count = 6`) drop a dead peer in about two minutes rather
  than the operating system's default of about two hours.

A long-running query is not bounded: the server keeps answering
keepalives and acknowledging data while it works. Bound statements with
a server-side `statement_timeout` if you need to.

Limits of these bounds:

- Keepalives probe only a connection with nothing in flight. Once a
  query has been sent and not acknowledged, the operating system's
  retransmission timeout applies instead. On Linux, pass
  `tcp_user_timeout` (milliseconds) in `...` to shorten it. It is not a
  default: libpq knows the keyword only from PostgreSQL 12, refuses it
  before that, and applies it only where the system supports
  `TCP_USER_TIMEOUT`.

- Through a local tunnel (an SSH port forward, say), keepalives and
  acknowledgements come from the local end of the tunnel, so only the
  connect is bounded; a remote end that dies after connecting is
  detected by the tunnel's own settings, if at all.

- None of them apply to a Unix-domain socket.

- Keywords passed here take precedence over the same keywords in a
  `PGSERVICE` service file. Pass `NULL` in `...` to defer to the file
  for a keepalive keyword, or give `connect_timeout` explicitly.

## See also

Other database:
[`frs_db_query()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_query.md),
[`frs_migration_trial()`](https://newgraphenvironment.github.io/fresh/reference/frs_migration_trial.md)

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

# A slow link: wait longer to connect
conn <- frs_db_conn(connect_timeout = 30)
DBI::dbDisconnect(conn)
} # }
```
