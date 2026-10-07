# Progress — Lake and wetland rearing buckets: size by polygon area, require connected spawning (#240)

## Session 2026-10-06

- Plan-mode exploration (driven from a link session) — phases and five decisions approved by user
- Created branch `240-lake-and-wetland-rearing-buckets-size-by` off main (`30e8733`)
- Scaffolded PWF baseline from issue #240 with approved phases
- Next: start Phase 1
- Phase 1 (area-only bucket predicates): tests red → `build_wb_pred()` drops the size clause and the cw no-width branch → 91/91 predicate tests. `/code-check` 3 rounds (`review-p1-round{1,2,3}.md`): r1 fixed a wrong test comment; r2 flagged the legacy `frs_habitat_species()` width-gated lake path (accepted, Decision 5, goes to NEWS); r3 clean.
- Phase 2 (rule validation): rear `requires_connected` must be on the first L/W rear rule, value `spawning`, with a finite `connected_distance_max` > 0; red→green, guard mutation-tested. `/code-check` 3 rounds (`review-p2-round{1,2,3}.md`): r1 flagged that link's `lnk_rules_build()` `add_rc()` stamps `rear_requires_connected` on every rear rule (inert today, all NA; link#310 must change it); r2, r3 clean.
- Plan review (Plan agent) landed: folded in WSG-scoped habitat joins, per-(waterbody_key, blue_line_key) outlets, more tests, first-rule guard; remaining items go to docs / NEWS / issue edits.
- Phase 3 (bucket connectivity): `.frs_trace_downstream()` generalised (SK default SQL pinned byte for byte by `tests/testthat/fixtures/trace_downstream_sk.sql`); new `.frs_bucket_connected()`; second loop in `.frs_run_connectivity()`; `frs_habitat()` docs. Full suite FAIL 0 / PASS 1201 / WARN 3 (all three pre-existing, `test-frs_network_features-live.R`).
  - `/code-check` (`review-p3-round{1,2}.md`): r1 found the distance tests could not catch a broken cap (straight line = network distance, prefilter applied the same cutoff) → folded-geometry fixture (`scale = 0.01`). r2 found the same class one axis over: no test pinned either trace's origin choice → tests with D between true distance and true + one segment, a two-segment cluster, a cluster across a confluence, a two-outflow wetland.
  - Ended by enumeration, not a quiet round. The candidate set is every choice that sets a distance or a result: outlet order, per-(waterbody_key, blue_line_key) grouping, cluster-origin order (measure, wscode), cap, UPDATE, each connection path, wiring, WSG match. Each of the 11 mutations turns a test red.
  - Performance: a GiST on geom plus ANALYZE took NATR BT from ~48 s to ~2.5 s per species with identical output; the pass now creates the index if missing.
- Phase 4 live check at `b38c40a` (`data-raw/logs/bucket_connected_240/`): area-only NATR BT lake 309.9 → 521.4 km, wetland 683.9 → 1,287.3 km (= link#307's cw figures); connected at 3 km keeps 514.5 / 1,190.9 km; 2–5 s per species per WSG. PARS lake 54.9 → 101.5 km, all kept at 10 km.
