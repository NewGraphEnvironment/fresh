## spyda Build Pipeline — Abstracting fwapg

**Context:** fwapg builds a stream network database in a fixed sequence:
schema → extensions → load 14 spatial tables → process streams (add measures)
→ load CSVs → build derived tables (by WSG) → cross-border merge → vacuum.
All bash/SQL, province-wide, single-threaded per step.

spyda abstracts this into generic, parallelizable steps that work at any
spatial partition — from a single box (DEM tile) to the entire province.

## What fwapg Actually Does (decomposed)

| Step | fwapg implementation | What it really is |
|------|---------------------|-------------------|
| 1. Schema | `db/create.sh` → `schema.sql` | Create target tables + extensions |
| 2. Load spatial | `ogr2ogr` from parquet on S3 | Ingest source geometries |
| 3. Process streams | `fwa_stream_networks_sp.sql` — `st_addmeasure()`, `st_dump()` | Compute linear measures on network |
| 4. Load CSVs | `COPY` from gzipped CSV on S3 | Ingest lookup/reference tables |
| 5. Derived tables (small) | SQL scripts in `load/` | Build indexes, named streams, waterbodies |
| 6. Derived tables (large) | Loop over WSGs, run SQL per group | **This is the parallelizable step** |
| 7. Install functions | 16 PL/pgSQL functions (`FWA_Upstream`, etc.) | Install traversal/spatial functions |
| 8. Vacuum | `VACUUM ANALYZE` | Optimize |

**Key insight:** Step 6 is already partitioned by WSG in fwapg. That's the
pattern to generalize — any compute-heavy step can partition by spatial unit
and run in parallel.

## Abstract Build Pipeline

```
spd_build(
  conn,
  source,           # data source spec (parquet URLs, GeoPackage, sf objects)
  partition = NULL,  # spatial partition column or sf polygons
  parallel = 1       # number of workers
)
```

### Stages (in order, dependencies shown)

```
1. spd_schema_init(conn)
   └─ Create schema, extensions (ltree, postgis), target tables
   └─ Idempotent — safe to re-run

2. spd_source_ingest(conn, source, partition)
   └─ Load raw geometries into staging tables
   └─ source can be: parquet URLs, GeoPackage path, sf object, pg table
   └─ If partition provided, filter source to partition extent
   └─ PARALLEL: each partition loads independently

3. spd_topology_build(conn, partition)
   └─ Validate connectivity (no orphans, consistent digitization)
   └─ Identify confluences, headwaters, outlets
   └─ Assign mainstem/tributary at each confluence
   └─ Compute wscode_ltree + localcode_ltree
   └─ Compute downstream_route_measure
   └─ For FWA: codes already exist, this verifies + indexes
   └─ For LiDAR: this is the heavy compute step
   └─ PARALLEL: independent watershed groups can build simultaneously

4. spd_functions_install(conn)
   └─ Install traversal functions (upstream, downstream, snap, watershed)
   └─ Generic versions of fwapg's FWA_Upstream, FWA_Downstream, etc.
   └─ Idempotent — CREATE OR REPLACE

5. spd_index_build(conn)
   └─ GiST on geometry, ltree indexes on codes
   └─ VACUUM ANALYZE
   └─ Must run after all partitions are loaded

6. spd_derived_build(conn, partition, parallel)
   └─ Named streams, waterbody lookups, order aggregates
   └─ THE parallelizable step — each partition is independent
   └─ This is where fwapg loops over WSGs
```

### What "partition" means at each scale

| Scale | partition value | What happens |
|-------|----------------|--------------|
| Box (DEM tile) | `sf` polygon of tile extent | Ingest + build for that tile only |
| Watershed | `list(blk = 360873822, measure = 1000)` | Delineate watershed, use as extent |
| Watershed group | `"BULK"` or `c("BULK", "MORR")` | Filter by WSG column |
| Province | `NULL` | Everything — no spatial filter |

Partitions are **composable**: build BULK, build MORR, stitch. The ltree
codes are globally unique so partitions don't conflict.

## Parallelism Options

### Option A: future (recommended start)

