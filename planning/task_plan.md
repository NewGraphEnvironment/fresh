# fresh — Habitat Model Pipeline Plan

## Goal

Build 4 server-side functions that replicate bcfishpass's ~34 SQL scripts as composable R functions: extract, break, classify, aggregate. All write to `working` schema via `DBI::dbExecute()`. Tested against live remote DB.

## Pipeline

```r
conn <- frs_db_conn()
params <- frs_params(conn)

conn |>
  frs_extract("bcfishpass.streams_co_vw", "working.streams_co", aoi = "BULK") |>
  frs_break_find("working.streams_co", attribute = "gradient", threshold = 0.05) |>
  frs_break_apply("working.streams_co", breaks = "working.breaks") |>
  frs_classify("working.streams_co", ranges = params$CO$ranges$spawn, label = "spawning") |>
  frs_aggregate(points = "working.crossings", features = "working.streams_co", metrics = "length_m")
```

All write functions return `conn` invisibly for consistent `|>` chaining. Table names are explicit parameters — no hidden state.

## Prerequisites (already complete)

- [x] #34 `.frs_resolve_aoi()` — already in `R/utils.R:188-256`
- [x] #35 conn-first API — merged as v0.2.0
- [x] #37 `frs_params()` — already in `R/frs_params.R` with tests
- [x] DB write access — confirmed CREATE/DROP in `working` schema
- [x] Break mechanism — `ST_LocateBetween()` on M-values, no geometry splitting needed

## Infrastructure (build first)

- [x] `.frs_db_execute()` — internal helper for DDL/DML in `R/utils.R`
- [x] `.frs_test_drop()` — integration test teardown helper in `R/utils.R`

## Phase 1: frs_extract() (#36)

Stage read-only bcfishpass data into working schema for modification.

- [x] `frs_extract(conn, from, to, cols, aoi, overwrite)` — `R/frs_extract.R`
- [x] Unit tests: 7 tests (SQL generation, validation, overwrite logic)
- [x] Integration tests: 3 tests (create, error on exists, overwrite) — 339 total pass

**SQL pattern:**
```sql
DROP TABLE IF EXISTS working.streams_co;
CREATE TABLE working.streams_co AS
SELECT segmented_stream_id, blue_line_key, gradient, channel_width, geom
FROM bcfishpass.streams_co_vw
WHERE watershed_group_code IN ('BULK');
```

## Phase 2: frs_break() (#38)

Find, validate, and apply break points on the stream network. Decomposed into sub-functions for flexibility — each exported, each independently useful.

### Sub-functions (all exported):

- [ ] `frs_break_find(conn, table, attribute, threshold, points, aoi)` — find break locations
  - Three modes: attribute threshold, point table, user sf points
  - Returns sf points with `blue_line_key`, `downstream_route_measure` columns
  - Attribute mode: finds segment endpoints where attribute exceeds threshold
  - Table mode: pulls point features from a DB table (falls, dams, crossings)
  - Points mode: snaps user-provided sf points via `frs_point_snap()`
  - `rbind()`-able — all modes return same shape
  - Returns `conn` invisibly
- [ ] `frs_break_validate(conn, breaks, evidence_table, where, count_threshold)` — filter against evidence
  - For each break point, count upstream observations matching `where`
  - Remove breaks where count >= count_threshold (fish got past = not a real barrier)
  - Uses ltree upstream query under the hood
  - Returns `conn` invisibly
- [ ] `frs_break_apply(conn, table, breaks)` — split geometry at break locations
  - Operates on working schema table (from `frs_extract()`)
  - Uses `ST_LocateBetween()` — break measures define new segment boundaries
  - Shortens original segments, inserts new segments (bcfishpass pattern)
  - Returns `conn` invisibly
- [ ] `frs_break(conn, table, attribute, threshold, ...)` — convenience wrapper
  - Calls find → validate (if evidence params) → apply in sequence
  - Returns `conn` invisibly
- [ ] Unit tests for each sub-function
- [ ] Integration tests against live DB

**SQL pattern (from bcfishpass `break_streams`):**
```sql
-- find break measures on each segment (>1m from endpoints)
WITH breakpoints AS (
  SELECT DISTINCT blue_line_key,
    round(downstream_route_measure::numeric)::integer as downstream_route_measure
  FROM working.breaks
  WHERE ...
),
-- pair up new segment boundaries using lead()
new_measures AS (
  SELECT segmented_stream_id, linear_feature_id,
    meas_event AS downstream_route_measure,
    lead(meas_event, 1, meas_stream_us) OVER (
      PARTITION BY segmented_stream_id ORDER BY meas_event
    ) AS upstream_route_measure
  FROM to_break
)
-- cut geometry
SELECT (ST_Dump(ST_LocateBetween(
  s.geom, n.downstream_route_measure, n.upstream_route_measure
))).geom AS geom
FROM new_measures n JOIN streams s ...
```

