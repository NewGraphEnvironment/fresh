# Progress: Issue #129

### 2026-04-11
- Branch `129-barrier-overrides` created
- PWF initialized
- Replaced `observations` with `barrier_overrides` on both classify and habitat
- New `.frs_access_with_overrides()` — simple NOT EXISTS against overrides table, species-filtered. Early return when no overrides for species.
- Removed `.frs_access_with_observations()` and all observation counting SQL
- Removed observation_* columns from parameters_fresh.csv
- 658 tests pass
