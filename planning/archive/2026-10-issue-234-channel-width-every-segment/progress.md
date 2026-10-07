# Progress — Channel width for every segment (#234)

## Session 2026-10-07

- Plan-mode exploration — phases approved by user
- Decisions: standalone function (no pipeline wiring); optional constant fallback + investigate input gap
- Created branch `234-channel-width-for-every-segment` off main
- Scaffolded PWF baseline from issue #234 with approved phases
- Next: Plan-agent review, then Phase 1
- Plan-agent review: 1 blocker (fill-NULL guard moved into Phase 1) + gaps folded in
- Phase 1 (#29): `frs_channel_width()` with poisson2021 / hall2007 / custom presets, fill-NULL default, single-statement overwrite, `to_regclass` column lookup. 77 tests pass (unit + live Byman-Ailport)
- /code-check: 3 rounds. R1 3 fixed (lookup, two-statement overwrite, hall<poisson claim); R2 1 inside R1's fix (crossover depends on precipitation); R3 enumerated 29 claims, 5 scoping fixes
- Phase 2 (#28): `value` fallback (ASSIGNED) + verbose counts. 101 tests pass
- /code-check Phase 2: 3 rounds. R1 clean; R2 1 (unanchored live message regex) + doc scope; R3 1 (integer64 `value`/coefs render raw bits via sprintf). Fixed. My coefficient fix initially missed `k_sql` (caught by the new test). Enumerated all 9 `.frs_sql_num()` call sites: all take coerced doubles or preset literals
- Phase 3: filed #246 (upstream area for placeholder/unmapped segments: half reachable). CLAUDE.md architecture line. Full suite 1,355 pass / 0 fail. R CMD check: only new issue was the undeclared `bit64` test dependency → Suggests. Pre-existing check items left for separate work
- Surfaced, not fixed: `frs_col_join()`'s own roxygen example passes a subquery with an alias (`) sub`), which breaks because the function appends `_src`
- Follow-up (user: "fix those two things"): R CMD check now Status OK (was 1 error / 5 warnings / 3 notes), full suite 1,361 pass
  - frs_break() errored on every call: it passed point-mode args that #95 moved to frs_feature_find(). Dropped from signature + call; retitled to attribute mode
  - frs_habitat_access() break_sources path used frs_break_find(points_table=...) → frs_feature_find(overwrite = FALSE, append = TRUE)
  - The same stale call sat in vignettes/habitat-pipeline.Rmd, data-raw/vignette_habitat_pipeline.R and data-raw/pipeline_wsg.R. These also lacked the ltree enrichment frs_classify(breaks=) needs (broken since #75); now routed through frs_habitat_access()
  - Docs: measure_precision (frs_break_apply), gate / label_block / measure_precision on frs_habitat via @inheritParams, gate direction fixed (upstream of a blocking break), frs_habitat_predicates docs + runnable example now match its real input shape, internal Rd link → plain code
  - ASCII stop() message; Suggests tibble; .Rbuildignore .lintr / docker; aliased subquery removed from frs_col_join example + test
  - New tests assert wrapper-forwarded arg names are in callee formals() (fail on old code)
  - /code-check: 3 rounds. R1 out-of-diff siblings (F1-F3); R2 inside the F2 fix (missing ltree enrichment); R3 swept 1,789 calls / 176 files against formals() with a positive control → one more doc instance (frs_habitat_predicates)
  - Not re-knitted: the habitat-pipeline vignette cache predates this. Code-check noted its cached access counts are falls-only (gradient table was dropped by append + overwrite when built), so a re-run will lower them
