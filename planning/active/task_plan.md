# Task: frs_wsg_drainage — FWA WSG drainage-closure primitive (#211)

## Problem

`link` currently computes WSG drainage closure (every WSG a focal set drains through, downstream-first) inline in `data-raw/study_area_wsgs.R` — see `NewGraphEnvironment/link@v0.40.5`. The query reads `public.wsg_outlet`, joins focal → closure via `f.outlet <@ w.outlet`, sorts by `nlevel(outlet) ASC`.

This is FWA-topology — it belongs in `fresh`, not `link`. No bundle/species/overrides knowledge involved; pure network shape. Replacing the inline query unblocks `NewGraphEnvironment/link#207` (`lnk_wsg_resolve`), which composes this primitive with the bundle's species-presence filter.

## Approach

New exported function `frs_wsg_drainage(conn, watershed_group_code, table = "public.wsg_outlet")` returning a character vector of WSG codes (focal + every WSG they drain through), ordered downstream-first by `nlevel(outlet) ASC`.

Param name `watershed_group_code` (not `wsgs`) for fresh-internal vocabulary consistency with `frs_wsg_species` + `frs_stream_fetch`. SQL ported verbatim from the validated query in `NewGraphEnvironment/link@v0.40.5 data-raw/study_area_wsgs.R:44-50`. SQL composition via `sprintf()` + `DBI::dbQuoteLiteral`. Identifier validation via `.frs_validate_identifier()` (`R/utils.R:54`). `@family wsg` (new family; retag of `frs_wsg_species` deferred). Live DB test gated on `Sys.getenv("PG_DB_SHARE")`.

## Phase 1 — Live-DB column verification

- [x] Confirm actual column name in `public.wsg_outlet` (`wsg` vs `watershed_group_code`) via `\d public.wsg_outlet` on the live DB so the SQL matches reality — **`wsg` varchar(4)** confirmed; also has `outlet ltree` (GIST) + `lvl integer`
- [x] Run the unmodified link query against current fwapg to confirm PARS+BULK → 15 WSGs (the regression baseline before any code lands) — **15/15 match**: `KISP, KLUM, LKEL, LSKE, MSKE, USKE, BULK, FINA, LBTN, LPCE, MORR, PARA, PCEA, UPCE, PARS` (DS-first, depths 1/1/1/1/1/1/2/2/2/2/2/2/2/2/3)

## Phase 2 — Function + roxygen

- [x] Write `R/frs_wsg_drainage.R` with signature, arg validation (`stopifnot` + `.frs_validate_identifier`), SQL via `sprintf` + `DBI::dbQuoteLiteral`, `\dontrun{}` example showing PARS+BULK, `@family wsg`, `@export`. Also: upper-case focal codes internally; warn on unmatched focals (caught by code-check Round 1); scalar `table` check (caught by code-check Round 1); use `DBI::dbGetQuery` (non-spatial, avoids sf warning).
- [x] `devtools::document()` → regenerate `NAMESPACE` + `man/frs_wsg_drainage.Rd`
- [x] `/code-check` clean (Round 1: 2 findings fixed; Round 2: Clean) → atomic commit (function + checkbox flip)

## Phase 3 — Tests

- [x] `tests/testthat/test-frs_wsg_drainage.R`: 6 arg-validation (non-character / empty / `NA` / empty-string / vector table / invalid identifier — last asserts validator's specific `"table contains invalid characters"` message after code-check Round 1) + 5 live-DB tests (skip on missing `PG_DB_SHARE`): PARS+BULK 15-WSG exact match, focal-order invariance, case-folding, unmatched-focal warning, no-match error
- [x] `devtools::test()` green — all 14 expectations pass against live fwapg (env-overridden to bypass dead `:63333` tunnel)
- [x] `/code-check` clean (Round 1: 1 finding fixed, 3 accepted as stopifnot-idiom tradeoffs; Round 2: Clean) → atomic commit

## Phase 4 — Release

- [ ] `NEWS.md`: new `# fresh 0.32.0` section, lead with bold one-liner + bullets (composition with `lnk_wsg_resolve`, pure-topology framing, test count) — matches existing style (`NEWS.md:1-10`)
- [ ] `DESCRIPTION`: `Version: 0.32.0`, `Date: <commit date>`
- [ ] `lintr::lint_package()` clean
- [ ] `/code-check` clean → atomic commit `"Release v0.32.0"` as final commit of branch
- [ ] `/planning-archive` → `/gh-pr-push` (PR body: `Closes #211` + `Relates to NewGraphEnvironment/sred-2025-2026#24`)

## Validation

- [ ] `devtools::test()` green
- [ ] Live `frs_wsg_drainage(conn, c("PARS","BULK"))` returns exactly: `KISP, KLUM, LKEL, LSKE, MSKE, USKE, BULK, FINA, LBTN, LPCE, MORR, PARA, PCEA, UPCE, PARS` (15 WSGs)
- [ ] Closure invariant to focal ordering
- [ ] `lintr::lint_package()` clean
- [ ] pkgdown reference page renders the new function with runnable `\dontrun{}` example
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

## Out of scope

- Retagging `frs_wsg_species` from `@family parameters` → `@family wsg` (separate concern, follow-up)
- Consuming the new function in link (`lnk_wsg_resolve` — covered by `NewGraphEnvironment/link#207`)
- Adding a `network = "fwa"` param for future non-FWA networks (YAGNI per the issue body)
