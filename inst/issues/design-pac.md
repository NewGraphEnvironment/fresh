## Abstract

**pac** — Portable Archive Connector — is a reproducible spatial data loader
for PostgreSQL. It reads from any source (S3 parquet, geopackage, shapefile,
FGDB, pg_dump, another PostgreSQL instance), writes to PostGIS tables, builds
indexes, and records every load as a reproducible recipe. Run the recipe on a
new machine and get an identical database.

pac is **network-agnostic**. It knows nothing about streams, watersheds, fish,
or FWA. It knows about sources, targets, filters, and indexes. It sits below
spyda, fresh, and bcfishpass — any of them can use pac to populate their
database, but pac doesn't know or care what the data represents.

```
pac (load data into pg) → spyda (build network topology)
pac (load data into pg) → fresh (query spatial data)
pac (load data into pg) → any pg-backed workflow
```

## Why Not Just sf::st_write()?

`sf::st_write()` handles any single load. But real projects need:

1. **Multi-source dispatch** — parquet on S3, geopackage on disk, another pg
   instance all handled by one function that detects the source type
2. **Filtered loading** — spatial (bbox/polygon) and attribute filters applied
   at read time, not after pulling everything into R
3. **Post-load indexing** — spatial GiST, btree on key columns, built
   automatically based on what was loaded
4. **Recipe/manifest** — YAML record of what was loaded, from where, with what
   filters. Reproducible database rebuild from a single file
5. **Status tracking** — what's in the database, when was it loaded, from what
   source

No existing R package combines all five. `sf` does 1 partially. `rpostgis`
does 3 partially. `etl` does 4 for public datasets only. `rdataretriever`
does 4-5 but for curated ecology data, not arbitrary spatial sources.

## Existing Landscape

| Package | Overlap with pac | Gap |
|---------|-----------------|-----|
| sf | Read/write any format via GDAL | No recipes, no index mgmt |
| rpostgis | PostGIS convenience wrappers | No multi-source, no recipes |
| etl | Reproducible ETL verbs | Not spatial-first, public data only |
| rdataretriever | Recipes + PostGIS + snapshots | Curated public datasets only |
| arrow/geoarrow | Fast parquet reads | Just a format reader |
| gdalUtils | ogr2ogr wrapper | No state tracking |
| Geocint (Python) | DAG spatial ETL on PostGIS | Python, enterprise-scale |

## Design Principles

1. **One function to load anything** — `pac_load()` detects source type and
   dispatches to the right reader (sf, arrow, DBI)
2. **Filter at source** — never pull 50GB into R to filter to 500MB. Push
   spatial/attribute filters down to the reader
3. **Indexes are part of the load** — pac knows what indexes to build based on
   geometry columns and user-specified key columns
4. **Recipe is the product** — the YAML manifest is more valuable than any
   single load. It's a reproducible database specification
5. **No domain knowledge** — pac doesn't know what FWA is, what a blue_line_key
   means, or what species a table contains. It loads spatial data into pg.
   Period.

## Proposed Function Surface

All exported functions prefixed `pac_`, noun-first.

### Core loading
- `pac_load()` — load from any source into a pg table. Detects source type,
  applies filters, writes to target, builds indexes, records to manifest
- `pac_source_detect()` — identify source type from path/URI (s3 parquet,
  local gpkg, local shp, pg connection, url, etc.)

### Filtering
- `pac_filter_spatial()` — construct spatial filter (bbox or polygon)
- `pac_filter_attr()` — construct attribute filter (column = value pairs)

### Indexing
- `pac_index_build()` — build spatial GiST + attribute btree indexes on a
  loaded table. Called automatically by `pac_load()`, available standalone
  for existing tables

### Recipe management
- `pac_recipe_save()` — serialize current database manifest to YAML
- `pac_recipe_run()` — rebuild database from a recipe YAML file
- `pac_recipe_diff()` — compare current database state against a recipe
  (what's missing, what's changed)

### Status
- `pac_status()` — list loaded tables with source, filter, row count,
  load timestamp
- `pac_log()` — detailed load history

### Connection
- `pac_db_conn()` — connect to target PostgreSQL (same env var pattern as
  fresh: PG_*_SHARE)
- `pac_db_init()` — ensure PostGIS extension exists, create pac metadata
  schema

## Recipe Format

