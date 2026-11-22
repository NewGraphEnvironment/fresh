# Review round 3: planning/backlog.md (#315)

## Checklist read

- `backlog_moves.sh` (published copy 9970254) header: list, next, tick, free, lanes semantics.
- `planning/backlog.md` in full, on branch `315-backlog-sweep-batch-the-52-open-issues-i` (clean tree).
- Bodies of umbrellas #318-#325 (`gh api .../issues/<N> --jq .body`), and the 34 member issues' bodies and comments.
- `origin/main` at 1dcc7a3 (fetched): `R/`, `research/`, `tests/`, `data-raw/`, `CLAUDE.md`, to resolve what each fix reaches.

What was checked and came out clean:

1. **lanes, on the real file (read-only):** 21 CLASH pairs. Each is ordered through `waits on`, directly or transitively: 2-5 (5>3>2), 4-6 (6>3>4), 4-8 (8>3>4), and the other 18 directly. No cycle: a topological order exists (1, 7, 4, 2, 3, 6, 5, 8). The pairs left unordered are (1,7), (2,7) and (2,4). The other five FREE pairs (2-8, 5-7, 6-7, 6-8, 7-8) are ordered transitively.
2. **list / next / free:** rc 0. next is `#318`, free offers `#318` (A) and `#324` (D). I ticked each of the eight umbrellas on its own fresh copy in the scratchpad: each gave `TICKED move <m>`, and the diff touches only that row. Ticking in topological order on one copy, free offers {1,7}, then {2,4}, then {3}, {6}, {5}, {8}, then `NONE`. So no `waits on` names a move that can never be ticked.
3. **Umbrella Touches:** every batch Touches line in #318-#325 is identical to the file's (lines 45, 53, 61, 69, 77, 85, 93, 101, 109); #320 carries both batch 4's and batch 5's.
4. **Public-repo scan:** the file and all eight umbrella bodies contain no private repo names (soul, compost, rtj, goat, sred, rfp, ...), hosts, ports, tunnels or env files. `NewGraphEnvironment/fwapg#36` and `link` are public NewGraphEnvironment repos.
5. **Enumeration coverage I tried that did not produce a cross-batch defect:**
   - #189 names `tests/testthat/test-frs_habitat{,_overlay}.R` and `inst/extdata/configs/...`.
   - #302 also reaches `research/fwa_downstream_walk.md:46` (the same "22 of 40,495").
   - #304's GEOS move makes the `research/fwa_downstream_walk.md:130` and `test-frs_near_river.R:186` GEOS 3.9.0 notes stale.
   - #239 and #251 reach `CLAUDE.md` (its `frs_col_join()` subquery and area-floor notes).
   - #299's renames are cited in `research/id_segment_identity.md`, which batch 9 already lists.
   - Batch 1 reaches `R/frs_db_conn.R`, `R/frs_feature_index.R` and `R/frs_order_child.R`, and batch 2 reaches `R/frs_cluster.R`.

   Each of these misses a Touches line, but none falls in another batch's set across an unordered pair.

## Findings

### 1. [gap, medium] planning/backlog.md:93: batch 7 reaches `R/utils.R` through `.frs_geom_select()`, so move 7 is unordered against moves 1 and 2, which share it

- **What:** #306's fix is batch 7's. Its second option is "Simplify polygons client-side in sf when `simplify_m` is given". That fix lands in the shared builder both polygon fetchers call: `R/frs_lake_fetch.R:95` and `R/frs_wetland_fetch.R:95` call `.frs_geom_select(cols, simplify_m)`, defined at `R/utils.R:853`. Its `normalize = TRUE` branch (`R/utils.R:853-862`) exists only for polygons, because the stream fetcher passes `normalize = FALSE` (`R/frs_stream_fetch.R:114`). Moving polygon simplification out of SQL therefore leaves that branch orphaned, and removing it edits `R/utils.R`.
- **Evidence:** batch 7's Touches line lists the two fetchers and `R/frs_watershed_at_measure.R`, but not `R/utils.R`. `R/utils.R` is in batch 1 (move 1, line 45) and batch 3 (move 2, line 61).
  - Moves 1 and 7 both have `waits on` `—`.
  - Move 2 waits on 1 only.
  - So `free` offers 7 beside 1 now, and beside 2 once 1 is ticked, and lanes reports `FREE 1 7` and `FREE 2 7`.
  - This is the one-hop helper dependency the enumeration does not follow: it resolved #306's named calls (`frs_lake_fetch()`, `frs_watershed_at_measure()`) to their files, but not what those call.
- **Option-dependent:** #306's first option (docs only) does not touch `R/utils.R`.
- **Two fixes:**
  - Add `R/utils.R` to batch 7 and order 7 with 1 and 2. That costs lane D its independence.
  - Or write into batch 7 (and #324) that the #306 fix must leave `R/utils.R` alone, for example by simplifying in each fetcher and leaving `.frs_geom_select()` as it is. That holds only as long as the plan honours it.

Rule: none

### 2. [ping, medium] umbrella #324 body, issue table row for #68: a bare `smnorris/fwapg#189` cross-referenced the upstream issue

- **What:** the table row copies #68's title, "Remove fwapg function workaround when smnorris/fwapg#189 is fixed", unbackticked. GitHub turned that into a cross-reference on the upstream issue.
- **Evidence:** `gh api repos/smnorris/fwapg/issues/189/timeline` shows a `cross-referenced` event from `NewGraphEnvironment/fresh#324 Backlog move 7: docker image and loader rebuild` at 2026-11-22T16:19:52Z. The earlier events are from #68 (2026-04-03) and #71.
  - The ping cannot be withdrawn now.
  - Wrapping the reference in backticks in #324's body stops it from showing as a live link.
  - The generator that writes umbrella issue tables from titles should backtick any `owner/repo#N` that is not ours, so the next sweep's umbrella for this batch does not ping upstream again.

Rule: none

### 3. [prose, low] planning/backlog.md:23: "parity (C) ... can run beside lane A" no longer holds

- **What:** after this round's waits, move 6 (lane C) waits on 1, 2 and 3, and moves 5 and 8 (lane A) wait on 6. When `free` first offers 6, every lane A move is either ticked or waiting on it.
- **Evidence:** the topological walk in item 2 of the checklist offers {3}, then {6}, then {5}, then {8}, one at a time. Only B (beside move 2) and D (beside move 1) ever run beside a lane A move.
  - The sentence and move 6's `C` label tell a reader, or a dispatcher reading the lane column, that parity is a parallel track. It is the middle of lane A's chain (it clashes with 1, 2, 3 and 5).
  - Either relabel move 6 `A` and drop "parity (C)" from line 23, or reword line 23 to say C runs between moves 3 and 5.

Rule: none
