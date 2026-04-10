# Findings: Issue #118

`distance` param does double duty: gradient sampling window AND minimum island length. Fix: separate into `distance` (window, unchanged) + `min_length` (island filter, default 0).
