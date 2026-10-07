## Outcome

Lake and wetland rearing buckets (`lake_rearing` / `wetland_rearing`) are now sized by polygon area only, under both `cw` and `mad`. The old predicate tested the channel width or `mad_m3s` of the line through the polygon, which sized the inflow; under `cw` it also returned `FALSE` for a species with no rear width range. This changes every bundle on upgrade.

A species' first rear `waterbody_type: L` / `W` rule may carry `requires_connected: spawning` with `connected_distance_max`. A new pass in `.frs_run_connectivity()` (`.frs_bucket_connected()`) then keeps a polygon only if same-species spawning is on its lines, downstream of one of its outlets within the distance, or upstream of it within the distance. The polygon is the unit. `rearing` is never touched.

The loader rejects `requires_connected` on any other rear rule; before, it was accepted and read by nothing. `.frs_trace_downstream()` was generalised, with its existing SK call pinned byte for byte by a golden SQL fixture.

What was learned:
- **Connectivity passes on a shared habitat table must match `watershed_group_code`.** The older passes do not. That is drafted as a separate issue.
- **The fixtures were the hard part.** Two code-check rounds each found a test that could not reach its failure mode:
  - straight-line distance equalled network distance, so the prefilter, not the cap, was deciding;
  - no test pinned either trace's origin.

  The loop ended by enumerating every choice that sets a distance or a result (11 mutations, each red), not on a quiet round.

## Measurement

BT bucket km (polygons) on link's persisted `fresh_default` with link's `default` rules, local fwapg, at `b38c40a`:

| WSG, bucket | persisted | area only | connected 0.5 km | 3 km | 10 km |
|---|---|---|---|---|---|
| NATR lake | 309.9 (95) | 521.4 (119) | 486.6 (78) | 514.5 (111) | 517.4 (114) |
| NATR wetland | 683.9 (886) | 1,287.3 (2,148) | 870.3 (938) | 1,190.9 (1,860) | 1,265.3 (2,087) |
| PARS lake | 54.9 (31) | 101.5 (41) | 81.4 (23) | 96.3 (36) | 101.5 (41) |
| PARS wetland | 190.2 (306) | 437.4 (766) | 325.3 (441) | 421.7 (718) | 437.4 (766) |

- **Area only reproduces link#307's `cw` figures** (521 / 1,287 km). That confirms the size test is what link#307 measured shrinking under `mad`.
- **Disconnected wetlands are the larger effect.** At 500 m, NATR loses 1,210 of 2,148 wetland polygons.
- **Speed: ~48 s → 2.5 s per species per WSG.** The first live runs took ~50–70 s per species per WSG. The wrong turn was blaming the trace. Profiling showed it needs a GiST on `geom` (working tables have none) *and* current statistics; neither alone was enough (57 s with the index, 50 s with ANALYZE). With both it runs in 2–5 s, identical output. The pass now creates the index if missing and ANALYZEs.
- **Test and check sweep.** `devtools::test()` FAIL 0 / PASS 1201. `devtools::check()` is identical to `main`: the same 12 pre-existing `test-frs_network_features.R` failures (no `tibble` in the check library), the same warnings and notes.

## Evidence

- `data-raw/logs/bucket_connected_240/*`
- `data-raw/bucket_connected_check.R`
- review records: `review-p*-round*.md` in this directory

Closed by: PR for #240 (branch `240-lake-and-wetland-rearing-buckets-size-by`)
