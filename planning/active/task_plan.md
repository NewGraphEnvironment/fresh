# #49 — Waterbody extra_where + from filtering

## Problem

`frs_network()` waterbody key lookup always traverses the FWA base table. Users can't filter waterbodies to those connected to habitat streams (e.g. `spawning > 0`).

## Architecture

Two-CTE approach — separate fast traversal from cheap filtering:

```sql
-- CTE 1: fast traversal on indexed FWA base table (always)
wbkeys_network AS (
  SELECT DISTINCT s.waterbody_key
  FROM whse_basemapping.fwa_stream_networks_sp s, ref
  WHERE fwa_upstream(ref.wscode_ltree, ref.localcode_ltree,
                     s.wscode_ltree, s.localcode_ltree)
  AND s.waterbody_key IS NOT NULL
),
-- CTE 2: filter to keys on habitat streams (only when from/extra_where)
wbkeys_filtered AS (
  SELECT DISTINCT n.waterbody_key
  FROM wbkeys_network n
  JOIN bcfishpass.streams_co_vw f USING (waterbody_key)
  WHERE f.spawning > 0 OR f.rearing > 0
)
SELECT ... FROM lakes JOIN wbkeys_filtered ...
```

## Key principle

- Traversal: ALWAYS on `fwa_stream_networks_sp` (has ltree GiST indexes)
- Filtering: on `from` table with `extra_where` (cheap join, no ltree)
- When no `from`/`extra_where`: single CTE, same as current behavior

## Changes needed

1. `frs_network_waterbody()` — rewrite SQL to two-CTE when `from`/`extra_where` present
2. `frs_network_one()` — pass `from` from waterbody spec (already has this logic, keep it)
3. `frs_network()` — resolve `default_from` from first stream table in list
4. Example: all waterbodies vs habitat-filtered, with plot
5. Tests: unit (SQL shape) + integration (count reduction)

## What stays the same

- `frs_network_direct()` — untouched
- All other functions — untouched
- Standalone `frs_waterbody_network()` — keeps FWA defaults
- `.frs_opt()` — not involved here

## Checklist

- [ ] Rewrite `frs_network_waterbody()` SQL (both with/without upstream_measure)
- [ ] Wire `from` through `frs_network_one` and `frs_network`
- [ ] Unit test: SQL has two CTEs when from specified
- [ ] Integration test: count reduction with extra_where
- [ ] Example: all vs habitat-filtered waterbodies
- [ ] 441+ tests pass
