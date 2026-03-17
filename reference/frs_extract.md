# Stage Data to Working Schema

Copy rows from a read-only source table into a writable working schema
table via `CREATE TABLE AS SELECT`. The working copy can then be
modified by `frs_break_apply()`, `frs_classify()`, and
`frs_aggregate()`.

## Usage

``` r
frs_extract(conn, from, to, cols = NULL, aoi = NULL, overwrite = FALSE)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- from:

  Character. Schema-qualified source table (e.g.
  `"bcfishpass.streams_co_vw"`).

- to:

  Character. Schema-qualified destination table (e.g.
  `"working.streams_co"`).

- cols:

  Character vector of column names to select, or `NULL` for all columns
  (`SELECT *`).

- aoi:

  AOI specification passed to `.frs_resolve_aoi()`. One of:

  - `NULL` — no spatial filter (copy all rows)

  - Character vector — watershed group code(s)

  - `sf`/`sfc` polygon — spatial intersection

  - Named list — see `.frs_resolve_aoi()` for details

- overwrite:

  Logical. If `TRUE`, drop the destination table before creating. If
  `FALSE` (default), error when the table already exists.

## Value

`conn` invisibly, for pipe chaining.

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Extract coho streams for Bulkley watershed group
conn |> frs_extract(
  from = "bcfishpass.streams_co_vw",
  to = "working.streams_co",
  aoi = "BULK"
)

# Extract specific columns with overwrite
conn |> frs_extract(
  from = "bcfishpass.streams_co_vw",
  to = "working.streams_co",
  cols = c("segmented_stream_id", "blue_line_key", "gradient",
           "channel_width", "geom"),
  aoi = "BULK",
  overwrite = TRUE
)

DBI::dbDisconnect(conn)
} # }
```
