# Task Plan: Issue #153 — frs_cluster bridge along downstream path

## Phase 1: Investigate root cause
- [x] Confirmed: upstream check ignores gradient/distance — uses FWA_Upstream as boolean only
- [x] Document findings

## Phase 2: Apply bridge constraints to upstream check (REVERTED)
- [x] Implemented path-based upstream gradient check (81e48c3)
- [x] **Reverted**: FWA_Upstream returns all upstream segments including tributaries. row_number interleaves tributary segments with mainstem, making path gradient unreliable.

## Phase 3: Keep downstream path gradient only
- [x] Revert `.frs_cluster_upstream` to boolean (0.13.5 version)
- [x] Revert `.frs_cluster_both` upstream query to boolean
- [x] Keep `.frs_cluster_downstream` path gradient (trace is linear, row_number works)
- [x] direction="both": upstream boolean + downstream path gradient
- [x] Update roxygen to document why upstream is boolean
- [x] Revert test assertions to cluster_minimums
- [ ] Commit + code-check

## Phase 4: Test with link
- [ ] ADMS: must not regress from 0.13.6 baseline
- [ ] BULK: CH rearing should improve from +6%
- [ ] Commit + code-check

## Phase 5: PR
- [ ] Push, create PR with SRED tag
