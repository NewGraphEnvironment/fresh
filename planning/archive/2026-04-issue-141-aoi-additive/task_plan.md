# Task: aoi replaces wsg filter instead of being additive (#141)

## Goal
When both `wsg` and `aoi` are provided, `aoi` should be ANDed with the WSG filter, not replace it.

## Status: in progress

## Phases
- [x] Branch + PWF
- [x] Fix job_aoi construction — AND character aoi with WSG filter, pass sf/list through unchanged
- [x] 4 unit tests + 1 integration test. 682 total pass.
- [ ] Code-check
- [ ] PR + merge + archive
