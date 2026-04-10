## Outcome

Added YAML-based habitat eligibility rules format for multi-rule species. 11 species in bundled default. SK lake-only rearing, CO/BT wetland-flow carve-out, all anadromous river-polygon spawning now expressible without code changes.

## Key Learnings

- R `$` partial matching is a silent footgun: `rule$edge_types` matched `rule$edge_types_explicit` because `edge_types` is a prefix. Use `rule[["..."]]` for all rule field access.
- Type-check YAML values at parse time, not at SQL build time: `edge_types_explicit: [foo]` coerced to `NA` via `as.integer()` and errored at query time with a confusing "column na" message. Better to error early with a clear message.
- `thresholds: false` per rule is the cleanest abstraction for carve-outs (segments that match without threshold checks). Avoids proliferating special-case code paths.
- Empty rule list `rear: []` has clean semantics: `.frs_rules_to_sql(list())` returns `"FALSE"`. Distinct from absent `$rules$rear` (NULL) which falls through to CSV ranges.
- CSV stays the source of numeric thresholds. YAML rules express WHICH segments qualify. Clean separation of concerns.

## Closed By

PR #115

## SRED

Relates to NewGraphEnvironment/sred-2025-2026#16
