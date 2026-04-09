# Findings: Issue #110 — Gradient barrier precision loss

## The bug

Two related precision-loss bugs introduced in v0.11.0 (PR #109, issue #101) when I added auto-derived gradient breaks from species params.

### Root cause

In `R/frs_habitat.R` (lines 287-288 of v0.11.0):

```r
all_thresholds <- all_thresholds[
  !duplicated(as.integer(all_thresholds * 100))]
```

And in label generation:

```r
sprintf("gradient_%d", as.integer(thr * 100))
```

Both use `as.integer(thr * 100)` which truncates fractional percentages:
- `0.05 * 100 = 5.0 → as.integer = 5`
- `0.0549 * 100 = 5.49 → as.integer = 5` (truncated, not rounded)

So distinct biological thresholds get the same integer key. The dedup drops one. The label is identical for both.

### Why I added it in #101

When I implemented `breaks_gradient`, the auto-derived values from `parameters_habitat_thresholds.csv` include fractional percentages like `0.0549, 0.0849, 0.1049`. The label format and barrier table name suffix both used integer percent. To prevent name collisions, I added the dedup.

But the dedup is silently destroying biological precision rather than fixing the underlying problem. The right fix is a precision-preserving label format.

## Why it matters

`parameters_habitat_thresholds.csv` has these spawn_gradient_max values:
- BT, CO, RB, WCT: `0.0549`
- CH, ST: `0.0449`
- GR, KO, SK: `0.0249`
- PK, CM: `0.0649`

And rear_gradient_max:
- BT: `0.1049`
- CH: `0.0549`
- CO: `0.0549`
- GR: `0.0349`
- RB, ST, WCT: `0.0849`

If a user passes `breaks_gradient = c(0.05, 0.10)` (clean integer values from a project's local channel-type scheme), those would collide with the auto-derived 0.0549 and 0.1049 from species params. The dedup keeps the first after sort, so:
- `c(0.05, 0.0549)` → keeps 0.05 (loses 0.0549, BT spawn_max!)
- `c(0.10, 0.1049)` → keeps 0.10 (loses 0.1049, BT rear_max!)

This is silently wrong. The species would be classified against breaks at the WRONG gradient value.

## Why backward compat matters

User code can pass `frs_break_find(label = "gradient_15")` for custom break sources. Or `label_block = c("gradient_15", "blocked")`. These literal strings are stored in the breaks table and parsed by `.frs_access_label_filter()`.

If we change the parser to ONLY accept the new 4-digit format, those user-supplied labels would be silently treated as non-blocking. Adding backward compat means the parser accepts both `gradient_15` (legacy, divide by 100) and `gradient_1500` (new, divide by 10000).

The write side of `frs_habitat()` always emits the new format. Documentation points users to the new format. But the read side is permissive.

## Resolution choice: 4-digit basis-points

Rejected formats:
- `gradient_5p49`: variable-length string, breaks `^gradient_(\d+)$` parsing
- Mixed (`gradient_15` for integers, `gradient_5p49` for fractions): cognitive load, two patterns
- `gradient_549` (no leading zero): visually confusing (50 vs 500)

Chosen: `gradient_NNNN` with leading zeros — `gradient_0500` for 0.05, `gradient_0549` for 0.0549.

Pros:
- Single uniform format
- Sorts naturally as strings (`gradient_0249` < `gradient_0500` < `gradient_1500`)
- Parses cleanly: `as.numeric(N) / 10000`
- Resolution to 0.0001 (1 basis point) — sufficient for any meaningful gradient threshold
- Self-documenting once you know the convention (4 digits = basis points)

Cons:
- Less human-readable at first glance than `gradient_15`
- All existing labels change (acceptable for pre-1.0 package)

## Test cases to add

1. **Regression test**: `frs_habitat(... breaks_gradient = c(0.05, 0.0549))` produces TWO distinct rows in the breaks table with labels `gradient_0500` and `gradient_0549`. Currently produces ONE row.
2. **Backward compat test**: `.frs_access_label_filter()` parses `gradient_15` (legacy) as 0.15 and blocks species with `access_gradient <= 0.15`.
3. **New format test**: `.frs_access_label_filter()` parses `gradient_1500` (new) as 0.15 and blocks species with `access_gradient <= 0.15`.
