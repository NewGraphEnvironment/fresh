## Outcome

Fish observations upstream of gradient/falls barriers now override per-species access gating. BT accessible doubled on ADMS (+103%, threshold=1, all salmonids count). CH/CO gained ~10% (threshold=5, species-specific).

## Key Learnings

- **Materialize before joining**: the correlated subquery approach (NOT EXISTS from inline SELECT) hung for 57+ minutes on ADMS scale. Materializing the overridden barriers into a temp table with a (blk, drm) index brought it to ~9s per species.
- **label_filter scope bug**: the access threshold loop's `label_filter` variable retained the LAST iteration's value. When species had different access gradients (15% vs 25%), the wrong barriers were being checked for observation overrides. Fix: recompute `label_filter` per species inside the observation override path.
- **Guard NA fields**: `observation_species` from the CSV could be NA for species without observation override. `strsplit(NA, ";")` produces `list(NA)` → `.frs_quote_string(NA)` silently becomes `'NA'` matching nothing. Guard with `!is.na() && nzchar()`.

## Closed By

PR #126

## SRED

Relates to NewGraphEnvironment/sred-2025-2026#16
