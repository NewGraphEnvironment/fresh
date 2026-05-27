# Progress — frs_wsg_drainage (#211)

## Session 2026-05-27

- Plan-mode exploration — phases approved by user
- Created branch `211-frs-wsg-drainage-fwa-wsg-drainage-closur` off main (off `90af475`)
- Scaffolded PWF baseline from issue #211 with approved phases (commit `1dc1145`)
- **Phase 1 complete:** `public.wsg_outlet` column confirmed as `wsg varchar(4)` (with `outlet ltree`, `lvl integer`); regression baseline run — PARS+BULK → 15 WSGs, exact match: `KISP, KLUM, LKEL, LSKE, MSKE, USKE, BULK, FINA, LBTN, LPCE, MORR, PARA, PCEA, UPCE, PARS` (DS-first, depths 1×6, 2×8, 3×1). Commit `808458e`.
- **Phase 2 complete:** Wrote `R/frs_wsg_drainage.R` (signature `frs_wsg_drainage(conn, watershed_group_code, table = "public.wsg_outlet")`); `devtools::document()` regenerated NAMESPACE + Rd; live-validated end-to-end (happy path: 15-WSG exact match; lowercase input normalized; TYPO triggers warning + drops from result; vector `table` rejected). `/code-check` Round 1 caught 2 fragility issues (scalar `table` check, silent unmatched focals), both fixed; Round 2 Clean. Commit `157d03e`.
- **Phase 3 complete:** Wrote `tests/testthat/test-frs_wsg_drainage.R` — 11 test_that blocks / 14 expectations (6 arg-validation + 5 live-DB). Live tests skip on missing `PG_DB_SHARE`; locally validated by inline-overriding env + `--no-environ` to bypass the dead `:63333` tunnel (per `m1-link-db-env` memory). All pass. `/code-check` Round 1 caught 1 too-broad `class = "error"` assertion (would pass on any error, not just identifier validation) — fixed to match `.frs_validate_identifier`'s actual message `"table contains invalid characters"`; Round 2 Clean.
- Next: Phase 4 — NEWS.md + DESCRIPTION bump + release commit + PR
