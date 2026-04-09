## Outcome

Fixed precision-loss bug introduced in v0.11.0 (#101) where distinct gradient thresholds collapsed to the same `gradient_N` label. New canonical format `gradient_NNNN` (4-digit zero-padded basis points) preserves precision to 0.0001 (1 basis point). Backward-compat parser still accepts legacy `gradient_N` from user-supplied labels.

## Key Learnings

- **Auto-derived parameters need validation too**: when implementing #101, only the user-supplied `breaks_gradient` was validated. The auto-derived path from `params[species]$spawn_gradient_max` could pass invalid values from custom CSVs. Code-check round 1 caught this. Lesson: validate at the union point, not just at function entry.
- **Label format must round-trip cleanly**: `as.integer(thr * 100)` truncates fractional percentages. The fix uses `as.integer(round(thr * 10000))` for precision and `sprintf("%04d", ...)` for fixed-width output.
- **Parser backward compat**: when changing canonical formats, accept both during transition. Write side commits to new format; read side handles both.
- **Mirai branch duplication is fragile**: the threshold derivation logic exists in two places (sequential `.run_job()` and parallel mirai inline). Both needed identical updates. Future refactor opportunity: extract shared helper.
- **Validation centralization**: `.frs_gradient_label()` and `.frs_validate_gradient_thresholds()` in `utils.R` give one place to update format / rules. Used by both branches.

## Workflow note

This was the first issue worked using proper PWF at `planning/active/` after a workflow hygiene reset (archived stale PR #56 files). Going forward: PWF files in `planning/active/`, archive on merge, code-check on each commit, checkbox tracking in task_plan.md.

## Closed By

PR #111 (commits ad94bc7, 6acfa94)

## SRED

Relates to NewGraphEnvironment/sred-2025-2026#16