```r
library(future)
plan(multisession, workers = 4)  # or multicore on Linux

wsgs <- c("BULK", "MORR", "ELKR", "KLUM")

# Parallel derived table builds
future.apply::future_lapply(wsgs, function(wsg) {
  conn <- spd_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  spd_derived_build(conn, partition = wsg)
})
```

**Why future first:**
- Pure R, no infrastructure
- Works locally (multisession) or on cluster (future.batchtools)
- Each worker gets its own pg connection — no connection sharing issues
- furrr is just purrr + future, familiar API
- Scales from laptop (4 cores) to server (64 cores) with one line change

### Option B: furrr (syntactic sugar over future)

```r
library(furrr)
plan(multisession, workers = 4)

wsgs |>
  furrr::future_walk(~{
    conn <- spd_db_conn()
    on.exit(DBI::dbDisconnect(conn))
    spd_derived_build(conn, partition = .x)
  })
```

Same backend as Option A, just purrr syntax. No new concepts.

### Option C: Kubernetes / external orchestration

For province-wide builds where even 64 local cores isn't enough:

```yaml
# Conceptual — each WSG is a k8s Job
apiVersion: batch/v1
kind: Job
metadata:
  name: spd-build-BULK
spec:
  template:
    spec:
      containers:
      - name: spd-worker
        image: newgraph/spyda:latest
        command: ["Rscript", "-e",
          "spyda::spd_derived_build(spd_db_conn(), partition = 'BULK')"]
```

**But we don't need this yet.** The beauty of future is that swapping
`plan(multisession)` for `plan(future.batchtools::batchtools_kubernetes)`
works without changing the R code. Design for future, scale to k8s later.

### Option D: pg-native parallelism

PostgreSQL itself can parallelize queries (`max_parallel_workers_per_gather`).
For heavy spatial operations (intersection, measure computation), pg's own
parallel query planner may be faster than R-level parallelism because data
never leaves the database.

```sql
-- pg.conf
max_parallel_workers_per_gather = 4
max_parallel_workers = 8
```

**Use both:** R-level parallelism for partition orchestration (different WSGs
on different workers), pg-level parallelism for heavy spatial ops within
each partition.

## Build at Box Level → Stitch

The most interesting scale. A "box" is a DEM tile or arbitrary rectangular
extent.

```r
# 1. Extract channels from DEM tiles (whitebox/terra — embarrassingly parallel)
tiles <- list.files("dem_tiles/", pattern = "\\.tif$", full.names = TRUE)

plan(multisession, workers = 8)
channels <- future.apply::future_lapply(tiles, function(tile) {
  whitebox::wbt_extract_streams(tile, threshold = 100)
})

# 2. Load each tile's channels into pg (parallel, each worker has own conn)
future.apply::future_lapply(channels, function(ch) {
  conn <- spd_db_conn()
  on.exit(DBI::dbDisconnect(conn))
  spd_source_ingest(conn, source = ch, schema = "lidar")
})

# 3. Stitch — resolve tile-edge connectivity
#    Channels that cross tile boundaries need their endpoints matched
spd_topology_stitch(conn, schema = "lidar")

# 4. Build topology on the stitched network
spd_topology_build(conn, schema = "lidar")

# 5. Now fresh works on it identically
frs_break(conn, aoi = my_study_area, type = "segment",
          attribute = "gradient", threshold = 0.05,
          network_schema = "lidar", schema = "working")
```

### The stitch problem

When building from tiles, channels cross tile boundaries. Two segments in
adjacent tiles represent the same physical channel but are disconnected
geometries. `spd_topology_stitch()` handles this:

1. Find segment endpoints within a tolerance of tile edges
2. Match across tiles by proximity + bearing continuity
3. Merge into single segments or add connecting edges
4. Validate: no dangling ends at former tile boundaries

This is the hardest part. fwapg doesn't have this problem because FWA is
delivered as a pre-connected province-wide network. LiDAR tile builds do.

## spd_build() — The One-Call Interface

