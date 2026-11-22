# Progress — Backlog move 1: watershed-group keying fixes (#318)

## Session 2026-11-22

- Plan-mode exploration — phases approved by user
- Created branch `318-backlog-move-1-watershed-group-keying-fi` off origin/main
- Scaffolded PWF baseline from issue #318 with approved phases
- Next: start Phase 1
- Phase 1 (#294): measured the whole-line read (`data-raw/barrier_span_294.R`, 5 of 12 lines changed by the second job), corrected #294's body, `.frs_persist_barriers()` on both job paths; both scope mutations fail 9 assertions. Commits c554f11, 2cf8eef, be717ce
- Plan review landed mid-Phase 1 (`review-plan.md`); 19 findings, none blocking, folded into the plan
- Phase 2 (#308): `.frs_group_required()` refuses any NULL group (EXISTS), called from classify, near_river, frs_cluster, frs_order_child and bridged overlay; call-graph enumeration test
- Phase 2 mutations: guard removed from frs_cluster -> 2 failures; lfid early return restored -> 4 failures. Commit fce5625
- Phase 3 (#277): direct-mode refusal from to_cols/from_cols; 4 new mocked tests red before, green after
