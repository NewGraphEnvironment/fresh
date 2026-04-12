## Outcome

Replaced per-threshold boolean gradient detection with bcfishpass v0.5.0 multi-class approach. One pass, class transitions produce separate barriers. Primary cause of the -23% CH spawning gap.

## Key Learnings

- **PARTITION BY is critical in window functions**: code-check caught missing `PARTITION BY blue_line_key` in `lag()` and `count()` — barriers bled across stream boundaries without it.
- **Dynamic CASE from named vector**: parameterized class breaks avoid hardcoding. Consumers can pass custom classes.
- **Single call replaces loop**: `frs_habitat()` went from N calls (one per threshold) to 1 call with all classes. Simpler orchestrator code.

## Closed By

PR #128

## SRED

Relates to NewGraphEnvironment/sred-2025-2026#16