```yaml
# project_db.yml — reproducible database manifest
database: my_project
created: 2026-03-21
tables:
  - target: whse_basemapping.fwa_stream_networks_sp
    source: s3://bucket/fwa/fwa_stream_networks_sp.parquet
    filter:
      attr:
        watershed_group_code: [BULK, MORR]
    indexes:
      - type: gist
        column: geom
      - type: btree
        column: blue_line_key
      - type: btree
        column: linear_feature_id

  - target: working.field_crossings
    source: /data/field_2025.gpkg
    layer: crossings
    filter:
      spatial:
        bbox: [1100000, 700000, 1200000, 800000]
    indexes:
      - type: gist
        column: geom

  - target: bcfishpass.barriers_anthropogenic
    source: s3://bucket/bcfishpass/barriers_anthropogenic.parquet
    filter:
      attr:
        watershed_group_code: BULK
    indexes:
      - type: gist
        column: geom
      - type: btree
        column: barriers_anthropogenic_id
```

## Source Type Dispatch

```
pac_load() calls pac_source_detect() which returns one of:
  - s3_parquet  → arrow::read_parquet() via S3 URI
  - s3_gpkg     → download to temp, sf::read_sf()
  - local_gpkg  → sf::read_sf()
  - local_shp   → sf::read_sf()
  - local_fgdb   → sf::read_sf()
  - local_csv   → readr::read_csv() + sf::st_as_sf() if coords present
  - pg_table    → DBI::dbReadTable() or custom SQL
  - pg_dump     → system("pg_restore ...") or DBI SQL
  - url_zip     → download, unzip, detect inner format, recurse
```

Each source type has a reader function that returns an sf object (or writes
directly to pg for pg_dump). The sf object is then written to the target
table via `sf::st_write()` or `DBI::dbWriteTable()`.

## Dependencies

- **Runtime:** DBI, RPostgres, sf, arrow (parquet), yaml (recipes)
- **Suggests:** paws or aws.s3 (S3 access), readr (CSV), testthat
- **Database:** PostgreSQL with PostGIS extension

## Metadata Schema

pac creates a `pac` schema in the target database with one table:

```sql
CREATE SCHEMA IF NOT EXISTS pac;

CREATE TABLE pac.load_log (
  id SERIAL PRIMARY KEY,
  target_table TEXT NOT NULL,
  source_uri TEXT NOT NULL,
  source_type TEXT NOT NULL,
  filter_json JSONB,
  row_count INTEGER,
  loaded_at TIMESTAMPTZ DEFAULT now(),
  recipe_hash TEXT  -- SHA256 of the recipe entry, for diff detection
);
```

`pac_status()` queries this table. `pac_recipe_save()` reads it to build
the YAML. `pac_recipe_diff()` compares it against a YAML file.

## Open Questions

1. **S3 authentication** — use paws (AWS SDK) or aws.s3? paws is heavier
   but more capable. Or just rely on environment variables and let arrow
   handle S3 natively via its built-in filesystem?

2. **Large loads** — for tables with millions of rows, should pac chunk
   the write (e.g., 100k rows at a time) or trust sf/DBI to handle it?

3. **Schema creation** — should pac create target schemas automatically,
   or require them to exist? Auto-create is convenient but risks typos
   creating junk schemas.

4. **Overwrite vs append** — `pac_load()` default behavior when target
   table exists? Options: error, overwrite, append. Overwrite is safest
   for reproducibility.

5. **Non-spatial tables** — pac is spatial-first but some tables (species
   lookup CSVs, parameter tables) have no geometry. Support them or leave
   that to plain DBI?

## Relationship to Other Packages

```
pac (load anything into pg)
 ├── used by fwapg (load BC FWA data)
 ├── used by bcfishobs (load fish observations)
 ├── used by bcfishpass (load barrier/habitat data)
 ├── used by spyda (load raw stream geometries before coding)
 ├── used by any project (load field data, LiDAR, external datasets)
 │
 └── does NOT know about:
      ├── stream networks (spyda's job)
      ├── FWA codes (fresh's job)
      ├── fish species (bcfishpass's job)
      └── any domain concept
```

## Ports to New Repo

This issue is the design seed. When `NewGraphEnvironment/pac` is created,
port this as the initial `CLAUDE.md` architecture section and close this
issue with a cross-reference.
