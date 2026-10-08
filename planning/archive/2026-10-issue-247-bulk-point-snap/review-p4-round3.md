# Review: Phase 4 parity script, round 3

Scope: `data-raw/point_snap_parity_check.R`, `data-raw/logs/point_snap_parity_247/*`,
`planning/active/findings.md` ("Parity with link::lnk_points_snap()").
Method: I re-ran a renamed copy (`working.parity_247r3_*` tables, logs written to the
scratchpad) for ALL at 150 m against local fwapg. It reproduced `ALL_summary.csv`
exactly. I then queried the kept tables directly and dropped them afterwards (0
`parity_247%` tables remain).

## Mechanism

Rounds 1 to 4 found the same thing each time: a summary column that **stands in for**
the claim instead of measuring it, or categories that **don't partition** the
population the claim is about. Round 2 (no count check in tie_set) and round 3
(measures checked only on identical sets) were proxies. Round 4 (no nf1 row for
crossings neither function snapped) was a non-partition. Two variants of this can
remain after the fixes:
(a) a column whose population is narrower than the sentence that reports it;
(b) a partition that holds **by construction** (one category is the remainder), so
the sum cannot fail and it shows nothing.

## Populations, column by column (ALL / BULK)

nf1 has one row per PSCIS point: it is built `FROM points LEFT JOIN` both outputs.
`stream_crossing_id` is unique (19,905 rows, 19,905 distinct). Each output has at
most 1 row per id, and no output row has a NULL `linear_feature_id`. The status
`ifelse` chain is exhaustive and never NA on this data, so the nf1 columns are a
true, observed partition.

| column | population |
|---|---|
| nf1_neither | points with no row in either nf1 output |
| nf1_link_999 | link's pick is `<@ '999'` (whatever fresh did) |
| nf1_link_only | link picked a non-999 segment, fresh picked nothing |
| nf1_fresh_only | fresh picked something, link picked nothing |
| nf1_same | both picked, link's pick is non-999, blk and measure equal |
| nf1_tie | both picked, not the same, distances within 1e-6 |
| nf1_differ | both picked, not the same, distances differ |
| nf1_fresh_wsg_na | diagnostic, not part of the partition: fresh-picked rows with NULL wsg |

- ALL: 18180 + 22 + 0 + 11 + 0 + 0 + 1692 = **19905** = n_pscis
- BULK: 1710 + 1 + 0 + 0 + 0 + 0 + 69 = **1780** = n_pscis

nf5 has one row per id that either side listed (`pairs JOIN side`; every id in
`pairs` is also in `side`). same_set and link_999 cannot be NULL. tie_set cannot be
NULL either: when a side has 0 candidates, `n = 5` is FALSE, which short-circuits.

| column | population |
|---|---|
| nf5_crossings | ids with at least one candidate on either side (not a category) |
| nf5_neither | `n_pts - nrow(nf5)`, derived by subtraction |
| nf5_link_999 | link listed any `<@ '999'` segment |
| nf5_same_set | non-999, both sides list the same segments |
| nf5_tie_set | non-999, sets differ, both sides list 5, every one-sided segment at the shared cut-off |
| nf5_differ_set | the non-999 remainder |
| nf5_drm_mismatch | diagnostic: **non-999** crossings with a measure mismatch on a shared segment |

- ALL: 1692 + 19 + 18108 + 86 + 0 = **19905** = n_pscis
- BULK: 69 + 0 + 1708 + 3 + 0 = **1780** = n_pscis

Both partitions sum to n_pscis in both runs. The findings.md arithmetic line is
correct as well. Other findings.md claims I checked against the data:
- All 22 ties have the same blk and measures 1 apart. Every tie has two *different*
  `linear_feature_id`s (0 same-lfid ties), so the "equidistant at a vertex"
  explanation holds and the distance proxy did not hide a measure bug.
- The 3 + 8 split of the 11 link 999 picks is correct.
- nf1_same has 0 rows that match on a different lfid.
- nf5_crossings 18213 = 19905 - nf1_neither.

## Findings

- **[fragile]** `data-raw/point_snap_parity_check.R:164`. `nf5_neither = n_pts -
  nrow(nf5)` is a remainder, so the nf5 partition is an identity. It holds whatever
  the nf5 query returns, so "likewise nf5" in findings.md is decoration, not a check.
  This is variant (b). The true value is right: I counted it directly as points with
  no row in either nf5 output, got 1692, and that id set equals the nf1-neither id
  set (0 rows in either `EXCEPT`). The fix is to count it the same way nf1 does
  (`FROM points LEFT JOIN` both nf5 outputs `WHERE` both are null), or to
  `stopifnot(summary$nf5_neither == summary$nf1_neither)`. That cross-check is the
  only one here that could fail.
- **[fragile]** `data-raw/point_snap_parity_check.R:169` and the findings.md row "nf5
  measure mismatches on any shared candidate". `nf5_drm_mismatch` still masks
  `!nf5$link_999`, so the 19 link-999 crossings are left out, which is variant (a).
  This is the rest of round 3's issue. The script comment (lines 108-109) and the
  findings row both claim every shared candidate. The column is not part of the
  partition, so the 999 mask is not needed. The number does not change: those 19
  crossings share 21 segments, and all 21 measures match. In every one of the 19,
  fresh's set equals link's non-999 candidates (0 missing). So the excluded
  population hides nothing today. Drop the mask so the column measures what the row
  says.

No other column has a population that differs from its label. Neither run fails to
partition.
