# Task: Decompose frs_habitat_classify into composable pieces

`frs_habitat_classify()` is 551 lines doing four distinct jobs. Pre-1.0, no external users, big consumer (link#55) about to land. Refactor now.

## Goal

Break `frs_habitat_classify` into four exported pieces:

| function | responsibility | purity |
|---|---|---|
| `frs_habitat_predicates(species, params)` | rules + thresholds → SQL boolean strings per habitat type | pure R, no DB |
| `frs_habitat_access(conn, table, breaks_tbl, params, label_block, barrier_overrides=NULL)` | build per-threshold-or-per-species access tables | DB |
| `frs_habitat_overlay(conn, table, known, ...)` | rename of existing `frs_habitat_known` | DB |
| `frs_habitat_classify(conn, table, to, ...)` | thin orchestrator: predicates → access → INSERT, optional overlay | DB |

`frs_habitat_classify` becomes a ~100-line wrapper. The other three are independently testable / composable.

## Phases

- [ ] Phase 1 — PWF baseline
- [ ] Phase 2 — Extract `frs_habitat_predicates()` — pure-R helper, returns named list of SQL boolean strings
- [ ] Phase 3 — Tests for predicates: rules-YAML path, CSV-ranges path, edge_type filter, lake/wetland W rule
- [ ] Phase 4 — Extract `frs_habitat_access()` — DB helper, owns the per-threshold pre-compute + `barrier_overrides` post-step
- [ ] Phase 5 — Tests for access: per-threshold reuse, barrier_overrides path, label_block filter
- [ ] Phase 6 — Rename `frs_habitat_known` → `frs_habitat_overlay`. No deprecation alias (no external users).
- [ ] Phase 7 — Update `frs_habitat_classify` to orchestrate the three. Add `known = NULL` parameter that calls `frs_habitat_overlay` when provided.
- [ ] Phase 8 — Update / refactor existing classify tests to test the orchestrator role only; predicate + access tests own their own paths
- [ ] Phase 9 — Run scoped tests per module
- [ ] Phase 10 — `/code-check` on the diff
- [ ] Phase 11 — Full suite via rtj harness
- [ ] Phase 12 — NEWS entry, version bump → 0.19.0 (breaking — function rename + classify signature changes)
- [ ] Phase 13 — PR

## Acceptance

- 4 functions of ~100-150 lines each instead of 1 of 551
- Predicates testable with no DB
- Existing classify behavior preserved (full suite still passes — but with NEWS noting the rename + new optional `known` param)
- `lnk_pipeline_classify` (next link PR) can take advantage of cleaner composition

## Risks

- **Test reorganization.** Existing 27+ tests on classify need to be reassigned to the new owners. Risk of dropping coverage in the move.
- **Breaking change**. `frs_habitat_known` → `frs_habitat_overlay` rename. No external users so safe, but downstream link branch (in flight on link#55) needs to use the new name from the start.
- **Per-threshold pre-compute** is a non-trivial efficiency optimization in current classify. Extracting it cleanly into `frs_habitat_access` without breaking the optimization needs care.

## Not in this PR

- link#55 caller — separate link PR after this lands.
- Any logic changes — refactor is structural only. Same outputs, same SQL, same test outcomes.
