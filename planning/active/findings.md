# Findings

The dedup at line 191-196 uses (BLK, DRM) only. Two labels at the same position lose one. Fix: add label to the dedup key. frs_break_apply already handles geometry dedup separately (SELECT DISTINCT BLK, round(DRM) — no label involved).
