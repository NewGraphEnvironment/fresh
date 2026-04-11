# Task: Observation-based access override (issue #69)

## Goal
If enough fish observations exist upstream of a gradient/falls barrier, upgrade access for that species. Reuses existing accessibility infrastructure — just removes qualifying barriers from the species' block list and reclassifies.

## Status: in progress

## Phases

- [x] Branch + PWF
- [x] Add observation columns to `parameters_fresh.csv`
- [x] Add `observations` param to `frs_habitat_classify()` with `.frs_access_with_observations()` helper
- [x] Pass `observations` through `frs_habitat()` (sequential + mirai)
- [x] 657 tests pass
- [ ] Code-check
- [ ] Integration test verification
- [ ] PR + merge + NEWS + archive
