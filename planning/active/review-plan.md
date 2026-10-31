# Plan review: #274 (Plan agent, 2026-10-31)

Written from the agent's reply (Plan agents cannot write files). The reviewer read the plan and the in-flight edits. It ran read-only SELECTs on local fwapg and edited nothing.

## Blocker
- **B1.** The "last site" claim is false: 14 more `downstream_route_measure <= %s` segment picks in `R/frs_network.R` (363, 386, 394, 489, 519, 527, 619, 627), `frs_network_upstream.R:82`, `frs_network_downstream.R:71`, `frs_network_prune.R:128` and `frs_waterbody_network.R:73`. Also `frs_wsg_drainage.R:102` (`dbQuoteLiteral`, 15 digits). Measured: in a 2% sample, 0 of 62,297 stored `downstream_route_measure` values (> 0) need more than 15 digits. -> **Fixed** in Phase 5. `frs_wsg_drainage()` was left out with a measured reason (findings.md).

## Gap
- **G1.** "185 of 400" conflicts with the issue's 86 of 400 (different populations and methods). -> Count dropped from the gate comment and the research note.
- **G2.** "2 before / 218 after" describes rounded tops. The reviewer's exact-top re-measure on 345 guarded streams: old rule 2, new rule 331, new rule at 15 digits 182. -> Kept attributed to #266, with how that sample wrote its tops marked as unrecorded. The reviewer's numbers were not re-derived here, so they are not published.
- **G3.** The #266 sweep writes measures with `format(scientific = FALSE)`, about 7 digits (`4494.61997946051` -> `4494.620`), verified. -> Stated in the research note. Re-running the sweep is #289.

## Assumption (checked)
- **A1.** The gate test stays meaningful at the exact top: old rule 0 rows, new rule 1. `skip_unless_head_case()` checks the column predicate only, not `ST_LocateAlong` on M; 14 of 345 pass the column rule but do not resolve. -> The comment no longer overstates this.
- **A2.** The key was already an integer in `frs_point_locate()`; `%d` is cosmetic. The issue's Status block is wrong.
- **A3.** No caller relies on NA or vector measures. The one outside caller wraps the call in `try()` and passes a scalar.

## Acceptance
- **Ac1.** The research note lacked a `**Verified:**` provenance line. -> Added.
- **Ac2.** The point_locate test used `as.numeric()` on a 15-digit string. -> Now a string comparison against `.frs_sql_exact()`.
