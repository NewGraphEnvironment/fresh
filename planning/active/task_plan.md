# Task Plan: Issue #153 — frs_cluster bridge_gradient/distance along path

## Phase 1: Investigate root cause
- [x] Confirmed: upstream check ignores gradient/distance — uses FWA_Upstream as boolean only
- [x] Document findings

## Phase 2: Apply bridge constraints to upstream check
- [x] Add bridge_gradient and bridge_distance to `.frs_cluster_upstream()` signature
- [x] Query upstream segments via FWA_Upstream join, order ASC, apply row_number + gradient/distance
- [x] Mirror pattern in `.frs_cluster_both()` upstream query
- [x] Use cluster_maximums (most-upstream point) as trace start
- [x] Update test assertions (cluster_maximums, nearest_connect, nearest_barrier)
- [x] 698 tests pass, code-check clean
- [x] Commit + code-check

## Phase 3: Verify convergence
- [ ] BULK CH rearing count matches bcfishpass within tolerance
- [ ] Other species with cluster_rearing=TRUE (CO, SK, ST, WCT) unaffected or improved
- [ ] Commit + code-check

## Phase 4: PR
- [ ] Push, create PR with SRED tag
