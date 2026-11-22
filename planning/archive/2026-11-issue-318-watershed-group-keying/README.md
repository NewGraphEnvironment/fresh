## Outcome

Backlog move 1 (#318) fixed the three watershed-group keying issues in one branch.

- **#294.** The issue said a job deleted another group's barriers. Measurement showed it was not a deletion. The gradient barrier finder reads every segment of a blue line, so the blue-line delete covered exactly what the insert wrote back. The real defect was last writer wins on gradient classes: the second group's run replaced the first group's barriers with classes built from its own species.
  - Persisted barriers now carry the parent segment and group of the segment each falls on.
  - Each job writes only its own segments' barriers, through `.frs_persist_barriers()`, keyed by `linear_feature_id` like `to_streams`, in one transaction.
  - A `to_barriers` table written before this release is refused, with a message to drop it and re-run.
  - Code-check round 1 found that FWA's `upstream_route_measure` can stop millimetres short of the next segment's start. Barriers rounded into those gaps matched no segment and dropped out of the table. The `parent = TRUE` arm of `.frs_enrich_breaks()` now bounds each segment by the next one's start.
- **#308.** A network with a NULL `watershed_group_code` is refused at every exported reader and writer of habitat rows. A call-graph test keeps new entry points from skipping the check.
- **#277.** `frs_habitat_overlay()` direct mode refuses an `id_segment` join that leaves out a key the target carries.

The durable record is `research/id_segment_identity.md` (sections on persisted barriers and on the NULL-group refusal).

The owner asked that nothing here break link, fresh's main production user. That was checked three ways:

- a mechanical diff of every fresh function link can reach;
- whether the new guard can fire on link's tables (it cannot);
- link's whole test suite against fresh `main` and against this branch, which came out identical.

## Measurement

- **The #294 premise** (`data-raw/barrier_span_294.R`, `docker/` fwapg, 2026-11-22):
  - 157 mainstem blue lines span watershed groups. The issue's 259 counts every line.
  - 108 of those 157 join groups whose species give different gradient thresholds.
  - On 5 of 12 sampled two-group lines, the second group's job changed the first group's barriers: 41 of 126 positions in all, 26 of 73 on GUIC/LNIC.
  - That turned "a job deletes the neighbour's barriers" into "the last job's classes win". Keying on the group alone would not have helped, so the owner chose the parent-segment key at the gate.
- **The wrong turn:** the 12-line sample found 0 barriers outside every segment, and the first write-up treated keying on the parent as lossless. Code-check round 1 measured whole groups:
  - unkeyed barriers in FWA's gaps: BULK 39 of 104,550, MORR 27 of 68,270, LFRA 41 of 52,430;
  - BULK has 510 such gaps over 1 mm;
  - after the `lead()` bound: 0 of 104,137 in BULK, 0 of 68,364 in MORR, 0 of 52,753 in LFRA (round 3).
- **Guard cost:** `.frs_group_required()` takes 0.02 s per call on SETN (66,083 segments, the largest group). The first, cold read was 2.8 s.
- **link compatibility:**
  - 123 fresh functions are reachable from link's 23 entry points, and 10 changed. On link's path the only change is the NULL-group guard, which link's `<schema>.streams` cannot trip: it is built with `WHERE watershed_group_code = <aoi>`.
  - link's suite against fresh `main` and against the branch: 1,492 tests, every status and pass count identical.
  - Not run: a full link pipeline per group, which needs link's provincial persist schema. link's `data-raw/pretest_run.sh` should run when link moves its fresh pin (`v0.52.0`) to 0.56.0.
- **fresh's own suite:** 0 failed, 2756 passed, 7 skipped (bcfishpass schema absent, no fwapg trial), 179 s.
- **Code-check:** 3 rounds, ended on an enumeration of every assertion the branch adds or changes. Three of the four findings were checks that could not fail against the defect they targeted; each is now fixed and shown to fail by mutation.

## Evidence

`data-raw/logs/barrier_span_294/*`

Closed by: PR (opened from branch `318-backlog-move-1-watershed-group-keying-fi`), release commit 42663b0
