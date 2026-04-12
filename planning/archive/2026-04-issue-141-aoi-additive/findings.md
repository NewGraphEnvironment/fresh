# Findings

Line 246: `job_aoi <- if (!is.null(aoi)) aoi else w`. When aoi is a WHERE clause string, it completely replaces the WSG code. The WSG filter is lost.

Fix: when both wsg and aoi are provided AND aoi is a character string (WHERE clause), combine them. When aoi is an sf polygon or list, keep it as-is (spatial filter handles scoping).

Need to check both the wsg_specs loop (line ~246) and the mirai branch.
