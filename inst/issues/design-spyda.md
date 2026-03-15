## Overview

**spyda** — Stream Processing Yielding Drainage Assignment — builds custom stream network databases that `fresh` can query. It is the construction layer; `fresh` is the retrieval layer.

The BC Freshwater Atlas (FWA) provides a province-wide coded stream network via `fwapg`. But habitat modelling often requires networks derived from higher-resolution sources (LiDAR DEMs, field-surveyed channels) or networks outside BC. spyda fills that gap: ingest raw stream geometries, walk the network, assign the same code architecture that FWA uses, and build a PostgreSQL database that fresh queries identically.

```
spyda (build) → fresh (query) → breaks (sub-basins) → flooded (floodplains) → drift (change)
```

## fresh Table Name Flexibility

**Decision: fresh gets configurable table/column names, not fwapg-hardcoded defaults.**

Rather than spyda creating views to mimic fwapg naming, fresh should accept table and column names as options. Defaults match fwapg so existing code doesn't break, but options let any network DB use rational, abstract names.

```r
# Current implicit behavior — fwapg defaults
frs_network_upstream(blue_line_key = 360873822, downstream_route_measure = 166030)

# Future — spyda-built DB with its own naming
options(
  fresh.stream_table = "streams",
  fresh.blk_col = "route_id",
  fresh.wscode_col = "wscode_ltree",
  fresh.localcode_col = "localcode_ltree",
  fresh.measure_col = "route_measure"
)
frs_network_upstream(blue_line_key = 42, downstream_route_measure = 500)
```

This lets spyda name tables as abstractly as possible without coupling to FWA conventions. The `fresh` defaults keep everything backward compatible.

## The Problem spyda Solves

`fresh` queries work because fwapg encodes every stream segment with:
- **blue_line_key** — unique route identifier (mouth to headwaters)
- **wscode_ltree** — hierarchical drainage address (ltree)
- **localcode_ltree** — position along the parent route (ltree)
- **downstream_route_measure** — metres from the mouth

These aren't properties of the raw geometry. They're *assigned* by walking the network and making decisions at every confluence. FWA made those decisions once for the whole province. spyda makes them for any network you give it.

## Mainstem Selection

At every confluence, one branch continues as mainstem (keeps the parent code path) and the other becomes a tributary (gets a new code level appended). This single decision drives the entire hierarchy.

### Decision rules (pluggable, priority order)

1. **User override** — table of `(confluence_id, mainstem_branch)` for expert decisions
2. **Drainage area** — largest contributing area continues (most defensible, needs DEM)
3. **Channel length** — longest upstream path continues (no DEM needed)
4. **Stream order** — higher Strahler order continues, ties broken by length

### Algorithm

```
1. Identify outlet(s) — segments with no downstream neighbour
2. Assign root code (e.g., '100')
3. Walk upstream from each outlet (BFS/DFS)
4. At each confluence:
   a. Evaluate decision rule (user override > area > length > order)
   b. Winner keeps current code path (mainstem)
   c. Loser gets new code level appended (tributary)
5. Assign blue_line_keys — each continuous mainstem route gets one key
6. Compute downstream_route_measure along each blue_line_key
7. Assign localcode_ltree from position along parent route
8. Build ltree + spatial GiST indexes
```

## Proposed Function Surface

All exported functions prefixed `spd_`, noun-first.

### Database initialization
- `spd_db_init()` — create PostgreSQL database with ltree extension and spyda schema
- `spd_db_conn()` — connect to a spyda-built database

### Network ingestion
- `spd_network_ingest()` — load stream geometries into database, validate topology
- `spd_network_validate()` — check for disconnected segments, loops, inconsistent digitization

### Code assignment
- `spd_mainstem_assign()` — walk confluences, pick mainstems
- `spd_code_assign()` — burn wscode_ltree + localcode_ltree onto every segment
- `spd_bluelinekey_assign()` — assign route IDs to each continuous route
- `spd_measure_compute()` — compute route measures

