# Progress — frs_network_features(): an existence mode (#281)

## Session 2026-10-28

- Plan-mode exploration — phases approved by user; output shape decided at the gate (matching rows only, `has_features`)
- Created branch `281-frs-network-features-an-existence-mode-t` off main
- Scaffolded PWF baseline from issue #281 with approved phases
- Next: start Phase 1
- Phase 1: `data-raw/network_features_exists.R` written; SALR, CHWK, LFRA measured 00:35-00:46 UTC (3 views x 6 runs each, every walk's digests agree). EXISTS 2-13x slower than the array walk; DISTINCT 5-17% faster. SETN pending.
- Plan review landed (planning/active/review-plan.md); dispositions in findings.md. Script gained `fn_ids`/`fn_exists` end-to-end forms (review A1).
