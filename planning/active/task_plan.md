# Task Plan: Issue #150 — Index classify inputs

## Phase 1: Make `.frs_index_working` idempotent
- [ ] Add `IF NOT EXISTS` with explicit named indexes to all CREATE INDEX statements
- [ ] Add test: call `.frs_index_working` twice on same table, no error
- [ ] Commit + code-check

## Phase 2: Index input tables in `frs_habitat_classify`
- [ ] Call `.frs_index_working(conn, table)` and `.frs_index_working(conn, breaks_tbl)` before access gating loop
- [ ] Add test: `frs_habitat_classify` on unindexed table succeeds (existing tests cover this implicitly)
- [ ] Commit + code-check

## Phase 3: PR
- [ ] Push branch, create PR with SRED tag
