# Findings: Issue #127

## Key difference: boolean vs class-based island detection

**Fresh (current):** `lag(above) IS DISTINCT FROM above` — binary step detection. A section going 12%→18%→25% is one island.

**bcfishpass:** `lag(grade_class) <> grade_class` — class transitions produce new islands. 12%→18% is a transition from class 12 to class 15. Separate barriers.

## bcfishpass class breaks

```sql
CASE
  WHEN gradient >= .05 AND gradient < .07 THEN 5
  WHEN gradient >= .07 AND gradient < .10 THEN 7
  WHEN gradient >= .10 AND gradient < .12 THEN 10
  WHEN gradient >= .12 AND gradient < .15 THEN 12
  WHEN gradient >= .15 AND gradient < .20 THEN 15
  WHEN gradient >= .20 AND gradient < .25 THEN 20
  WHEN gradient >= .25 AND gradient < .30 THEN 25
  WHEN gradient >= .30 THEN 30
  ELSE 0
END
```

## Additional filters

- `blue_line_key = watershed_key` — only main flow lines, excludes side channels (382 of 11,520 ADMS segments)
- Max gradient_class at duplicate positions via GROUP BY + max()
- wscode_ltree/localcode_ltree joined from FWA base table at insert time

## Design: parameterize the class breaks

The class break values should NOT be hardcoded. Pass as a named numeric vector where names are the class labels and values are the lower bounds:

```r
classes = c("5" = 0.05, "7" = 0.07, "10" = 0.10, "12" = 0.12,
            "15" = 0.15, "20" = 0.20, "25" = 0.25, "30" = 0.30)
```

Build the CASE statement dynamically. This lets consumers customize class breaks without code changes.

## Impact on frs_habitat()

Currently frs_habitat() loops over access thresholds calling frs_break_find() once per threshold. With multi-class, it calls frs_break_find() ONCE, gets all classes, then filters by species access threshold when building break_sources.
