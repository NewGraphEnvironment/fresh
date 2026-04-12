# Progress: Issue #133 (fourth pass)

### 2026-04-12
- PR #137: cross-BLK bypass → 11.7km survived 3km cap
- PR #138: removed cross-BLK → overcorrected to 14.9 km (bcfishpass: 85.7)
- Root cause: spawning (stream BLK) and rearing (lake BLK) are always different BLKs for SK
- Fix: Euclidean ST_Distance fallback for cross-BLK, capped at connected_distance_max
