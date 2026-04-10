# Findings: Issue #124

`frs_col_generate()` replaces gradient with a GENERATED ALWAYS column from DEM Z vertices. After splitting a 4.9% parent at a break, children get recomputed gradients (3% + 7%). This is more accurate per sub-segment but diverges from bcfishpass which keeps the parent gradient.

Fix: `frs_col_generate()` has a list of 4 generated columns (gradient, drm, urm, length). When `gradient_recompute = FALSE`, skip the gradient column but still regenerate the other 3 (measures and length MUST update after a split).

Implementation: modify `frs_col_generate()` to accept an `exclude` parameter listing columns to skip. `frs_network_segment()` passes `exclude = "gradient"` when `gradient_recompute = FALSE`.
