# Findings — frs_point_match: match two point datasets along FWA network within instream distance (#206)

## Issue context

## Problem

fresh has primitives for snapping points to FWA streams (`frs_point_snap`) and for finding upstream/downstream features per segment (`frs_network_features`), but no primitive for matching two **point datasets** along the network within a distance threshold.

Concrete use case driving this: link's bcfp parity layer needs to reproduce bcfp's `02_pscis_streams_150m.sql` at `smnorris/bcfishpass@v0.7.14-125-g6e9cf1c` (current tunnel state, `bcfishpass.log.model_run_id=121` rebuilt 2026-05-05) -- match PSCIS crossings to modelled crossings within 100m instream distance on the same stream, then keep the nearest PSCIS per modelled crossing. Currently link's `lnk_pipeline_crossings` is missing this layer, leaving modelled crossings duplicating PSCIS positions in the working schema; cascades into >+1000 false-positive anthropogenic barriers in BULK alone (see link's `research/bcfp_table_map.md`).

The operation generalizes beyond PSCIS:

- field-assessed crossings <-> user-added crossings deduplication
- observations <-> habitat confirmation points
- any "merge two point datasets on the same FWA network" workflow

## Proposed primitive

`frs_point_match(conn, table_a, table_b, table_to, distance_max, ...)`:

- Both input tables must already be snapped to FWA (carry `blue_line_key`, `downstream_route_measure` -- typically via `frs_point_snap` upstream).
- Output table has columns from `table_a` plus a `<table_b_id_col>` linking column populated where a match within `distance_max` exists.
- Matching is on **same `blue_line_key`** + instream distance <= `distance_max` (computed from `downstream_route_measure` deltas).
- Dedup: each `table_b` row links to at most one `table_a` row -- the closest one (`DISTINCT ON (table_b_id) ORDER BY distance ASC`).

### Signature

```r
frs_point_match(
  conn,
  table_a,                              # schema-qualified, points to match FROM
  table_b,                              # schema-qualified, points to match TO
  table_to,                             # schema-qualified destination
  distance_max,                         # max instream distance (metres)
  table_a_id_col = "id",
  table_b_id_col = "id"
)
```

Returns `conn` invisibly. Side effect: drops + recreates `table_to` with table_a's columns plus the linking ID column.

Network-position columns (`blue_line_key`, `downstream_route_measure`) are hard-coded to the FWA convention -- every FWA-snapped point table in the bcfp ecosystem uses these names. Per-side overrides (like `frs_network_features` got in fresh#204) can be added later if a real divergence appears.

## Why fresh, not link

This is a generic FWA-primitive operation. fresh already owns:

- `frs_point_snap` -- point <-> stream snap
- `frs_network_features` -- segment <-> feature dnstr/upstr

`frs_point_match` rounds out the point-handling family -- point <-> point along the network. Adding it in fresh makes the primitive available to link, bcfishpass-comparable tooling, and any future packages working with point-on-network data. Name uses singular `point` to match `frs_point_snap` (the closest existing analog).

## Acceptance

- [ ] `frs_point_match(...)` produces output byte-identical to bcfp's `02_pscis_streams_150m.sql` output (at `smnorris/bcfishpass@v0.7.14-125-g6e9cf1c`) for a test WSG (after stream-name filtering, which is bcfp-specific and stays in link's caller, not the primitive)
- [ ] Mocked tests covering the dedup logic (multiple table_a matching one table_b)
- [ ] Live test on a small WSG (ADMS or similar) validating the byte-identical claim
- [ ] Roxygen + lintr clean
- [ ] Exported from NAMESPACE

## Out of scope

- Stream-name matching (bcfp does this for PSCIS-specific reasons via `gnis_name` <-> `stream_name` regex matching). Caller can layer that on top -- primitive provides just the network-distance match.
- Multi-stream matching (matching across wscode_ltree subtrees) -- single `blue_line_key` is enough for the parity case.
- Bidirectional dedup variants (matching pairs both ways) -- `DISTINCT ON (table_b_id)` is enough.
- Per-side column-name overrides (`table_*_blk_col` etc.) -- add when a real divergence appears.

## Exploration notes (from plan-mode 2026-05-11)

### fresh codebase patterns (Explore agent report)

- **`frs_network_features` is the template** (`R/frs_network_features.R`). v0.29.0+, has per-side wscode/localcode overrides (fresh#204 / commit `f42e86a`), uses `sprintf` SQL composition with `.frs_validate_identifier()` on every user-supplied identifier (security gate).
- **Three-tier test pattern** (`tests/testthat/test-frs_network_features.R`):
  - Tier 1 — validation tests, no DB, `expect_error()` per arg path (lines 6–124)
  - Tier 2 — SQL composition tests via `withr::local_mocked_bindings()` mocking `frs_db_query`, capture SQL, `expect_match` key clauses (lines 127–374)
  - Tier 3 — live DB integration, `skip_if_not(.frs_db_available())`
- **No re-exports from other packages** — pure `@export` via roxygen.
- **Current version** — `DESCRIPTION` line 3: `0.29.0`.
- **Private helpers** in `R/utils.R`: `.frs_validate_identifier()`, `.frs_db_available()`, `.frs_snap_guards()`.

### bcfp algorithm (Explore agent report, with verification)

- bcfp source: `model/01_access/pscis/sql/02_pscis_streams_150m.sql`
- Same-stream constraint: `e.blue_line_key = m.blue_line_key` (line 158)
- Instream distance: `ABS(e.downstream_route_measure - m.downstream_route_measure) < 100` (line 159)
- Dedup: two phases — `DISTINCT ON (stream_crossing_id, blue_line_key)` ordered by `modelled_xing_dist_instream`
- 100m threshold hard-coded; 150m planar pre-filter also hard-coded (will be `distance_max` parameter in our primitive)
- **Algorithm unchanged between local v0.7.13-167-ga9d93f0 source and tunnel v0.7.14-125-g6e9cf1c** — verified via `git log --oneline v0.7.13-167-ga9d93f0..v0.7.14-125-g6e9cf1c -- 02_pscis_streams_150m.sql` (empty output)
- Stream-name scoring (lines 18–26, 101–105) is **descriptive not prescriptive** — stays in caller (link), out of scope for primitive
- Width-order scoring similar — out of scope
- 150m planar pre-filter (`distance_to_stream < 150`) — stays in caller (link's `lnk_points_snap` already snaps to streams within tolerance)

### Design decision: write-to-table vs return-tibble

- Issue body specifies write-to-table (`table_to`, returns `conn` invisibly)
- This diverges from existing fresh primitives (`frs_point_snap` returns sf, `frs_network_features` returns tibble)
- Right call because:
  - Result is a derived dataset, not a query result
  - bcfp's analog `02_pscis_streams_150m.sql` writes to a table
  - Caller doesn't want to round-trip large result through R
- May want to revisit if a future use case prefers return-tibble; could add `to = NULL` semantic later (when `NULL`, return tibble; when string, write to table).
