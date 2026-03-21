## pac_source_detect

Identify source type from a path or URI string. Returns a string
classification used by `pac_load()` to dispatch to the right reader.

```r
pac_source_detect("s3://bucket/data.parquet")
#> "s3_parquet"

pac_source_detect("/data/field.gpkg")
#> "local_gpkg"

pac_source_detect("PG:dbname=source_db")
#> "pg_table"

pac_source_detect("https://example.com/data.gdb.zip")
#> "url_zip"
```

## Classification Rules

Priority order (first match wins):

1. Starts with `s3://` → check extension: `.parquet` = `s3_parquet`,
   `.gpkg` = `s3_gpkg`, `.shp` = `s3_shp`
2. Starts with `PG:` or is a DBI connection → `pg_table`
3. Starts with `http://` or `https://` → check extension for `.zip` =
   `url_zip`, else `url_direct`
4. Local file → check extension: `.gpkg`, `.shp`, `.fgdb`/`.gdb`,
   `.csv`, `.parquet`, `.sql` (pg_dump)
5. No match → error with helpful message listing supported formats

## Implementation

- `R/pac_source_detect.R`
- `tests/testthat/test-pac_source_detect.R`

## Dependencies

None (base R string operations)
