# Code check, round 5: #259 near_river (branch diff merge-base...HEAD, 24e0a3b)

## Checklist read

- code-check-infra.md: in full.
- code-check.md: the prose of all 14 H3s under `## Mechanisms` (I skipped the table rows). I did not read the other headings, about 30.
- code-check-r.md: I read 6 sections: "Postgres row order is never fixed…", "`sprintf("%g", x)` writes `Inf` and `NA`…", "An `information_schema` lookup…", "`ifelse()` with an all-NA test…", "A database driver's value is not a base R type…" and "`on.exit()` at a script's top level never fires". I did not read the other 107 or so.
- code-check-spatial.md: I read 3 sections: "FWA `upstream_route_measure` misses…", "FWA main flow is not edge type 1000 alone" and "A Freshwater Atlas main stem's downstream end…". I did not read the other 82 or so.
- code-check-shell.md: I read none, because the diff has no shell code.

## How I tested

- **BULK.** "BULK" below means my scratch copy `zz_review5_nr.streams`:
  - It copies `working_bulk.streams`: 87,641 rows, 30,046 FWA segments, so most FWA segments are split into several working rows.
  - `mad_m3s` is set to wet's annual pick, as the check script sets it. 1,411 rows carry 3 m3/s or more, and `conn_max` = 3,060.55 m.
  - I dropped the schema afterwards.
- **Synthetic probes.** These ran in `pg_temp` from an rsync'd copy of the repo, using the test helper `.nr_seg()` / `.nr_fixture()`. I did not edit the repo.
- **Suite.** In the copy, `test-frs_near_river.R` passes 40 and `test-near_river_rules.R` passes 63, with 0 failed and 0 errors.
- **Mutation.** With `AND NOT cut` deleted, exactly "a row the prefilter drops cuts the path behind it" fails (1 expectation). The new test guards the cut.

## (a) Round 4's fix

**Soundness: the cut never removes a row reachable within `cap`.**
- Let `r` be on the path but dropped by the prefilter. Then `dist(o.geom, r.geom) > cap`.
- `path_m(r)` is a chain of straight jumps and walked pieces, each at least its chord. It runs from the origin's downstream end to `r`'s entry point, so `path_m(r) >= dist(o.geom, r.geom) > cap`.
- Every row after `r` in path order has a `path_m` at least as large, so in the unfiltered walk `capped` removes it anyway.
- `r` precedes `t` whenever `r` is on `t`'s line above it, because `wscode` is constant per `blue_line_key`. On BULK, 0 lines carry more than one wscode, 0 lines mix main flow with side lines, and 0 `(blue_line_key, drm)` pairs repeat.
- The `bool_or` window cuts only from `t` onward, so the cut is sound.
- Measured on BULK: the walk with `AND NOT cut` removed and the shipped walk agree on every segment at q = 3, at d = 1,000 and at d = 20,000 (0 differ either way). The cut never fires to effect there.

**The cases the brief names.**
- **The first row entered on a new line.** The row above it is above the confluence, so `FWA_Downstream()` rejects it, and no false cut occurs. Probe C splits P's FWA segment above the confluence into two far rows; it gives origin 62 the same 300 m at d = 1,000 and at d = 9,000. The flip side is that the test then looks no further, which is gap 1 below.
- **Breaks within one FWA segment.** Rows that share a local code get one `FWA_Downstream()` answer, so the neighbour test agrees with the join. BULK, with about 2.9 rows per FWA segment, shows 0 differences.
- **Rows the table genuinely lacks.** The "next row above" skips the gap to the next row the table holds.
  - If that row is kept, the gap stays a counted jump (probe E: 1,700 m, no row at 1,000 m, the same answer at d = 9,000).
  - If it is on the path and dropped, the cut is sound by the argument above.
- **The origin's own line.** The guard `r.drm < o.drm` repeats the join's guard, so the origin itself, or anything above it, never counts as a dropped neighbour.

