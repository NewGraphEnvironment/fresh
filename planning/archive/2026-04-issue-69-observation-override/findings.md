# Findings: Issue #69

## bcfishobs.observations table
- 372k observations, 280k since 1990, 592 in ADMS
- Has: species_code, blue_line_key, downstream_route_measure, observation_date
- No wscode_ltree/localcode_ltree — uses blk+drm only

## Implementation approach
The observation override modifies ACCESSIBILITY, not classification. After the initial access gating produces per-species accessibility tables, we:

1. For each species with observation_threshold > 0:
   a. Find all blocking barriers from the breaks table (using the same label filter)
   b. For each barrier, count qualifying observations upstream (beyond buffer, since date_min, matching species list)
   c. Barriers meeting the threshold are "overridden" — removed from the block list
2. Recompute accessibility WITHOUT the overridden barriers
3. Reclassify habitat using the updated accessibility

This happens INSIDE `frs_habitat_classify()` after the initial access computation and before classification. The flow becomes:

```
1. Compute access per threshold (existing)
2. Observation override: remove qualifying barriers → recompute access (NEW)
3. Classify per species (existing)
```

## SQL pattern for counting upstream observations

```sql
SELECT b.blue_line_key, b.downstream_route_measure, b.label,
  count(o.*) AS n_obs
FROM {breaks_tbl} b
JOIN {observations_tbl} o
  ON o.blue_line_key = b.blue_line_key
  AND o.downstream_route_measure > b.downstream_route_measure + {buffer_m}
  AND o.observation_date >= '{date_min}'
  AND o.species_code IN ({species_list})
WHERE {label_filter}  -- only blocking barriers for this species
GROUP BY b.blue_line_key, b.downstream_route_measure, b.label
HAVING count(o.*) >= {threshold}
```

Barriers matching this query get EXCLUDED from the access computation for this species.

Note: this only handles same-BLK observations (barrier and observation on same blue_line_key). Cross-BLK observations (fish observed on a tributary upstream of the barrier) would need fwa_upstream() — but bcfishpass v0.5.0 also uses a simplified same-BLK approach for the observation count.
