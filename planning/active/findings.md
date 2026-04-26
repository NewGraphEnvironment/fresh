# Findings

## Current frs_habitat_classify map (551 lines)

| range | section | extract to |
|---|---|---|
| 118-160 | Setup: load params, index inputs, get WSGs, create output, delete stale | stays in classify |
| 160-238 | Pre-compute access tables per unique gradient threshold | `frs_habitat_access()` |
| 240-260 | Per-species: edge_type filter helper | `frs_habitat_predicates()` (used inside) |
| 260-318 | Per-species: spawn + rear conditions (rules path or CSV path) | `frs_habitat_predicates()` |
| 318-332 | Per-species: barrier_overrides (recompute per-species access) | `frs_habitat_access()` |
| 332-372 | Per-species: lake_rear + wetland_rear conditions | `frs_habitat_predicates()` |
| 374-394 | Per-species: INSERT joining accessibility + classification | stays in classify |
| 414-end | Cleanup access temp tables | stays in classify |

## Predicate output shape

```r
frs_habitat_predicates("CO", params)
#> list(
#>   spawn        = "h.gradient < 0.0549 AND h.channel_width >= 2 AND ...",
#>   rear         = "h.gradient <= 0.0549 AND ...",
#>   lake_rear    = "h.waterbody_key IN (SELECT ... WHERE area_ha >= 200)",
#>   wetland_rear = "..."
#> )
```

Pure R. Caller embeds these in `CASE WHEN <pred> THEN TRUE ELSE FALSE END`.

## Access output shape

`frs_habitat_access()` returns a named list:

```r
list(
  by_threshold = c("0.05" = "tmp.access_05", "0.1" = "tmp.access_10"),
  by_species   = c(CO = "tmp.access_05_ovr_CO")  # only when barrier_overrides applied
)
```

Caller resolves: for species X, use `by_species[[X]]` if present, else
`by_threshold[[as.character(thr)]]`. Cleanup is the caller's job.

## Helpers already in fresh that this work reuses

- `.frs_rule_to_sql(rule, csv_thresholds)` — single-rule → SQL
- `.frs_rules_to_sql(rules, csv_thresholds)` — rule-list → SQL (OR'd)
- `.frs_find_waterbody_rule(rules, "L"|"W")` — lookup helper
- `.frs_access_label_filter()` + `.frs_access_with_overrides()` — already extracted

The new `frs_habitat_predicates()` mostly orchestrates `.frs_rules_to_sql()` + the new lake/wetland gating logic from fresh#165 + `.frs_find_waterbody_rule()`. Not new logic; new public boundary.

## Naming decision

Settled in conversation 2026-04-25: `frs_habitat_predicates` (plural). Predicates is the SQL term for boolean expressions used in WHERE clauses. Aligns with the existing `.frs_rule_to_sql` private helper one level up.
