## pac_load

The core function. Load from any source into a PostgreSQL table. Detects
source type, applies filters, writes to target table, builds indexes,
and records the load in `pac.load_log`.

```r
# S3 parquet with attribute filter
pac_load(conn, "s3://bucket/fwa_streams.parquet",
         target = "whse_basemapping.fwa_stream_networks_sp",
         filter_attr = list(watershed_group_code = c("BULK", "MORR")))

# Local geopackage with spatial filter and layer selection
pac_load(conn, "/data/field_2025.gpkg",
         target = "working.crossings",
         layer = "crossings",
         filter_spatial = sf::st_bbox(aoi))

# Another pg instance
pac_load(conn, source_conn,
         source_table = "public.stations",
         target = "working.stations")
```

## Parameters

- `conn` — DBI connection to target database
- `source` — path, URI, or DBI connection to source
- `target` — schema-qualified target table name (e.g., "working.streams")
- `layer` — layer name for multi-layer sources (gpkg, fgdb). NULL = first layer
- `filter_attr` — named list of column = value(s) for attribute filtering
- `filter_spatial` — bbox or sf polygon for spatial filtering
- `source_table` — table name when source is a pg connection
- `indexes` — character vector of columns to index, or NULL for auto-detect
  (always indexes geometry columns with GiST)
- `overwrite` — logical, default TRUE. Drop and recreate if target exists
- `append` — logical, default FALSE. If TRUE, append to existing table
  (overrides overwrite)

## Internal Flow

1. `pac_source_detect(source)` → source type
2. Dispatch to reader: `pac_read_s3_parquet()`, `pac_read_gpkg()`, etc.
3. Apply filters at read time where possible (arrow predicate pushdown,
   sf wkt_filter, SQL WHERE)
4. `sf::st_write()` or `DBI::dbWriteTable()` to target
5. `pac_index_build()` on target
6. Insert row into `pac.load_log`

## Implementation

- `R/pac_load.R`
- `R/pac_read_parquet.R` (internal)
- `R/pac_read_sf.R` (internal)
- `R/pac_read_pg.R` (internal)
- `tests/testthat/test-pac_load.R`

## Dependencies

DBI, RPostgres, sf, arrow