```r
# Local laptop — 4 cores, single WSG
spd_build(conn, source = "bcgw", partition = "BULK", parallel = 4)

# Server — 32 cores, multiple WSGs
spd_build(conn, source = "bcgw",
          partition = c("BULK", "MORR", "ELKR", "KLUM"),
          parallel = 32)

# LiDAR tiles — box-level build
spd_build(conn,
          source = list.files("dem_tiles/", full.names = TRUE),
          source_type = "dem",
          parallel = 8,
          schema = "lidar")

# Province-wide from cached parquet
spd_build(conn, source = "s3://bucket/fwa/", parallel = 64)
```

Internally this just calls the stages in order, parallelizing where possible.

## What spyda Needs vs What fwapg Has

| fwapg asset | spyda equivalent | Reuse? |
|-------------|-----------------|--------|
| `schema.sql` | `spd_schema_init()` | Abstract — no FWA-specific table names |
| `load.sh` ogr2ogr calls | `spd_source_ingest()` | Abstract — any source format |
| `fwa_stream_networks_sp.sql` | `spd_topology_build()` | Generalize measure computation |
| 16 PL/pgSQL functions | `spd_functions_install()` | Fork + rename: `spd_upstream()` etc. |
| WSG loop in load.sh | `spd_derived_build()` with future | Same pattern, parallel |
| `load/*.sql` derived tables | Recipe registry | Source-specific — FWA recipes stay in fwapg loader |

### The function fork

fwapg's PL/pgSQL functions (`FWA_Upstream`, `FWA_Downstream`, etc.) are the
crown jewels. They're not FWA-specific — they work on any ltree-coded
network. spyda forks these as `spd_upstream()`, `spd_downstream()`, etc.

The only FWA-specific part is column names (`blue_line_key`,
`wscode_ltree`, `localcode_ltree`). spyda's versions use configurable
column names matching `fresh.blk_col`, `fresh.wscode_col`, etc.

## Implementation Sequence

1. **spd_schema_init()** — create schema + extensions. Test: schema exists.
2. **spd_source_ingest()** — load from parquet/gpkg/sf. Test: rows in staging.
3. **spd_functions_install()** — fork fwapg functions. Test: `spd_upstream()` callable.
4. **spd_index_build()** — indexes. Test: explain plan uses index.
5. **spd_derived_build()** — one WSG. Test: derived tables populated.
6. **spd_build()** — orchestrator. Test: end-to-end single WSG.
7. **Parallel support** — future/furrr. Test: 2 WSGs simultaneously.
8. **spd_topology_build()** — ltree assignment for non-FWA networks. Test: LiDAR channels get valid codes.
9. **spd_topology_stitch()** — tile-edge resolution. Test: cross-tile continuity.

Steps 1-7 replicate what fwapg does. Steps 8-9 are new capability.

## Open Questions

1. **Schema per network or shared schema?** FWA in `whse_basemapping`,
   LiDAR in `lidar`, custom in `custom`? Or a network registry table?

2. **Function namespacing** — `spd_upstream()` in public schema, or
   `{schema}.spd_upstream()` per network? pg functions don't namespace
   well by schema.

3. **DEM → channels** — does spyda own the whitebox/terra channel
   extraction, or just ingest the result? (Suggest: just ingest.
   Channel extraction is a terra/whitebox concern, not topology.)

4. **fwapg transition** — when does fwapg thin down to "FWA data loader
   that calls spyda"? After spd_build() can reproduce fwapg's output
   for at least one WSG.

5. **pg connection pooling** — with 32+ parallel workers each opening a
   connection, need to manage `max_connections` and possibly use
   pgbouncer. Document minimum pg config.

6. **Partition stitching order** — for province-wide builds, do you build
   all WSGs in parallel then stitch? Or build downstream-first so
   cross-boundary codes are consistent? (FWA codes are pre-assigned so
   this only matters for LiDAR/custom networks.)

## Relates To

- `inst/issues/design-spyda.md` — topology engine design (mainstem selection, code assignment)
- `inst/issues/design-habitat-models.md` — fresh operations that consume spyda-built networks
- NewGraphEnvironment/fwapg — the concrete implementation being abstracted
- NewGraphEnvironment/fresh#27
