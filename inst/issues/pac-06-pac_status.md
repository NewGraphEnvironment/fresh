## pac_status

List all tables loaded by pac with summary info. Queries `pac.load_log`
and cross-references with actual database state.

```r
pac_status(conn)
#> # A tibble: 3 x 5
#>   target_table                                source_uri                    rows loaded_at            source_type
#>   <chr>                                       <chr>                        <int> <dttm>               <chr>
#> 1 whse_basemapping.fwa_stream_networks_sp      s3://bucket/fwa/streams.pq  45000 2026-03-21 10:30:00  s3_parquet
#> 2 working.field_crossings                      /data/field_2025.gpkg         127 2026-03-21 10:31:00  local_gpkg
#> 3 bcfishpass.barriers_anthropogenic            s3://bucket/bcfishpass/b.pq  3200 2026-03-21 10:32:00  s3_parquet
```

## pac_log

Detailed load history including filters applied, index operations, and
timing. Useful for debugging and auditing.

```r
pac_log(conn, target = "working.field_crossings")
#> Load history for working.field_crossings:
#>   2026-03-21 10:31:00 — loaded 127 rows from /data/field_2025.gpkg
#>     filter_spatial: BBOX(1100000, 700000, 1200000, 800000)
#>     indexes: geom (gist)
#>   2026-03-15 09:00:00 — loaded 95 rows from /data/field_2025_draft.gpkg
#>     overwritten by later load
```

## Implementation

- `R/pac_status.R`
- `R/pac_log.R`
- `tests/testthat/test-pac_status.R`

## Dependencies

DBI, RPostgres
