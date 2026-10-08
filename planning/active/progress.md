# Progress — Bulk point snap: one call snaps a dataset and returns watershed_group_code (#247)

## Session 2026-10-07

- Plan-mode exploration — design decisions from user: replace `frs_point_snap()` in place, 100 m default tolerance, output = input id + snap columns
- Plan-agent review: 2 blockers + 6 gaps folded into the plan
- Phases approved by user
- Created branch `247-bulk-point-snap-one-call-snaps-a-dataset` off main
- Scaffolded PWF baseline from issue #247 with approved phases
- Next: start Phase 1
- Phase 1: `.frs_point_snap_sql()` + `.frs_db_write_temp()` with SQL-shape tests. Code-check 4 rounds (round 3: whole-string assertions could pass vacuously → scoped to lateral / final SELECT slices; round 4 mutation-proved 14 cases). Reviews in `review-round{1..4}.md`
- Phase 2: new `frs_point_snap(conn, points, ...)` (df / sf / table, `to =`, `col_id`, `col_blk` hint, 100 m default); `fwa_indexpoint` + `frs_point_snap_knn()` removed; `frs_watershed_split()` snaps in one call; x/y test callers migrated. Code-check: round 1 (to==points drops source; out-of-range lon/lat fails batch; integer64 tolerance) → round 2 found both guards one axis over (geographic CRS other than 4326; `to` = network table) → ended by enumeration (`review-p2-enumeration.md`), which also added the hint range check + finite `num_features`. Full suite: FAIL 0 / WARN 3 / SKIP 2 / PASS 1463 (warns pre-existing `frs_network_features` live tests; skips need bcfishpass schema)
- Phase 3: `frs_feature_find(points = <sf>)` snaps through `frs_point_snap()`; label / label_col / label_map / append / BLK scoping as the table path; create/append tail shared in `.frs_feature_find_write()`. Code-check: round 1 (double id → "2e+05"; feature_id type differs between paths) → round 2 found the label type one axis over (+ DROP before checks, 16-digit ids, blk as.integer) → ended by enumeration (`review-p3-enumeration.md`). `.frs_label_expr()` now casts `label_col::text` in label_map CASEs (fixes the table path too)
- Phase 4: `data-raw/point_snap_parity_check.R` + logs. PSCIS 150 m, province: 18,180 identical, 22 ties (same blk, <= 1 m), 11 link-999, 1,692 neither, 0 other differences; nf5 0 differences beyond 86 cut-off ties + 19 link-999; 0 measure mismatches. Code-check: round 1 (top-level on.exit; nf5 tie count check; drm only on identical sets) → round 2 (nf1 not partitioning: no "neither" rows) → round 3 (nf5_neither a remainder; drm mask) → ended by enumeration (`review-p4-enumeration.md`); script now asserts both partitions
- Phase 5: roxygen + `frs_candidates_pick()` xref, NEWS 0.40.0, CLAUDE.md snap note. `R CMD check` (no tests) 0/0/0; full suite FAIL 0 / WARN 3 / SKIP 2 / PASS 1494 (warns/skips pre-existing). Follow-up issues drafted (link wrapper, link 999 guard, downstream migrations) — not filed
- Next: user review of follow-up drafts; `/planning-archive`, `/gh-pr-push`
