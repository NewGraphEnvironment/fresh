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
| `devtools::test()` reported a failure that a re-run could not reproduce | Two test runs were hitting the database at once — the mutation sweep's last round and a suite run started while it was still going. `test-frs_cluster.R:153` and `test-utils.R:33` create fixed table names in the shared `working` schema (`working.test_cluster_streams`, `working.test_idx_idem`), so concurrent runs drop each other's tables. Pre-existing; the new tests use `pg_temp` only, which is session-local. Don't run the suite beside anything else that touches the same database. |
| `Geometry has Z dimension but column does not` inserting real FWA rows | Real `fwa_stream_networks_sp` geometry is LineStringZM; the shared fixture table is 2D. `ST_Force2D()` on insert, rather than widening the DDL the synthetic fixtures depend on. |
| Both downstream tests skipped, which reads identically to passing | The run-time fixture discovery required two streams with different level-3 wscode prefixes, and no candidate pair qualified. Wrong predicate: what matters is that neither wscode is an ltree **ancestor** of the other. Siblings are fine. |

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

## The phase-3 LEFT JOIN corrupted the job's own distances

`R/frs_cluster.R`'s phase 3 joined habitat with `LEFT JOIN … ON st.id_segment =
h2.id_segment AND h2.species_code = sp`. A colliding row in another group
therefore **duplicated the streams row**, and

```sql
-st.length_metre + SUM(st.length_metre) OVER (
  PARTITION BY cm.cluster_id ORDER BY st.wscode_ltree DESC, …)
