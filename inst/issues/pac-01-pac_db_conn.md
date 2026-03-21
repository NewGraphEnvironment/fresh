## pac_db_conn

Connect to target PostgreSQL database using PG_*_SHARE env var pattern
(same as fresh). Returns a DBI connection object.

## pac_db_init

Ensure PostGIS extension exists. Create `pac` schema and `pac.load_log`
metadata table if they don't exist. Idempotent — safe to call repeatedly.

```r
conn <- pac_db_conn()
pac_db_init(conn)
```

## Implementation

- `R/pac_db_conn.R`
- `R/pac_db_init.R`
- `tests/testthat/test-pac_db_conn.R`
- `tests/testthat/test-pac_db_init.R`

## Dependencies

DBI, RPostgres
