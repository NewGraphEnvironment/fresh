# Task: Replace observations with barrier_overrides (issue #129)

## Goal
Replace complex observation counting logic with a simple `barrier_overrides` table from link. Fresh just skips matched barriers — no counting, no thresholds.

## Status: in progress

## Phases
- [x] Branch + PWF
- [x] Replace `observations` with `barrier_overrides` on `frs_habitat_classify()` and `frs_habitat()`
- [x] Replace `.frs_access_with_observations()` with `.frs_access_with_overrides()` — no counting, no thresholds, just skip matched barriers
- [x] Remove observation_* columns from `parameters_fresh.csv`
- [x] 658 tests pass
- [ ] Code-check
- [ ] PR + merge + NEWS + archive
