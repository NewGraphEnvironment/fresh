# Findings — fresh#191

## What the lake-adjacency rule does today

`.frs_connected_waterbody` (R/frs_habitat.R:1465–) Phase 2 — upstream spawning:

1. `rearing_segs` CTE: rearing segments per species (already gated on `area_ha >= rear_lake_ha_min` by classify upstream)
2. `spawn_upstream` CTE: spawn-eligible segments (`hs.spawning IS TRUE`, gated on access + spawn rule by classify upstream) that are upstream of any rearing segment via `fwa_upstream` or same-blkey
3. `clustered` CTE: `ST_ClusterDBSCAN(geom, 1, 1)` — group contiguous spawn-upstream segments
4. `cluster_geoms` CTE: `ST_Collect(geom)` per cluster
5. `valid_clusters` CTE: cluster geom within 2 m (`ST_DWithin`) of a qualifying waterbody polygon
6. INSERT id_segments from clusters that survived (5)

The cluster + lake-adjacency step is a *restrictive* filter on top of an already-correct accessibility-gated spawn classification. Dropping it credits any spawn-eligible segment that's:

- upstream of a qualifying rearing lake (preserved via `EXISTS rearing_segs`)
- accessible from it (preserved via classify having gated `hs.spawning IS TRUE` on access)

bcfishpass source: [`load_habitat_linear_sk.sql`](https://github.com/smnorris/bcfishpass/blob/main/model/02_habitat_linear/sql/load_habitat_linear_sk.sql) lines 137–253.

## Why drop the cluster step

bcfp's rule misses ecologically-real spawning reaches: tributaries above a rearing lake whose spawn-eligible segments don't form a single contiguous cluster touching the lake. Steep connectors, sub-cw stretches, or beaver complexes break the cluster. Sockeye DO spawn well above nursery lakes in such reaches.

## Why a knob (not just drop it)

bcfishpass parity tests need the current behaviour. Default-bundle wants the relaxed behaviour. One param, two behaviours — clean.

Default = TRUE so existing callers (link bcfishpass-bundle, anything else with no rules.yaml entry) keep current behaviour. Caller passes `lake_adjacent: no` in rules.yaml when they want the relaxed Phase 2.

## Validator update

`.frs_load_rules` validates allowed keys under `spawn_connected` (R/frs_params.R). Need to add `lake_adjacent` to the allowed list, otherwise rules.yaml with the new key fails validation. Tested in `test-frs_params.R:287` (errors on unknown keys).

## Versions at start

- fresh main: ec0c770 (0.25.0)
- bcfishpass: 440bc1e (2026-04-28)
- link main: 7210baf (0.20.0)
