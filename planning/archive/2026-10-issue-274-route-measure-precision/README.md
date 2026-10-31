## Outcome

Route measures that fresh writes into SQL as positions now go through `.frs_sql_exact()` (`%.17g`) instead of `%s` (15 significant digits). That covers `frs_point_locate()`'s `fwa_locatealong()` call and every `downstream_route_measure <= <m>` segment pick in `frs_network()` (direct, waterbody, and the `upstream_blk` check), `frs_network_upstream()`, `frs_network_downstream()`, `frs_network_prune()` and `frs_waterbody_network()`. 0.49.0 had already fixed the `fwa_watershedatmeasure()` sites. The plan claimed `frs_point_locate()` was the last site; the Plan review disproved it. A grep that needed `sprintf` and `measure` on one line misses the multi-line `paste0()` builders, which put the 14 picks' arguments on other lines. Round 3 of code-check closed the class by parsing every `sprintf()` placeholder in `R/` (1,123 pairs). Two parts of the issue body were wrong: `frs_point_locate()`'s key already went through `as.integer()`, so the `3.56e+08` defect was not present there. And its "four sites" were an incomplete count. `frs_wsg_drainage()` keeps `dbQuoteLiteral()` (15 digits), for the measured reason below. The gate test (`test-frs_fwapg_gate.R`) now sends a stream's exact top, as `frs_point_locate()` does. `research/fwa_point_snap.md` is revised: it stops attributing a precision to the 400-stream head-case sample, and records that `data-raw/point_snap_tie_sweep.R` writes measures at `format()`'s 7 digits. Re-running that sweep is #289.

## Measurement

- Local Docker fwapg, blue line 354087614: its guarded top sent with `%s` (`2273.67420120248`) parses above the stored `max(upstream_route_measure)`; with `%.17g` (`2273.6742012024752`) it parses exact.
- Blue line 360447231 (the gate pin) at its exact top `1528.8506958829107`: parses exact, `old_rule` 0, closed 1, so it is still a head case. With `FRESH_FWAPG_TRIAL` (both migrations) the head-case test ran and passed; without the trial all gated tests skip.
- `DBI::dbQuoteLiteral()` on RPostgres writes `1234567.89123457::float8` (15 digits). `fwa_downstream()` on one blue line answered FALSE in both directions for measures 2 ULPs apart, at 17 digits and at 15. So the drainage literal's rounding is not observable there, and bundled `wsg_outlet.csv` has at most 10 significant digits.
- `format(c(1528.8506958829107, 4494.61997946051), scientific = FALSE)` is `"1528.851" "4494.620"`. So the #266 sweep's CSV counts are of rounded measures (#289). Whole numbers come through exactly.
- Full suite at c51bb4f: 0 failed, 2409 passed, 6 skipped. Every new precision test is red on origin/main's R files (mutation-checked by reviewers in temp copies).

## Owed

- Edit the #274 issue body: remove the incorrect key claim from the Status block; list the segment-pick sites this branch fixed and `frs_wsg_drainage()` left as is

Closed by: PR (see branch `274-route-measures-reach-sql-through-s-15-si`)