## Phase 3: frs_classify() (#39)

Label features by attribute ranges, break accessibility, manual overrides.

- [ ] `frs_classify(conn, table, ranges, breaks, overrides, label)` — column UPDATE
  - `ranges = list(gradient = c(0, 0.025), channel_width = c(2, 20))` — all must be in range
  - `breaks` = break table name → label segments as accessible/not based on network position
  - `overrides` = table of manual corrections (JOIN + UPDATE)
  - `label` = column name to add/update (e.g. `"spawning"`, `"accessible"`)
  - Returns `conn` invisibly
- [ ] Unit tests: SQL generation
- [ ] Integration test: classify extracted data, verify column values

**SQL pattern (ranges):**
```sql
ALTER TABLE working.streams_co ADD COLUMN IF NOT EXISTS spawning boolean;
UPDATE working.streams_co SET spawning = TRUE
WHERE gradient BETWEEN 0 AND 0.025
  AND channel_width BETWEEN 2 AND 20;
```

**SQL pattern (breaks/accessibility):**
```sql
ALTER TABLE working.streams_co ADD COLUMN IF NOT EXISTS accessible boolean;
UPDATE working.streams_co s SET accessible = TRUE
WHERE NOT EXISTS (
  SELECT 1 FROM working.breaks b
  WHERE fwa_downstream(b.wscode, b.localcode, s.wscode, s.localcode)
);
```

## Phase 4: frs_aggregate() (#40)

Summarize features along the network from given points.

- [ ] `frs_aggregate(conn, points, features, metrics, direction, collect)` — network traversal + aggregation
  - `points` = table of locations (crossings, sites)
  - `features` = table to aggregate (streams, lakes)
  - `metrics` = what to compute (`"length_m"` → `ST_Length(geom)`, `"area_ha"`, `"count"`)
  - `direction` = `"upstream"` (default) or `"downstream"`
  - `collect = FALSE` → writes result table, `TRUE` → returns data.frame to R
  - Returns `conn` invisibly (when `collect = FALSE`)
- [ ] Unit tests
- [ ] Integration tests

**SQL pattern:**
```sql
SELECT p.id,
  SUM(ST_Length(f.geom)) AS length_m
FROM working.crossings p
JOIN working.streams_co f ON fwa_upstream(p.wscode, p.localcode, f.wscode, f.localcode)
GROUP BY p.id;
```

## Phase 5: Package Polish

- [ ] `devtools::document()` — regenerate NAMESPACE and man pages
- [ ] `devtools::test()` — all tests pass (unit + integration)
- [ ] `devtools::check()` — 0 errors
- [ ] Update NEWS.md
- [ ] Bump to v0.3.0
- [ ] Tag and push

## Testing Strategy

### Two tiers:

1. **Unit tests (mock conn):** Test SQL generation, input validation, error paths. Fast, no DB needed. Use `mockery::local_mocked_bindings()` to capture SQL strings.

2. **Integration tests (live DB):** Test real SQL execution against remote DB via SSH tunnel. Pattern:
   ```r
   test_that("frs_extract creates working table", {
     skip_if_not(.frs_db_available(), "DB not available")
     conn <- frs_db_conn()
     on.exit({
       .frs_test_drop(conn, "working.test_extract")
       DBI::dbDisconnect(conn)
     })
     # ... test ...
   })
   ```

### Test table names (fixed):
`working.test_extract`, `working.test_break`, `working.test_classify`, `working.test_aggregate`

## Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Write helper | `frs_db_execute()` internal | `frs_db_query()` can't do DDL/DML |
| Return values | All return `conn` invisibly | Consistent `\|>` chaining, explicit table names |
| Break mechanism | `ST_LocateBetween()` on M-values | FWA already has route measures, no vertex splitting needed |
| Break decomposition | 4 exported sub-functions | Flexibility: use find/validate/apply independently or via wrapper |
| Break writes to | working schema copy (from extract) | Never modify read-only bcfishpass tables |
| Test table names | Fixed (`working.test_*`) | Simple, cleanup is straightforward |
| Test cleanup | `on.exit()` + `.frs_test_drop()` | Reliable, DRY |
| Server-side default | Write to schema, `collect = TRUE` to return | Avoid pulling large tables into R |

## Errors Encountered

| Error | Attempt | Resolution |
|-------|---------|------------|
| MCP pg_write_query blocks DDL | 1 | Use R/DBI for write testing, MCP for reads only |

## Open Questions

(all resolved)
