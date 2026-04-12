## Outcome

Multiple labels per break position preserved. Dedup uses `IS NOT DISTINCT FROM` for NULL-safe label comparison. Enables per-barrier overrides and reporting.

## Key Learnings

- Code-check caught NULL label bypass: `a.label = b.label` evaluates to NULL (not TRUE) when both are NULL. Use `IS NOT DISTINCT FROM` for NULL-safe equality.

## Closed By

PR #146

## SRED

Relates to NewGraphEnvironment/sred-2025-2026#16