### Indexing
- `spd_index_build()` — GiST indexes on ltree + spatial columns

### Overrides
- `spd_override_table()` — create/manage user override table
- `spd_override_add()` — add override for specific confluence

## Dependencies

- **Runtime:** DBI, RPostgres, sf, igraph (network walking)
- **Suggests:** terra (drainage area from DEM), fresh (integration testing)
- **Database:** PostgreSQL with ltree extension (no fwapg needed)

## Open Questions

1. **Flow direction** — LiDAR-derived networks may have inconsistent digitization direction. How much topology repair does spyda handle vs requiring clean input?

2. **Multiple outlets** — coastal drainages have many independent outlets. Each gets its own root code. Systematic assignment scheme?

3. **Waterbody integration** — FWA has separate lake/wetland tables linked by waterbody_key. Stream-only sufficient for habitat modelling, or do we need the same?

4. **Scale** — province-wide LiDAR network could be millions of segments. BFS walk in SQL vs R?

5. **fresh contract** — which fwapg columns/functions does fresh actually use? That defines the minimum schema spyda must produce and the options fresh needs to expose.

## Package Architecture — What Lives Where

Two generic packages, BC-specific loading stays separate:

```
Generic (any network, any jurisdiction):
  spyda  → topology engine (linestrings → coded network in PG)
  fresh  → operations layer (query, break, classify, aggregate)

BC-specific (data loading / ETL):
  fwapg     → load FWA streams, watersheds, lakes from BCGW
  bcfishobs → load fish observations from DataBC, snap to network
  bcfishpass → crossing CSVs, barrier overrides, species params
```

### Why not consolidate the loaders now?

The three BC repos already work. Their ETL is tested and runs weekly
(bcfishobs) or on-demand. Rewriting ETL into a single loader blocks on
spyda's schema being stable — you need to know what you're loading *into*
before consolidating what loads it.

**Sequence:**
1. Build spyda (topology engine)
2. Build fresh operations (break, classify, aggregate) with flexible table names
3. Once spyda schema is stable, *then* consider a single BC loader that
   knows how to populate a spyda-built DB from BCGW/DataBC sources
4. fwapg/bcfishobs/bcfishpass thin down to param files + data archives

### What the loaders actually do

| Repo | Extract from | Transform | Load into |
|------|-------------|-----------|-----------|
| fwapg | BCGW parquet (14 spatial datasets) | ltree codes, indexes | `whse_basemapping.*` tables + 23 PL/pgSQL functions |
| bcfishobs | DataBC `fiss_fish_obsrvtn_pnt_sp` + species CSVs | Multi-criteria snap (100m/500m/1500m, wscode validation) | `bcfishobs.observations` with FWA references |
| bcfishpass | User CSVs (barriers, habitat overrides, WCRP watersheds) | — | `bcfishpass.*` tables |

The snapping logic in bcfishobs (multi-criteria matching with distance
thresholds and wscode validation) is actually generic — it's "snap points
to nearest stream with fallback rules." That could eventually live in
fresh as `frs_point_snap()` with configurable match rules.

### fresh table name flexibility

fresh uses `options()` for table/column names. Defaults match fwapg so
existing code works unchanged. Any spyda-built network uses whatever
names make sense:

```r
options(
  fresh.stream_table = "streams",
  fresh.blk_col = "route_id",
  fresh.wscode_col = "wscode_ltree",
  fresh.localcode_col = "localcode_ltree",
  fresh.measure_col = "route_measure"
)
```

This means spyda is free to choose the most rational, abstract table names
without coupling to FWA conventions. The flexibility lives in fresh, not
in compatibility shims.

## Related

- `inst/issues/design-habitat-models.md` — fresh operations layer design
  (frs_break, frs_classify, frs_aggregate) that queries spyda-built networks
- NewGraphEnvironment/fresh#27

## Ports to New Repo

This issue is the design seed. When `NewGraphEnvironment/spyda` is created,
port this as the initial `CLAUDE.md` architecture section and close this
issue with a cross-reference.
