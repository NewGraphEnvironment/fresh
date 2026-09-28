# Progress — Live integration tests error when the database is unreachable instead of skipping (#229)

## Session 2026-09-27

- Plan-mode exploration — phases approved by user
- Created branch `229-live-integration-tests-error-when-the-da` off main
- Scaffolded PWF baseline from issue #229 with approved phases
- Next: start Phase 1
- Phases 1–2: `skip_if_no_conn()` + tests (92aeac0). Code-check 3 rounds: clean; accepted notes — any error skips (documented in helper comment), no connect_timeout (refused port fails fast), disconnect error could mask skip (same as `skip_if_no_schema()`)
- Phase 3: live file gated on `skip_if_no_conn(bcfp_conn)`. Repro with `PG_PASS_SHARE` set + tunnel down: main FAIL 3 → branch SKIP 1
- Phase 4: CLAUDE.md note updated; NEWS left to `/gh-pr-merge`
- Full suite: FAIL 0 | SKIP 3 | PASS 1148. Code-check on Phases 3–4: 3 rounds clean (round 3 swept tests/ for other un-gated connects — none)
