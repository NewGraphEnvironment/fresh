# Findings

## frs_network() architecture (from code read)

### Current execution path
```
frs_network() → lapply(tables, frs_network_one())
  ├─ frs_network_direct()    → frs_db_query(conn, sql) → sf
  └─ frs_network_waterbody() → frs_db_query(conn, sql) → sf
```

### With to= parameter
```
frs_network(to=) → lapply(tables, frs_network_one())
  ├─ frs_network_direct()    → .frs_db_execute(conn, CREATE TABLE AS sql)
  └─ frs_network_waterbody() → .frs_db_execute(conn, CREATE TABLE AS sql)
```

The SQL body is identical — ltree traversal, CTEs, waterbody bridging. Only the final execution changes.

### Internal dispatch
- `frs_network_one()` routes to `frs_network_direct()` or `frs_network_waterbody()` based on table name pattern (lakes/wetlands/rivers → waterbody)
- Both currently return sf. With to=, both would return NULL (side effect: table created)
- Main function handles: overwrite (DROP), naming (prefix + suffix), and return value (conn vs list)

### Return type when to= provided
- Single table: `conn` invisibly (pipeable)
- Multi table: also `conn` invisibly (all tables written with suffixed names)
- User accesses tables by the names they chose

### Clip incompatibility
`clip` does `frs_clip(sf, polygon)` in R — requires sf. When to= writes to DB, there's no sf to clip. Options:
- Error if both provided (simplest, chosen)
- Future: add SQL-level clipping (ST_Intersection) as a TODO

## Caller inventory (46+ usages)

### fresh package
| Location | Count | Pattern | Needs change? |
|----------|-------|---------|---------------|
| R/frs_network.R examples | 2 | sf for plotting | Add to= example |
| R/frs_clip.R example | 1 | sf for clipping | No (clip + to incompatible) |
| tests/testthat/ | 35+ | Unit tests, to=NULL | No |
| vignettes/ | 4 | sf for tmap/analysis | No |
| data-raw/ | 2 | sf for caching | Yes — use to= pipeline |

### breaks package
| Location | Count | Pattern | Needs change? |
|----------|-------|---------|---------------|
| R/app_server.R | 1 | sf for Shiny reactive | No |

### restoration_wedzin_kwa
| Location | Count | Pattern | Needs change? |
|----------|-------|---------|---------------|
| scripts/fwa_extract_flood.R | 1 | sf → GeoPackage | No (future opt-in) |
| scripts/prioritization_score.R | 2 | sf → spatial join | No (future opt-in) |

## Channel width lookup tables (from DB inspection)

| Attribute | Table | Join key | Type |
|-----------|-------|----------|------|
| channel_width | fwa_stream_networks_channel_width | linear_feature_id | Direct |
| mad_m3s | fwa_stream_networks_discharge | linear_feature_id | Direct |
| upstream_area_ha | fwa_watersheds_upstream_area | watershed_feature_id (via lut) | Two-hop |
| map_upstream | fwa_stream_networks_mean_annual_precip | wscode_ltree + localcode_ltree | Composite |

`frs_col_join()` handles all of these (built and tested in current session).

## Lake rearing gap (bcfishpass#7)

In BULK watershed group:
- Lake segments: 1140 total, **0 rearing**, 29 spawning
- Wetland segments: 4481 total, 2605 rearing, 232 spawning
- Stream segments (in waterbodies): 2143 total, 1709 rearing, 1783 spawning

bcfishpass coho model scores lake-connected stream segments as `rearing = 0`. Wetland-connected segments DO get scored. This is a known gap — coho use lakes for rearing ecologically.

Fresh fixes via `frs_classify(where = "edge_type IN (1050)")` using `frs_edge_types()`.

## frs_edge_types() (built and tested)

CSV at `inst/extdata/edge_types.csv` with 28 FWA edge type codes. Helper `frs_edge_types(category = "lake")` returns code 1050.

## frs_classify(where=) (built and tested)

New `where` param scopes which rows get classified. Works with ranges, breaks, and overrides modes.

## frs_col_join() (built and tested)

Generic lookup table enrichment. Detects source column types from information_schema. Handles direct keys, composite keys, named key mapping, and subqueries.

## Cached data (regenerated)

`inst/extdata/byman_ailport.rds` now includes `channel_width` and `channel_width_source` on streams (996 of 2167 segments have values). Data generation script updated to use `conn` parameter throughout.
