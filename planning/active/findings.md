# Findings

grad_tbl is created at line 400 (sequential) / 557 (mirai), enriched with label column, then added to barrier_tables. At cleanup (line 476/615), all barrier_tables are dropped.

Fix: before the cleanup loop, if to_barriers is provided, INSERT INTO to_barriers SELECT * FROM grad_tbl. The grad_tbl already has wscode_ltree and localcode_ltree from .frs_enrich_breaks() which runs on the breaks table (but NOT on grad_tbl directly — it runs on breaks_tbl which is the merged breaks table from frs_network_segment).

Wait — the grad_tbl is the RAW output from frs_break_find(). It has: blue_line_key, downstream_route_measure, gradient_class, label, source. It does NOT have wscode_ltree/localcode_ltree — those are added by .frs_enrich_breaks() which operates on the breaks_tbl (the merged table inside frs_network_segment).

Need to enrich grad_tbl with ltree columns before persisting. Can use the same .frs_enrich_breaks() helper.
