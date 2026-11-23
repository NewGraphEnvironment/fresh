# Progress — Backlog move 2: rules loading and persist validators (#319)

## Session 2026-11-22

- Plan-mode exploration — phases approved by user
- Created branch `319-backlog-move-2-rules-loading-and-persist` off origin/main (f3e331d); claimed #319 in-flight
- Scaffolded PWF baseline from issue #319 with approved phases
- Next: start Phase 1
- Phase 1 (#267): two C-locale tests, red on the unfixed loader (empty rules; truncation after a mid-file em-dash), green after reading with `yaml.load(readLines(encoding = "UTF-8"))`. test-frs_params.R: 0 fail.
- Phase 2 (#222 rules): `.frs_validate_rule_range()` shared by mad/gradient/channel_width (finite, min <= max, per-element); generic "has no value for" check on every other key; loader stores the three ranges as numeric. Bad-gradient test message updated. params/utils/near_river/predicates test files: 0 fail.
- Phase 3 (#250, #251): `build_wb_pred()` reads `.frs_waterbody_tables()` (L = lakes + manmade, floor on each; W string byte-identical). `.frs_run_connectivity()` passes no floor when the rule declares none; `.frs_connected_waterbody(waterbody_ha_min = NULL)` drops the area clause. The SK/KO live check is replaced by a stronger one: with a declared floor the emitted SQL is byte-identical (`WHERE lp.area_ha >= 200 AND ST_DWithin(...)`, old and new), and every shipped bundle declares 200. habitat/predicates/connectivity_wsg/bucket_connected: 0 fail (live against the .Renviron fwapg).
- Phase 4 (#239, #222 col_join): `.frs_query_col_types()` (result OIDs -> `format_type`) replaces the `information_schema` lookup and the `text` fallback. Chose this over the plan's temp table: no DDL or temp privilege, same typmod-free types as before (measured: link's channel_width / channel_width_source / stream_order_parent read `double precision` / `text` / `integer` both ways; ltree and geometry now named instead of `USER-DEFINED`). Live tests: subquery typed, unqualified pg_temp source typed (old lookup could not see pg_temp), ltree, missing column errors before ALTER. test-frs_col_join.R: 22 pass, 0 skip.
