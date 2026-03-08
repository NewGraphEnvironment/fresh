# fresh — Findings

## DB Connection Patterns
- fpr uses `Sys.getenv('PG_DB_SHARE')` etc. for defaults — zero config for existing users
- fpr `fpr_db_query()` uses `sf::st_read()` for spatial results, `DBI::dbGetQuery()` for non-spatial
- ngr `dbqs_*` functions are SQL string builders (generic, not FWA-specific)
- `ngr_dbqs_ltree()` useful for FWA watershed hierarchy queries (localcode_ltree, wscode_ltree)

## FWA Schema (fwapg)
- Key tables: `whse_basemapping.fwa_stream_networks_sp`, `whse_basemapping.fwa_lakes_poly`, `whse_basemapping.fwa_wetlands_poly`
- Network topology via `blue_line_key`, `downstream_route_measure`, `localcode_ltree`, `wscode_ltree`
- Watershed groups: `watershed_group_code` (e.g. "BULK" for Bulkley)

## bcfishpass Schema
- `bcfishpass.streams` — enriched stream segments with habitat/access model outputs
- Species access columns: e.g. `ch_spawning`, `ch_rearing`, `st_spawning`, `st_rearing`
- Barrier status, gradient, channel width all on stream segments

## bcfishobs Schema
- Fish observation records linked to FWA network position
- Species, counts, survey method, date
