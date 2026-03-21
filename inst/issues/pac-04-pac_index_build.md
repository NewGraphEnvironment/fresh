## pac_index_build

Build spatial and attribute indexes on a PostgreSQL table. Called
automatically by `pac_load()` after writing data. Available standalone
for existing tables that need indexing.

```r
# Auto-detect geometry column, add GiST
pac_index_build(conn, "working.streams")

# Explicit: GiST on geom + btree on two columns
pac_index_build(conn, "working.streams",
                columns = c("geom", "route_id", "watershed_code"))
```

## Behavior

- If `columns` is NULL, introspect the table for geometry columns and
  build GiST indexes on each
- For non-geometry columns in `columns`, build btree indexes
- Index names follow pattern: `idx_{table}_{column}_{type}`
- Uses `CREATE INDEX IF NOT EXISTS` — safe to call repeatedly
- Uses `CONCURRENTLY` when possible (not inside a transaction)

## Implementation

- `R/pac_index_build.R`
- `tests/testthat/test-pac_index_build.R`

## Dependencies

DBI, RPostgres
