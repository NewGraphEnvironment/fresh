# Progress

## Session 2026-04-14
- Created branch `153-cluster-bridge-path` from main (5a4247d)
- Read issue #153 and full frs_cluster.R implementation
- Root cause: upstream check in `.frs_cluster_upstream` ignores bridge_gradient/distance
- Next: investigate whether upstream needs gradient constraints or whether direction should change
