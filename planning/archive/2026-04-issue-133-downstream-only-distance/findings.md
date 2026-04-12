# Findings

bcfishpass SK spawning:
- Downstream from lake: 3km cap, 5% gradient bridge, mainstem only
- Upstream of lake: NO distance cap, limited by spawn eligibility contiguity

The distance filter must only remove segments where:
1. The segment IS downstream of rearing (rearing is upstream of the segment)
2. AND the distance exceeds connected_distance_max

"Downstream of rearing" means rearing is above the segment:
- Same-BLK: s.drm < r.drm (segment measure below rearing measure)  
- Cross-BLK: fwa_upstream(s, r) — rearing is upstream of segment

Segments where the segment IS upstream of rearing (s.drm >= r.drm, or segment is upstream via ltree) are KEPT with no distance cap.

SQL logic for NOT EXISTS (keep if):
```sql
-- Keep if: upstream of rearing (any distance)
(r.blue_line_key = s.blue_line_key
 AND s.downstream_route_measure >= r.downstream_route_measure)
OR
-- Keep if: downstream of rearing but within cap
(r.blue_line_key = s.blue_line_key
 AND s.downstream_route_measure < r.downstream_route_measure
 AND r.downstream_route_measure - s.downstream_route_measure <= max_dist)
OR
-- Keep if: cross-BLK upstream of rearing (any distance)
(r.blue_line_key != s.blue_line_key
 AND fwa_upstream(s.wscode_ltree, s.localcode_ltree,
                  r.wscode_ltree, r.localcode_ltree))
OR
-- Keep if: cross-BLK downstream within Euclidean cap
(r.blue_line_key != s.blue_line_key
 AND NOT fwa_upstream(s.wscode_ltree, s.localcode_ltree,
                      r.wscode_ltree, r.localcode_ltree)
 AND ST_Distance(s.geom, r.geom) <= max_dist)
```
