# Issue #211 — frs_wsg_drainage

## Outcome

Added `frs_wsg_drainage(conn, watershed_group_code, table = "public.wsg_outlet")` as a new exported primitive in the `@family wsg` family. Given a focal set of FWA watershed groups, returns the drainage closure (focal + every WSG they drain through) ordered downstream-first by `nlevel(outlet) ASC`. Pure FWA topology — no bundle / species / overrides knowledge. SQL ported verbatim from the validated query in `NewGraphEnvironment/link@v0.40.5 data-raw/study_area_wsgs.R:44-50`.

Beyond the literal SQL port, the function adds: scalar `table` arg check (`.frs_validate_identifier` is vectorized internally so a vector value would silently slip through and produce malformed SQL — caught by code-check Round 1); internal upper-casing of focal codes; `warning()` on unmatched focals so `c("BULK","TYPO")` no longer returns silently partial closure (also Round 1); test assertion tightened to match the validator's actual error message rather than a generic `class = "error"` (Round 2). 11 test_that blocks / 14 expectations (6 arg-validation + 5 live-DB gated on `PG_DB_SHARE`). Released as **v0.32.0**.

First consumer: `link::lnk_wsg_resolve` ([NewGraphEnvironment/link#207](https://github.com/NewGraphEnvironment/link/issues/207)) — the link wrapper composes this primitive with the bundle's species-presence filter to drive `data-raw/study_area_wsgs.R` (replacing the inline query there).

Closed by: commits `808458e` (Phase 1 verification), `157d03e` (function), `e9fa8b9` (tests), `b686598` (Release v0.32.0). PR forthcoming via `/gh-pr-push`.