**Completeness: the cut can fail to fire where it must** (finding 1). The test looks at one row, the next row above `t` on `t`'s own line. The row before `t` in path order is not always that row:
1. **When the dropped run reaches the bottom of its line.** The next path row is then the first row of a lower line, whose own neighbour above is above that confluence and so is not on the path. Nothing checks the dropped run.
2. **When the row directly above is off the path by its local code** (an out-of-step row, the kind round 3's item 3 measured: Bulkley 17014753). The test stops at that row and never sees a dropped path row above it.

## Enumeration (12 places, current code)

The shared assumption, as round 3 named it: the rows `FWA_Downstream()` returns, cut to main flow and sorted `wscode DESC, drm DESC, id DESC`, form one contiguous chain from the origin, and each row's `waterbody_key` and `edge_type` say where the walk is. Item 12 is the version of that assumption that round 4 introduced: the rows left after the prefilter are the path's prefix.

1. **Path order across more than two lines: holds.**
   - Code: `ord` is unchanged.
   - Probe: on BULK, 0 main-flow wscodes are shared by two lines, and 0 lines carry two wscodes.
   - Round 3's two province-wide shared-code cases and the 999 codes stand as recorded.
2. **`LAG(prev_pt)` across a jump, and `below_m` from a far point: holds as documented ("either way").**
   - Code: unchanged.
   - The `LAG` is over the rows left after the prefilter, which is item 12's subject.
3. **Rows `FWA_Downstream()` drops from the true path: holds (a counted jump).**
   - Code: unchanged.
   - New consequence: such a row now also blinds the cut. See item 12 and probe G.
4. **The prefilter removing rows before the windows: does NOT hold in general.** This is the same defect as item 12, because the cut is the prefilter's repair. Finding 1 has the evidence.
5. **Connector rows inside their polygon: holds.**
   - Probe: on BULK, 92 main-flow 1400s, 1,065 main-flow 1450s and 88 side-line 1450s all have a polygon with their key, with 0 m outside it.
6. **A `waterbody_key` that recurs in separate runs: holds.**
   - Code: `PARTITION BY origin_id, waterbody_key` is unchanged.
   - Round 3 measured 0 answers moved, and only `least()` has touched this since, which can only lower the subtraction.
7. **Several jumps into one polygon, and the `cap` allowance: holds.** `least(conn_max, …)` enforces it by construction, and round 4's mutation test guards it.
8. **Correlated subquery binding: holds.**
   - `entry_sql` still binds `downstream.prev_pt` / `downstream.geom` to the outer row.
   - In the new EXISTS, the inner `r` (the derived table, and the `FROM %s r` inside it) shadows nothing outside. `t` and `o` resolve to the outer `downstream` FROM items.
   - The sprintf argument order (`… ord, table, cap, table, cap, entry_sql …`) matches the placeholders, since the suite's distances come out exact.
9. **The `capped` filter before the subtraction: holds** by item 7.
10. **`dist_m >= 0`: holds.**
    - `greatest(…, 0)` clamps it.
    - Probe: on BULK, a run of `c(3, 1, 8)` / `c(1000, 20000, 15000)` writes 129,918 rows, the smallest 0, and 0 negative.
11. **Invariants outside the walk: hold.**
    - `R/utils.R`, `R/frs_habitat_predicates.R` and `R/frs_params.R` are unchanged since c4e4a5e (`git diff c4e4a5e..HEAD --stat`). Round 4's 440-string byte-identity check therefore stands.
    - The EXISTS reads only `s.id_segment` / `s.watershed_group_code`.
    - Only rows with a local code and `mad_m3s` NULL or below the discharge get a row at it. Probe: on BULK, 0 rows at any of 1, 3 or 8 m3/s belong to a segment at or above that discharge, 0 to a segment with no local code, and 0 have a NULL `discharge_min`. Now that the NULL reach rows are gone, the INSERT's dropped `WHERE discharge_min IS NOT NULL` is correct.
12. **The prefilter cut: sound, NOT complete** (finding 1). Some answers above its source of truth:
    - The source of truth for an answer is the same walk with no prefilter, which is what a larger `max(distance_max)` approaches.
    - The cut's rule ("the row directly above `t` on its own line") is narrower than "the row before `t` in path order".
    - Probes A, F and G give a single spec one answer alone and another in a call with a larger reach.
    - BULK shows 0 cases: q = 3, d = 1,000 alone against `c(3, 1, 8)` / `c(1000, 20000, 15000)`, 0 differ either way; against q = 3, d = 20,000, 0 differ.

**So something still sits above its source of truth: item 12, which is item 4.** The other 10 hold, by code or by probe.

## Findings

### Finding 1

- **[severity: fragile]** R/frs_near_river.R:328-346 (`above_dropped`), with :373 and :378, and the doc at :262-266.
- **What happens.** The cut tests only the row directly above `t` on `t`'s own line, so it misses two shapes of dropped path row. A single (discharge_min, distance_max) answer then still depends on the other specs in the call, and through `frs_habitat_classify()`, which walks once per discharge at the largest `distance_max` any species asks for, one species' habitat depends on another species' rule. The doc's claim that "the prefilter is an optimisation that must not change an answer" is false for these shapes.
- **Repro A** (dropped run at the bottom of its line, the next row on another line):
  - Origin 62: blk 2, ws/lc `100.300.500`, (0,0)–(-100,0), 0.2 m3/s.
  - Line P, row 61: blk 3, ws = lc `100.300`, (0,1100)–(500,1100), 0.5 m3/s. This is P's only path row, and all of it is more than 1,000 m from 62.
  - Line Q, row 60: blk 1, ws = lc `100`, (0,200)–(0,1100), 5 m3/s.
  - `q = 3, d = 1000` alone writes 62 at **200 m**.
  - `q = c(3, 1), d = c(1000, 9000)` writes **no q = 3 row** for 62, and q = 3, d = 5,000 writes **1,100 m**, which is the walk's own distance through 61.
  - With two dropped rows on P (61 and 63), d = 1,000 still writes 200.
- **Repro F** (the same shape on the origin's own line, through a stretch off the table):
  - Origin 72: blk 2 at drm 1,500, (0,0)–(-100,0).
  - Rows 500–1,500 of blk 2 are missing from the table. Row 71, blk 2 at drm 0, (0,1100)–(500,1100), is dropped.
  - Row 60 on blk 1 is as in A.
  - d = 1,000 gives **200**; d = 9,000 gives **1,100**.
- **Repro G** (the row directly above is off the path by its local code):
  - On blk 1 (ws `100`), from the bottom up:
    - 60, lc `100.400`, (0,200)–(0,1100), 5 m3/s;
    - 63, lc `100.600`, (0,1100)–(10,1100), which `FWA_Downstream()` rejects for an origin at `100.500`;
    - 61, lc `100.400`, (10,1100)–(500,1100), on the path and dropped.
  - Origin 62 is as in the round 4 test.
  - d = 1,000 alone gives **200**; with `c(1000, 9000)` there is **no q = 3 row**; d = 9,000 gives **1,110.0**.
- **When it can happen.** As in round 4's finding, it needs a jump of about `cap` onto the dropped row (a code-placed confluence or a stretch off the table), and then a later row back within reach. G also needs an out-of-step row, which exists: Bulkley 17014753, and 2,013 nested-code main-flow rows province-wide.
- **Possible fix.** Test the row before `t` in path order, not the row above it on its line:
  - On `t`'s line, take the nearest row above that is **on the path**: move the `FWA_Downstream()` test and the origin-line guard inside the `ORDER BY … LIMIT 1` subquery. That closes G.
  - Where there is none (`t` is the first path row on its line), test the lowest path row of the next line up in path order. Its wscode is an ancestor of the origin's (or equal to it) and greater than `t.wscode`, at the smallest such depth. That closes A and F.
  - A dropped path row anywhere earlier is then caught. A run on one line ends either at a kept row on that line, which gets the first test, or at the bottom of its line, which gets the second; induction carries it up the lines.
  - Both are sound by the argument in (a).
  - Or state the remaining bound in the docs.

## (c) The verbose message change

There are no stale references that matter:
- `R/frs_near_river.R`: the docs (`@param verbose`, Limits), the `cat()`, the stats query and the walk-table doc no longer mention ended walks or a reach row. `man/frs_near_river.Rd` was regenerated (5a2a3ce) to match.
- `tests/testthat/test-frs_near_river.R`: the renamed test matches the new message ("4 segments within 1000 m; 0 with no local code did not walk"; "3 segments within 1000 m; 1 with no local code"). Nothing else greps `ended`, `within reach` or `discharge_min IS NULL`. Other test files have no hits.
- `NEWS.md`: it never named the count.
- The committed logs: no `ended` text.
- **Harmless leftover:** `data-raw/near_river_check.R:128` and `:135` still filter the walk table on `WHERE discharge_min IS NOT NULL`, which was meant to skip the reach rows. Those rows no longer exist, so the filter is always true and changes nothing.
