# Phase 4 code-check — enumeration (terminal step)

Round 3 found `nf5_neither` (added in round 2's fix) to be a remainder,
which made the nf5 partition an identity. Per `/code-check` the loop ends on
an enumeration of the mechanism's candidate set, not on a quiet round.

## Mechanism — a summary column that is a proxy for its claim

Two forms: a column counting a narrower population than the sentence that
reports it, and a category computed as a remainder so its partition cannot
fail. Every summary column, with the population it counts:

| column | population | how counted |
|---|---|---|
| n_pscis | PSCIS points in the WSG / province | `count(*)` of the points table |
| nf1_same / tie / differ / link_999 / link_only / fresh_only / neither | every crossing, one status each | `nf1` is `FROM points LEFT JOIN` both outputs; each status from columns, none a remainder |
| nf1_fresh_wsg_na | crossings fresh snapped | `blk_fresh` not NA and `wsg_fresh` NA |
| nf5_crossings | crossings with a candidate on either side | rows of the nf5 aggregate |
| nf5_neither | crossings with no candidate on either side | points (via `nf1`) absent from nf5 — counted, not `n_pts - nrow` (fixed) |
| nf5_link_999 | crossings where link lists a `999.*` candidate | `bool_or(is_999)` |
| nf5_same_set / tie_set / differ_set | non-999 crossings with candidates | from `same_set` / `tie_set` (count-checked) |
| nf5_drm_mismatch | every crossing with candidates, 999 ones included (fixed) | `NOT bool_and(drm_same)` over shared segments |
| secs_* | wall time of each call | `Sys.time()` deltas |

`stopifnot()` now asserts `nrow(nf1) == n_pts` and that the nf1 and nf5
category sets each sum to `n_pts`. Each is a check that can fail, since
every term is counted independently. 15 of 15 columns accounted for.
