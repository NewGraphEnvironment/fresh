# Task Plan: Issue #153 — frs_cluster bridge_gradient/distance along path

## Phase 1: Investigate root cause
- [ ] Confirm: is the issue upstream check ignoring gradient/distance, or downstream trace bug?
- [ ] Run comparison query on BULK CH to verify the 97/180 excess
- [ ] Document findings

## Phase 2: Apply bridge constraints to upstream check
- [ ] Add bridge_gradient and bridge_distance to `.frs_cluster_upstream()` signature
- [ ] Trace upstream path segment-by-segment (or reuse `.frs_trace_downstream` in reverse?)
- [ ] Tests
- [ ] Commit + code-check

## Phase 3: Verify convergence
- [ ] BULK CH rearing count matches bcfishpass within tolerance
- [ ] Other species with cluster_rearing=TRUE (CO, SK, ST, WCT) unaffected or improved
- [ ] Commit + code-check

## Phase 4: PR
- [ ] Push, create PR with SRED tag
