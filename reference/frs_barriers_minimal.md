# Reduce Barriers to Downstream-Most Per Flow Path

Given a point table on an FWA stream network, remove any points that
have another point from the same table downstream of them on the same
upstream flow path. The result is the minimal set of points needed to
define access blocking per reach — equivalent to bcfishpass's
"non-minimal removal" step.

## Usage

``` r
frs_barriers_minimal(
  conn,
  from,
  to = "working.barriers_minimal",
  tolerance = 1,
  overwrite = TRUE
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object (from
  [`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)).

- from:

  Character. Source table (schema-qualified) with barrier points. Must
  contain `blue_line_key`, `downstream_route_measure`, `wscode_ltree`,
  and `localcode_ltree` columns. Enrich with ltree columns via
  [`frs_col_join()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_join.md)
  if needed.

- to:

  Character. Destination table for minimal barriers. Default
  `"working.barriers_minimal"`.

- tolerance:

  Numeric. Tolerance in metres when comparing positions on the same
  reach. Default `1` — two points within 1 m on the same `blue_line_key`
  are treated as coincident and both are kept. Matches bcfishpass
  convention; prevents near-coincident gradient barriers (different
  gradient classes at the same vertex) from cancelling each other out.

- overwrite:

  Logical. If `TRUE` (default), drop `to` before creating.

## Value

`conn` invisibly, for pipe chaining.

## Details

On a full watershed group this typically reduces ~27,000 raw gradient
barriers to ~700 downstream-most per reach. Once the downstream-most
barrier on a path is present, any barrier upstream of it is redundant
for access-blocking purposes.

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# Typical pipeline: detect gradient barriers, enrich with ltree cols,
# then reduce to the minimal set for segmentation.
frs_break_find(conn,
  table     = "whse_basemapping.fwa_stream_networks_sp",
  to        = "working.barriers_raw",
  attribute = "gradient",
  classes   = c("15" = 0.15, "20" = 0.20, "25" = 0.25, "30" = 0.30))

frs_col_join(conn, "working.barriers_raw",
  from = "whse_basemapping.fwa_stream_networks_sp",
  cols = c("wscode_ltree", "localcode_ltree"),
  by   = "blue_line_key")

n_before <- DBI::dbGetQuery(conn,
  "SELECT count(*) FROM working.barriers_raw")[[1]]

frs_barriers_minimal(conn,
  from = "working.barriers_raw",
  to   = "working.barriers_minimal")

n_after <- DBI::dbGetQuery(conn,
  "SELECT count(*) FROM working.barriers_minimal")[[1]]

message("Reduced ", n_before, " -> ", n_after, " barriers (",
        round(100 * (1 - n_after / n_before)), "% removed)")

DBI::dbDisconnect(conn)
} # }
```
