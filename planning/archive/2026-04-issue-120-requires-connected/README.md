## Outcome

SK/KO spawning now requires spatial connectivity to a qualifying rearing lake. When no rearing exists (no lakes >= 200 ha), all spawning set to FALSE. New `.frs_run_connectivity()` helper orchestrates both rearing and spawning cluster checks after classification.

## Key Learnings

- `requires_connected` is consumed by the orchestrator (`frs_habitat()`), not by `frs_habitat_classify()`. Classification and connectivity are separate concerns.
- The same `frs_cluster()` machinery works for both directions: rearing-needs-spawning AND spawning-needs-rearing. Just swap `label_cluster` and `label_connect`.
- KO was missing from `parameters_fresh.csv` — caught during implementation.

## Closed By

PR #121

## SRED

Relates to NewGraphEnvironment/sred-2025-2026#16
