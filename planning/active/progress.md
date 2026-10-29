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
- Code-check round 1 (01:30 UTC): the SQL-level `ids` timings above had their arrays pruned by the planner; the "DISTINCT 0-15% faster" and "1.1-13x" figures in the Phase 1 line are against that pruned walk. Re-timed as `ids_arrays` (batch 4, 01:49-01:58 UTC): same-batch SQL ratio 0.99-1.18x; EXISTS 1.1-15x slower than the join. SETN CH spill checked: 538,912 kB. Committed c287932.
- Code-check round 2 (02:00 UTC): no bugs; two prose items (research "rising with segments" holds per group, not per walk; findings Measurement section still carried round-1-superseded figures). Fixed; enumeration of superseded figures across NEWS, research, log README, findings, progress, R and data-raw: remaining hits are history (0.45.0 NEWS, round-1 disposition, this log).
- Code-check round 3 (02:06 UTC): exists predicate was a second copy that mocked tests could not pin; now one `walk_from` for both results, new identity test, five mutations red. Missing exists `@return` added. Two prose fixes. `frs_network_features` tests 02:19 UTC: FAIL 0, PASS 232.
