## Outcome

`frs_network_features(direction = "downstream", aoi = )` now copies the AOI's segments into an indexed, analyzed session temp table and walks only the features `fwa_downstream()` can reach: those on one of the AOI's blue lines, or whose wscode is an ancestor of, or equal to, a segment's. The feature id is the last `ORDER BY` key in both directions. The issue proposed the prefilter alone. Exploration showed that on fresh's own documented shape (a province-wide `segments` with `aoi`) the prefilter alone is neutral to catastrophic: the planner materializes the admitted set and cross-loops it with the segments. The v0.44.0 SQL was already catastrophic there for large views, because a GiST `@>` estimate of 77,961 rows against about 314 actual pushes the planner off the segment-driven plan. Both parts are needed. A read-only fenced-lateral form was rejected, at 2.6× slower on link's shape. The live test's fixture moved from VICT with the whole network to SKGT with a 1/25 sample plus NULL-coded copies, after mutation runs showed VICT could not see either prefilter arm. Released as fresh 0.45.0. The durable verdict is in `research/fwa_downstream_walk.md`, "Prefiltering the feature side".

## Measurement

The local fwapg, `fresh_default.streams` with `aoi`, link's CH, BT and anthropogenic barrier views, and four groups. The v0.44.0 SQL hit the 10-minute cap on all 8 CH and BT walks. The new form ran them in 0.34-8.35 s, temp table included, so more than 71× (LSKE CH) to more than 1,775× (LKEL BT) faster. Against link's shape (the old SQL on an indexed temp copy of the group), the new form is 7.9-33× faster, which isolates the prefilter's share. Anthropogenic walks went from 0.85-4.51 s to 0.17-1.74 s, 2.6-4.9×. The temp table costs 0.07-0.15 s for 7-14 k segments and 0.7 s for 77 k. Sorted digests agree in 12 of 12 walks. This turned link#261's temp-table-shape finding into a measurement on fresh's own shape, and it changed the design from "prefilter" to "temp table plus prefilter".

The wrong turns are kept in `findings.md`:
- the issue's form as written regressed fresh's shape;
- the VICT live test passed with either arm removed;
- four code-check rounds found no bug in R code but corrected seven stated claims, one of them inside the previous round's fix (the pooling failure points).

## Evidence

- `data-raw/logs/network_features_272/` (`walks.tsv`, README), from `data-raw/network_features_prefilter.R`
- exploration probes, mutation tables and the failure-path enumeration in this directory's `findings.md`
- review rounds in `review-round*.md`

## Owed

- Comment on link#261 / link#393 that fresh ≥ 0.45.0 carries the prefilter and scopes the AOI itself, so `lnk_access()`'s scoped table (`zz_lnk_streams_<aoi>`, a real table in the view schema) is no longer load-bearing for the walk, though it still serves `lnk_pipeline_access()`'s own `segments_sql` (S3: each of the up to six calls per group now builds and drops its own temp, 0.2 s each). Name the new session requirement and the two link scripts that set `default_transaction_read_only = on` before calling the function (`data-raw/logs/recompute_cost_261/walks.R:108`, `walk_prefilter.R:109`), which would now fail on a real call (A2)

Closed by: commit 25946a6 (Release v0.45.0) / PR to follow on branch `272-frs-network-features-every-walk-probes-t`
