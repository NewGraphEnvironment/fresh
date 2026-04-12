# Findings: Issue #133 (reopened)

## The problem

`connected_distance_max` was passed as `bridge_distance` to `frs_cluster()`. But `bridge_distance` controls how far to SEARCH for a connection, not how far from the connection the classified segments can extend. A contiguous cluster of 112km spawning qualifies if rearing is reachable from ANY part — but segments 11.7km from rearing should be excluded by the 3km cap.

## The fix

After `frs_cluster()` removes disconnected clusters, add a distance filter:

1. For each segment where `label_cluster` is TRUE, find the nearest segment where `label_connect` is TRUE
2. Compute network distance (cumulative `length_metre` along the stream path)
3. Set `label_cluster = FALSE` if distance > `connected_distance_max`

## SQL approach

Use the segmented streams table's `downstream_route_measure` for distance. For segments on the same BLK as a rearing segment, distance = `abs(s.downstream_route_measure - r.downstream_route_measure)`. Cross-BLK distance is harder — would need `fwa_downstreamtrace` or cumulative length.

Simpler approach: measure-based distance on same BLK. For cross-BLK (tributary spawning near a mainstem lake), use the difference in measures via the FWA route system. Actually, the simplest: for each spawning segment, find the min distance to ANY rearing segment using `abs(drm difference)` on same BLK, or cumulative path length for cross-BLK.

For SK/KO the primary case is spawning downstream of a lake on the same BLK. Simple DRM difference should cover most of the gap.

Actually even simpler: UPDATE directly in SQL:

```sql
UPDATE habitat h SET spawning = FALSE
FROM streams s
WHERE h.id_segment = s.id_segment
  AND h.species_code = 'SK'
  AND h.spawning IS TRUE
  AND NOT EXISTS (
    SELECT 1 FROM streams r
    JOIN habitat hr ON r.id_segment = hr.id_segment
    WHERE hr.species_code = 'SK'
      AND hr.rearing IS TRUE
      AND r.blue_line_key = s.blue_line_key
      AND abs(r.downstream_route_measure - s.downstream_route_measure) <= 3000
  )
```

This handles same-BLK distance. Cross-BLK would need ltree + measure computation but is a minor case for SK/KO.
