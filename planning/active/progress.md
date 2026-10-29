# Progress — frs_network_features(): an existence mode (#281)

## Session 2026-10-28

- Plan-mode exploration — phases approved by user; output shape decided at the gate (matching rows only, `has_features`)
- Created branch `281-frs-network-features-an-existence-mode-t` off main
- Scaffolded PWF baseline from issue #281 with approved phases
- Next: start Phase 1
- Phase 1: `data-raw/network_features_exists.R` written; SALR, CHWK, LFRA measured 00:35-00:46 UTC (3 views x 6 runs each, every walk's digests agree). EXISTS 1.1-13x slower than the array walk; DISTINCT 0-15% faster. SETN pending.
- Plan review landed (planning/active/review-plan.md); dispositions in findings.md. Script gained `fn_ids`/`fn_exists` end-to-end forms (review A1).
- Phase 2/3: tests (mocked + live SKGT with repeated-id segments and all-NULL-id features) and `result = "exists"` (DISTINCT join form) committed 93d54aa, 341a34b. Mutations: zero-row `has_features <- TRUE`, dropped DISTINCT, exists path without prefilter: each goes red. Full suite 00:49-00:51 UTC: FAIL 0, SKIP 6, PASS 2164. ids SQL identical to v0.46.0 on four paths.
- Phase 1 finished / Phase 4: SETN and end-to-end (`fn_*`) runs 00:51-01:11 UTC, base-table EXISTS 01:16-01:26 UTC (capped at 5 min, both runs). Exists mode 1.00x-1.24x faster end to end; join form ships. Spill check in SETN skipped: another client began walking the DB ~01:26 UTC.
- lint: no lints in changed files except two object_usage false positives in the data-raw script (installed fresh is 0.44.0, lacks `.frs_walk_prefilter` and `result`).
- Research: `research/fwa_downstream_walk.md` "Existence walks" + README row.
