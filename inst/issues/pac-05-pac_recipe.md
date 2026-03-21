## pac_recipe_save

Serialize the current database load history into a YAML recipe file.
Reads from `pac.load_log` and writes a manifest that `pac_recipe_run()`
can replay.

```r
pac_recipe_save(conn, "project_db.yml")
```

## pac_recipe_run

Rebuild a database from a recipe YAML file. Reads the manifest, executes
each load in order. Idempotent — existing tables are overwritten by default.

```r
# New machine, from scratch
conn <- pac_db_conn()
pac_db_init(conn)
pac_recipe_run(conn, "project_db.yml")
```

## pac_recipe_diff

Compare current database state against a recipe file. Reports what's
missing, what's extra, and what's changed (different row count or source).

```r
pac_recipe_diff(conn, "project_db.yml")
#> Missing from database:
#>   - working.field_crossings (source: /data/field_2025.gpkg)
#> Extra in database (not in recipe):
#>   - scratch.temp_analysis
#> Changed:
#>   - whse_basemapping.fwa_stream_networks_sp: 45000 rows (recipe) vs 43000 rows (db)
```

## Recipe YAML Format

See `inst/issues/design-pac.md` for full spec. Key fields per table entry:
target, source, layer, filter (attr + spatial), indexes.

## Implementation

- `R/pac_recipe_save.R`
- `R/pac_recipe_run.R`
- `R/pac_recipe_diff.R`
- `tests/testthat/test-pac_recipe.R`

## Dependencies

DBI, RPostgres, yaml
