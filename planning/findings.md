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
- Species-specific views: `streams_co_vw`, `streams_ch_vw`, etc.
- Key columns: `segmented_stream_id`, `blue_line_key`, `wscode`, `localcode` (NOT ltree types)
- Habitat columns: `gradient`, `channel_width`, `mad_m3s`, `mapping_code`, `rearing`, `spawning`, `access`
- Caveat: rearing/spawning filters drop lake/wetland segments (bcfishpass#7)

## bcfishobs Schema
- Fish observation records linked to FWA network position
- Species, counts, survey method, date

## fwapg Built-in Functions
- `fwa_indexpoint(geom, tolerance, num_features)` — snap point to nearest stream(s)
- `fwa_upstream(wsc_a, loc_a, wsc_b, loc_b)` — boolean: is b upstream of a?
- `fwa_downstream(wsc_a, loc_a, wsc_b, loc_b)` — boolean: is b downstream of a?
- `fwa_networktrace(blk_a, meas_a, blk_b, meas_b)` — stream segments between two points
- `fwa_locatealong(blk, measure)` — point geometry at a network position
- `fwa_watershedatmeasure(blk, measure)` — watershed polygon at a network position

## Write Operations (new for habitat pipeline)

### frs_db_query() limitation
- Uses `sf::st_read(conn, query = query)` — SELECT only
- Cannot handle CREATE TABLE, UPDATE, INSERT, ALTER TABLE
- Need `DBI::dbExecute(conn, sql)` for write operations

### working schema
- Remote DB has `working` schema for user-writable staging
- bcfishpass weekly builds are read-only (except working)
- No existing fresh functions write to DB — all read-only until now

## Existing infrastructure (already built)

### .frs_resolve_aoi() — R/utils.R:188-256
- Character vector → `WHERE partition_col IN (...)` with spatial intersection
- sf polygon → `ST_Intersects(geom, ST_GeomFromText(...))`
- list(blk, measure) → watershed delineation via `fwa_watershedatmeasure()`
- list(table, id) → polygon lookup from DB table
- NULL → no filter (empty string)
- Partition table/column configurable via `options()`

### frs_params() — R/frs_params.R
- Loads from DB table or CSV
- Returns named list keyed by species_code
- Each species has threshold values + `$ranges` sub-list
- `$ranges$spawn` and `$ranges$rear` each contain `list(column = c(min, max))`
- Test data: `inst/testdata/test_params.csv` (BT/CH/CO)

## DB Write Access
- `working` schema: confirmed CREATE TABLE + DROP TABLE via `DBI::dbExecute()`
- MCP pg_write_query blocks DDL ("dangerous patterns") — use R/DBI for testing writes
- MCP pg_read_query works fine for SELECT including function source inspection

## bcfishpass break_streams() — the core splitting pattern

Uses `ST_LocateBetween()` (PostGIS linear referencing on M-values). NO actual geometry splitting needed — FWA streams already carry route measures.

**Algorithm:**
1. Collect break point measures from a point table (rounded to integer, >1m from segment endpoints)
2. JOIN to `bcfishpass.streams` on `blue_line_key` where measure falls within segment
3. Use `lead()` window over break measures per `segmented_stream_id` to get new (ds_measure, us_measure) pairs
4. `(ST_Dump(ST_LocateBetween(geom, ds_measure, us_measure))).geom` — extract sub-linestring
5. UPDATE original segment geometry (shortened to first break point)
6. INSERT new segments with attributes copied from original + FWA base table

**Key columns carried forward:** `linear_feature_id`, `edge_type`, `blue_line_key`, `watershed_key`, `watershed_group_code`, `waterbody_key`, `wscode_ltree`, `localcode_ltree`, `gnis_name`, `stream_order`, `stream_magnitude`, `feature_code`, `upstream_area_ha`, `stream_order_parent`, `stream_order_max`, `map_upstream`, `channel_width`, `mad_m3s`

**Implication for fresh:** `frs_break_apply()` can use the same `ST_LocateBetween()` approach on working schema tables. Much simpler than vertex insertion.

## bcfishpass SQL Patterns (to replicate)

### Barriers (frs_break)
- 14 SQL scripts for different barrier types
- All variations of: find where attribute exceeds threshold → mark as break
- Evidence validation: count upstream fish observations, remove break if count exceeds threshold
- Species access models: combine barriers with species-specific thresholds

### Classification (frs_classify)
- 14 SQL scripts for habitat labeling
- Pattern: UPDATE column SET value WHERE attribute BETWEEN min AND max
- Accessibility: WHERE NOT EXISTS downstream barrier
- Manual overrides: JOIN with known habitat table

### Aggregation (frs_aggregate)
- 6 SQL scripts for network-directed summarization
- Pattern: JOIN via fwa_upstream/fwa_downstream, then SUM/COUNT/GROUP BY
- Metrics: upstream habitat length, upstream observation counts, etc.
