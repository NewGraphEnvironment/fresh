## Outcome

Added `frs_order_child()` — post-classification UPDATE that flags direct-children of large-order parent streams (`stream_order = stream_order_max` AND `stream_order_parent >= parent_order_min`). Wired into the rules YAML via `channel_width_min_bypass` block so per-species rearing classifiers can opt in. Closes the BT/CO/CH/ST/WCT rearing-stream gap on bcfishpass-bundled WSGs (HORS, COLR, KHOR, CLRH, etc.).

## Closed By

PR #193 (initial impl), with follow-ups #195 and #196 (SQL fixes for the missing/restored `stream_order_max` column via CTE).
