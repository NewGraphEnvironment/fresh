# Review round 1: planning/backlog.md (#315)

## Checklist read

- **Parser, on a copy** (scratchpad `cp/planning/backlog.md`) with `backlog_moves.sh` at
  the published parser: `list`, `next`, `free` gave no stderr and exit 0. `next` gives
  `/planning-init #318`. `free` gives #318 (A), #321 (B) and #324 (D). `tick #<u>
  https://example.invalid/pr` ran on a fresh copy for each of #318-#325: each printed `TICKED`
  with the right batches and ticked the right `### n.` checkbox. After ticking all eight on one
  copy, `next` printed `NONE: every move is ticked` (rc 4) and named no unplaced batch.
- On the copy, `lanes` printed UNKNOWN for every move. The parser resolves paths against
  `ls -A <file>/../..`, and the scratch copy has no repo beside it (symlinks did not help). So
  I ran `lanes` on the real file, which is read-only. The md5 was the same before and after
  (8bcaa1fd...). Every path resolved. The 13 CLASH pairs are 1-2, 1-3, 1-5, 1-6, 1-8, 2-3,
  2-5, 3-5, 3-7, 3-8, 4-5, 5-6 and 5-8.
- **Ordering:** the transitive closure of `waits on` is 2:{1}, 3:{1,2,7}, 5:{1,2,3,4,6,7},
  6:{1} and 8:{1,2,3,4,5,6,7}. Moves 1, 4 and 7 wait on nothing. Every CLASH pair is ordered
  (2-5 through 3), and there is no cycle.
- **Issue states:** I fetched `gh api .../issues/N` for every `#N` in the file. Every issue in
  a batch, the singles or the tracks is open. Every issue under "Closed and transferred"
  (64, 73, 243, 256, 295, 231, 232, 233, 235, 236) is closed. PR #252 and PR #254 are open. PR
  #296 and PR #297 are merged.
- **Coverage:** there are 53 open issues. Less #315 and the umbrellas #318-#325, that leaves
  44. 44 are placed (34 in batches, 5 in tracks, 5 singles). Each is placed once, and no open
  issue goes unnamed.
- **Umbrellas:** I read the bodies of #318-#325. Each one's member table matches its Order row
  and its batch section. The `track:speed` and `track:package-boundaries` labels are on the
  issues line 25 names.
- **Claims checked, all true:**
  - PR #254 is open and its closing references are #68 and #253.
  - PR #296 is titled "#277 parts 1 and 2" and PR #297 "#277 part 3", both merged.
  - 50f3fa4 adds `tibble,` to Suggests.
  - PR #94 has "mirai parallel: each WSG is one task", and `R/frs_habitat.R:576` calls
    `mirai::daemons`.
  - 81 of 275 is in `research/id_segment_identity.md:90` and in CLAUDE.md.
  - #222's delete and insert are one transaction (`R/frs_habitat_classify.R:373-528`).
  - link#349 is closed.
  - #246 option 1 is documented in `R/frs_channel_width.R:8` and `:35`.
  - #265 waits on fwapg#36.
  - link's open #133 waits on fresh#44, and link's open #132 waits on fresh#189.
  - Both `data-raw/audit_*.R` files exist.
  - 1dcc7a3 is v0.55.1.
- **Lane coverage:** I listed the source paths each batch member names in its body and
  comments, and compared them with its batch's Touches line.
- **Public text:** grep for the private repo names, host names, port and tunnel
  found nothing. The only repos linked are fwapg and link, both PUBLIC.

## Findings

1. **planning/backlog.md:61 (batch 3 Touches), with rows 15 and 19.** Batch 3's Touches
   leaves out `R/frs_habitat_classify.R`. #222's body places its first gap there: "`to_habitat`
   persist (`R/frs_habitat_classify.R`)". That gap is the subject of the batch's gate, "alter
   or refuse a target missing a flag column". Batch 6 (move 6) touches
   `R/frs_habitat_classify.R`. Move 2 and move 6 each wait only on move 1, so once move 1 is
   ticked they are both `free` at once. Evidence: `lanes` prints `FREE 2 6`.
   - Caveat: the target-prep helper is in `R/utils.R:64-90`, which batch 3 lists, so the fix
     could land there. But the INSERT and its column list are in `frs_habitat_classify.R`.
   - Fix: add the path, then order 2 and 6 (6 waits on 2, or the reverse).
   - Rule: none
2. **planning/backlog.md:85 (batch 6 Touches), with rows 15, 16 and 19.** Batch 6's Touches
   leaves out `R/frs_habitat.R`. #189's implementation table names it: "`known_habitat_when`
   option threaded through `frs_habitat` orchestrator ... `R/frs_habitat.R` (around line 1153
   `.frs_run_connectivity`)". Move 2 (batch 3) and move 3 (batch 4) both touch
   `R/frs_habitat.R`, and neither is ordered against move 6. Evidence: `lanes` prints
   `FREE 2 6` and `FREE 3 6`.
   - #189's gate includes "whether this belongs in fresh or link", so it may not land. But the
     Touches line is what makes the moves free.
   - Rule: none
3. **planning/backlog.md:109 (batch 9 Touches), with rows 14 and 17.** Batch 9 renames both
   audit scripts (#299; umbrella #321's gate is "rename both audit scripts").
   `research/id_segment_identity.md:9` cites `data-raw/audit_habitat_293.R` by path, so the
   rename edits that file. Batch 9's Touches does not list it. Move 1 (batch 1) touches
   `research/id_segment_identity.md`, and move 1 and move 4 are both free now with no ordering.
   Evidence: `free` lists #318 and #321, and `lanes` prints `FREE 1 4`.
   - This is a one-line reference edit, so the risk is a small conflict, not lost work. Move 5
     also touches the file but waits on 4, so that pair is fine.
   - Rule: none

Not a finding: umbrella #321's Touches says `research/`, where batch 9 names two files. The
umbrella is broader, not narrower, and the parser reads only the backlog. Likewise #325's
umbrella names a new `R/frs_gradient_*.R` that the backlog gives in prose; a new file cannot
clash.
