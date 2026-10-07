# Progress — Lake and wetland rearing buckets: size by polygon area, require connected spawning (#240)

## Session 2026-10-06

- Plan-mode exploration (driven from a link session) — phases and five decisions approved by user
- Created branch `240-lake-and-wetland-rearing-buckets-size-by` off main (`30e8733`)
- Scaffolded PWF baseline from issue #240 with approved phases
- Next: start Phase 1
- Phase 1 (area-only bucket predicates): tests red → `build_wb_pred()` drops the size clause and the cw no-width branch → 91/91 predicate tests. `/code-check` 3 rounds (`review-p1-round{1,2,3}.md`): r1 fixed a wrong test comment; r2 flagged the legacy `frs_habitat_species()` width-gated lake path (accepted, Decision 5, goes to NEWS); r3 clean.