```

counted that segment once per duplicate. Measured on the fixture in
`test-frs_connectivity_wsg.R`: spawning 2000 m below the cluster, two
intermediate segments each carrying one extra habitat row in another group, cap
2500 m — the trace read 4000 m and the cluster was invalidated.

So this site was not only a cross-group leak. It returned a wrong answer for the
watershed group being processed, and the other group's rows needed no flags set
to cause it.

## The confluence boost can validate a cluster from an unrelated river

`subpath(cm.wscode_ltree, 0, -1)` on a one-label wscode is the **empty ltree**,
and every ltree is a descendant of it. So for a cluster minimum below
`confluence_m`, the parent-stream branch
`FWA_Upstream(subpath(wscode, 0, -1), wscode, st.wscode, st.localcode)` reduces
to a string comparison that admits `label_connect` on any river sorting above
this one. Real FWA wscodes have many labels, so this is reachable in the tests
rather than in production — every cluster minimum in the fixtures sits at
drm >= 1000 to keep the branch out of play. Not fixed here: out of scope for
fresh#242, and worth its own look before anyone writes a fixture with
single-label wscodes below the confluence tolerance.

## Mutation table: which test catches which site

Each site had the single-key join restored, one at a time, in a copy of the
package sources, and `test-frs_connectivity_wsg.R` + `test-frs_bucket_connected.R`
were run against it (`data-raw/`-style harness kept in the session scratchpad; the
unmutated copy was confirmed 0 red / 0 skipped first, so a result means something).

**First result: 15 of 19 sites pinned by a named test, 4 not.** The conclusion
drawn from that — that the four were unobservable — was wrong; see the correction
below, after which all 19 are pinned.

| site | caught | by |
|---|---|---|
| `cluster_upstream` clustering join | no | — see below |
| `cluster_upstream` valid_clusters join | yes | cluster upstream … not rescued by them |
| `cluster_upstream` UPDATE | yes | cluster upstream … not rescued by them |
| `cluster_downstream` clustering join | no | — see below |
| `cluster_downstream` has_connect | yes | cluster downstream is not rescued by … |
| `cluster_downstream` UPDATE | yes | cluster downstream never clears … |
| `cluster_both` tmp_clusters join | no | — see below |
| `cluster_both` phase 2 join | yes | cluster both leaves another group's rows alone … |
| `cluster_both` phase 3 LEFT JOIN | yes | another group's rows do not inflate the … distance |
| `cluster_both` UPDATE | yes | cluster both leaves another group's rows alone … |
| `cluster_both` phase-1 predicate `IS NOT TRUE` → `= FALSE` | yes | cluster both leaves another group's rows alone … |
| `bucket_connected` hab_join (pre-existing, #240) | yes | another watershed group's rows sharing an id_segment … |
| `distance_filter` outer UPDATE | yes | distance_filter never clears another group's rows |
| `distance_filter` inner NOT EXISTS | yes | distance_filter is not rescued by … |
| `connected_waterbody` origins_sql | yes | connected_waterbody takes no trace origin from … |
| `connected_waterbody` rearing_segs | yes | connected_waterbody takes no trace origin from … |
| `connected_waterbody` spawn_upstream | no | — see below |
| `connected_waterbody` subtractive UPDATE | yes | connected_waterbody never clears another group's … |
| `connected_waterbody` additive UPDATE | yes | the additive spawn_connected step promotes no … |
| the verbose count sites (`.frs_wsg_in()` neutered) | yes | the verbose progress lines count this job's groups … (4 assertions red) |

### Correction: that claim was wrong, and three of the four were load-bearing

**What this section said first, and why it mattered.** It said the four sites the
sweep could not catch were defence in depth whose removal "cannot change the
final habitat state". Review round 2 disproved it with measured counterexamples,
and the error is the dangerous kind: a sentence asserting there is nothing left
to test is what licenses a later refactor to drop a predicate while the suite
stays green. The code was correct throughout; only this write-up was wrong.

**The flawed step.** I reasoned that a phantom habitat row from another group is
a *duplicate* of a row the CTE already holds, and duplicates change nothing
(`minpoints = 1`, `DISTINCT ON` picks the same minimum, an UPDATE applies once).
That holds only when the two groups **agree** on the flag — which is the axis
every fixture in the file happened to hold fixed. When the other group says
`label_cluster = TRUE` on an `id_segment` whose own group says `FALSE`, the CTE
*gains* a segment: clusters merge, `cluster_minimums` moves, and this group's
answer changes.

Reproduced before accepting it (`frs_cluster(direction = "both")`, one mainstem
on a multi-label wscode so the `subpath` boost below is not involved, cap 500 m,
minima at or above 1000 m against `confluence_m = 10`): shipped gives
`TEST/2 rearing = FALSE`; with only the `tmp_clusters` predicate deleted,
`TRUE`. The phantom drops the minimum from drm 2000 to drm 1000, from where the
phase-3 trace does reach spawning inside the cap.

The fourth site, `.frs_connected_waterbody()`'s `spawn_upstream` join, failed for
a second reason. My argument reasoned only about the wrongly-added stream's own
row, which is sound for `lake_adjacent = FALSE` — and `TRUE` is the default,
where `clustered` / `cluster_geoms` / `valid_clusters` credit a whole cluster for
touching a lake, so the added stream lends its adjacency to the rest of its
cluster.

**All four now have their own test, and each is pinned:**

| site | test |
|---|---|
| `cluster_both` tmp_clusters join | another group's rearing on an id this group calls FALSE does not move the cluster minimum |
| `cluster_upstream` clustering join | the same holds for the upstream direction's clustering CTE |
| `cluster_downstream` clustering join | the same holds for the downstream direction's clustering CTE |
| `connected_waterbody` spawn_upstream | another group's spawning does not lend lake adjacency to this group's cluster |

The upstream fixture turned on the same-blue-line measure rather than a trace
distance, after a first attempt asserted the wrong thing: with
`localcode_ltree = wscode_ltree`, which is how the helper builds segments, the
8-arg `FWA_Upstream` takes its simple branch and ignores measures entirely, so a
tributary counted as upstream of a position above its mouth. The lake fixture
measures its own geometry before relying on it — a line 500 m out from one
boundary vertex can sit back inside the polygon, which is how its first version
quietly credited the segment it meant to exclude.

**So the enumeration is 19 of 19, not 15 of 19.** Two predicates remain
uncatchable by a behavioural test, and both are correct to keep for stated
reasons rather than absent ones: `.frs_wsg_in()`'s inner column qualification
(a `table` lacking the column would fail later anyway, so no path ships a wrong
number — pinned by a text assertion in `test-utils.R` instead), and
`frs_habitat_classify()`'s progress count (reaching it for real needs a
classifiable streams table, so it is pinned on the SQL in
`test-frs_habitat_classify.R`).

## Enumeration: every statement in `R/` that reads a habitat table

Walked from the source — `grep` for each function whose signature names a
habitat table, then every `FROM %s` / `UPDATE %s` / `count(*) FILTER` /
`SELECT DISTINCT` in those files — rather than recalled. This is what ends the
review loop: not a reviewer saying it is complete, but a list whose every member
has a verdict.

| file | statement | scoped |
|---|---|---|
| `frs_cluster.R:139` | `species = NULL` resolution | yes, `EXISTS` on `table` |
| `frs_cluster.R:153`, `:176` | before / after counts | yes, `.frs_wsg_in()` |
| `frs_cluster.R:223`, `:245`, `:267` | upstream clustering, valid_clusters, UPDATE | yes |
| `frs_cluster.R:309`, `:339`, `:390` | downstream clustering, has_connect, UPDATE | yes |
| `frs_cluster.R:467`, `:487`, `:549`, `:604` | both: tmp_clusters, phase 2, phase 3, UPDATE | yes |
| `frs_habitat.R:1372` | bucket count | yes, `.frs_wsg_in()` |
| `frs_habitat.R:1476` | bucket hab_join | yes (#240) |
| `frs_habitat.R:1519`, `:1577` | distance_filter counts | yes, `.frs_wsg_in()` |
| `frs_habitat.R:1538`, `:1544` | distance_filter UPDATE, NOT EXISTS | yes |
| `frs_habitat.R:1783`, `:1959` | connected_waterbody counts | yes, `.frs_wsg_in()` |
| `frs_habitat.R:1809`, `:1841`, `:1848` | origins_sql, rearing_segs, spawn_upstream | yes |
| `frs_habitat.R:1910`, `:1947` | subtractive and additive UPDATEs | yes |
| `frs_habitat_classify.R:245` | per-WSG DELETE | yes, already was |
| `frs_habitat_classify.R:398` | per-species progress count | yes, `.frs_wsg_in()` |

Checked and **not** in this class, so correctly unscoped:
`frs_habitat_classify.R:164` reads the streams table, not habitat; `:322` counts
a per-threshold temp table derived from `table`; `:502` counts the
caller-supplied `barrier_overrides`.

Outside this branch, unscoped, and all four in
[#277](https://github.com/NewGraphEnvironment/fresh/issues/277):
`frs_habitat_overlay.R:251`, `frs_order_child.R:271` (and its own count at
`:291`), `frs_habitat.R:515` and `:675` (the custom-AOI persist DELETE), and the
habitat table's absent unique index.

Nothing else in `R/` reads a habitat table.
