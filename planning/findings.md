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

## fwapg Built-in Functions
- `fwa_indexpoint(geom, tolerance, num_features)` — snap point to nearest stream(s)
  - Returns: linear_feature_id, blue_line_key, downstream_route_measure, distance_to_stream, geom
  - postgisftw overload takes (x, y, srid) for convenience
  - tolerance default 5000m, num_features default 1
- `fwa_upstream(wsc_a, loc_a, wsc_b, loc_b)` — boolean: is b upstream of a?
- `fwa_downstream(wsc_a, loc_a, wsc_b, loc_b)` — boolean: is b downstream of a?
- `fwa_networktrace(blk_a, meas_a, blk_b, meas_b)` — stream segments between two points
  - Uses downstream traces from both points, returns non-overlapping segments
- `fwa_locatealong(blk, measure)` — point geometry at a network position
- `fwa_slicewatershedatpoint` — watershed polygon at a point
- `fwa_upstreamtrace` / `fwa_downstreamtrace` — raw trace functions
