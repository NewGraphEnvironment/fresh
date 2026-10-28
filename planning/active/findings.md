# Findings — Connectivity passes join a shared habitat table on id_segment alone (#242)

## Issue context

**If done:** running `frs_habitat()` into one `to_habitat` for several watershed groups (in one call or one call per group) leaves each group's habitat exactly as its own run produced it. **If never:** a later group's connectivity pass can clear or keep earlier groups' `spawning` / `rearing` rows whose `id_segment` happens to collide, with no error.

## Problem (fresh@30e8733 (v0.36.3))

`frs_habitat(to_habitat =)` writes every WSG job into one habitat table (`R/frs_habitat.R`, both job paths). The connectivity passes then run per job against that shared table with only the job's own streams table, and they join on `id_segment` alone:

- `frs_cluster()`, all three directions (`R/frs_cluster.R`: clustering CTEs, the `valid_clusters` lookups and the final `UPDATE ... WHERE h.id_segment = c.id_segment`).
- `.frs_distance_filter()` (`UPDATE ... FROM <streams> s WHERE h.id_segment = s.id_segment`).
- `.frs_connected_waterbody()`, whose subtractive step has no group scope at all:
  `UPDATE <habitat> SET spawning = FALSE WHERE species_code = 'SK' AND spawning AND id_segment NOT IN (<this job's qualifying ids>)`.
  That clears SK spawning in **every other group** in the table.

`id_segment` is not unique across groups. Split segments get `max(id_segment) + row_number()` per working table (`R/frs_break.R`), and on NATR the next 5,000 ids already belong to 1,451 MIDR and TAKL segments (measured during #240's plan review).

**Who is affected:** standalone fresh callers that accumulate several groups in one `to_habitat`. link is not affected: its connect phase passes a per-WSG working schema's `streams_habitat` (`link/R/lnk_pipeline_connect.R`).

#240's `.frs_bucket_connected()` (PR #241) already joins on `(id_segment, watershed_group_code)` and has a test with colliding rows from another group (`tests/testthat/test-frs_bucket_connected.R`). This issue brings the older passes in line.

## Proposal

1. Every habitat join in the connectivity passes matches `watershed_group_code` too. Every subtractive UPDATE is restricted to the groups present in `table`.
2. A test in the shape of #240's: a second group's rows share ids with the first, and each pass leaves them untouched.
3. Restore the bug in each pass and confirm its test goes red.

Relates to #240, NewGraphEnvironment/link#203 (the same id collision on the persist side).


## Verified before the baseline

| claim | how checked | verdict |
|---|---|---|
| Habitat table carries `watershed_group_code` | DDL at `R/frs_habitat_classify.R:230`, INSERT at `:372` | yes, `character varying(4)` |
| `link` is unaffected and already needs the column | `link/R/lnk_pipeline_connect.R:101` calls `.frs_run_connectivity` on a per-WSG `<schema>.streams_habitat`; `link/DESCRIPTION` pins `fresh (>= 0.44.0)`, which ships `.frs_bucket_connected()` | yes |
| Shipped params make only two of the five passes live | `inst/extdata/parameters_fresh.csv`: `cluster_direction` is `both` for CH, CO, SK, ST, WCT; `cluster_spawn_direction` is blank, which `.frs_run_connectivity()` defaults to `both` | `.frs_cluster_both()` and `.frs_connected_waterbody()` are live; the other three need a direct `frs_cluster()` call or custom params |
| Local DB can run the synthetic tests | `fwapg`, 7 `fwa_upstream`/`fwa_downstream` overloads, 2 `fwa_downstreamtrace`, `fwa_stream_networks_sp` and `fwa_lakes_poly` present | yes |
| `frs_habitat_overlay()` has the same defect | `R/frs_habitat_overlay.R:251`, `h.id_segment = s.id_segment` in the bridged join feeding an additive UPDATE; exported (`NAMESPACE:26`) | yes — follow-up issue, not this branch |

## Enumeration of unscoped habitat touches

Every site where a habitat row is matched, read or written without a
`watershed_group_code` predicate, walked from the source rather than recalled.
`R/frs_habitat.R:1401`, `:1440`, `:1441`, `:1466` and `:1474` are
`.frs_bucket_connected()` and already correct.

| file:line | site | phase |
|---|---|---|
| `R/frs_cluster.R:130` | `species = NULL` resolution reads every group | 5 |
| `R/frs_cluster.R:209` | `.frs_cluster_upstream()` `clustering` CTE | 4 |
| `R/frs_cluster.R:233` | `.frs_cluster_upstream()` `valid_clusters` | 4 |
| `R/frs_cluster.R:253` | `.frs_cluster_upstream()` final UPDATE | 4 |
| `R/frs_cluster.R:291` | `.frs_cluster_downstream()` `clustering` CTE | 5 |
| `R/frs_cluster.R:320` | `.frs_cluster_downstream()` `has_connect` EXISTS | 5 |
| `R/frs_cluster.R:372` | `.frs_cluster_downstream()` final UPDATE | 5 |
| `R/frs_cluster.R:429` | `.frs_cluster_both()` `phase1_ids` query | 3 |
| `R/frs_cluster.R:444` | `.frs_cluster_both()` `tmp_clusters` build | 3 |
| `R/frs_cluster.R:466` | `.frs_cluster_both()` phase 2 join | 3 |
| `R/frs_cluster.R:516` | `.frs_cluster_both()` phase 3 `LEFT JOIN` — also multiplies rows, corrupting this group's own distances | 3 |
| `R/frs_cluster.R:563` | `.frs_cluster_both()` inlined `phase1_protect` | 3 |
| `R/frs_cluster.R:574`, `:583` | `.frs_cluster_both()` both UPDATE branches | 3 |
| `R/frs_habitat.R:1532` | `.frs_distance_filter()` outer UPDATE | 4 |
| `R/frs_habitat.R:1537` | `.frs_distance_filter()` inner `NOT EXISTS` join | 4 |
| `R/frs_habitat.R:1795` | `.frs_connected_waterbody()` `origins_sql` | 2 |
| `R/frs_habitat.R:1826` | `.frs_connected_waterbody()` `rearing_segs` | 2 |
| `R/frs_habitat.R:1832` | `.frs_connected_waterbody()` `spawn_upstream` | 2 |
| `R/frs_habitat.R:1884` | `.frs_connected_waterbody()` subtractive UPDATE — **no group scope at all** | 2 |
| `R/frs_habitat.R:1919` | `.frs_connected_waterbody()` Phase 3 additive UPDATE | 2 |

## Errors Encountered

| Error | Resolution |
|-------|------------|

## `fwa_upstream()`'s 4-arg form admits equality

`fwa_upstream(wscode_a, localcode_a, wscode_b, localcode_b)` with
`wscode == localcode` on both sides reduces to `wscode_b <@ wscode_a`, which is
TRUE when the two are equal (`whse_basemapping.fwa_upstream`, 4-arg, read with
`pg_get_functiondef`; confirmed by a truth-table query, 2026-10-28).

Consequence for the fixtures: every segment the helper builds on one `wscode`
counts as upstream of every other on that code, because the helper sets
`localcode_ltree = wscode_ltree`. A segment that must be **strippable** by
`spawn_upstream` therefore has to sit on a separate river (`wscode = "200"`),
which is not a descendant of `"100"`. A fixture that relied on downstream
position alone within one wscode would have been unable to fail.
