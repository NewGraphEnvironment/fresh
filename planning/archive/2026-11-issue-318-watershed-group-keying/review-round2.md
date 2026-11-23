# Code-check round 2: branch 318 (HEAD a522499, merge-base a00ad5d)

## Checklist read

- code-check-infra.md: in full.
- code-check.md: the prose of all 14 H3s under `## Mechanisms`, table rows skipped. No headings read under the other sections; about 30 left unread there (none matched a tool or shape this diff uses beyond what Mechanisms covers).
- code-check-r.md: 8 headings read: "Postgres row order is never fixed unless the query fixes it…", "testthat counts an uncaught error under `error`, not `failed`", "An `information_schema` lookup by the literal table name misses what Postgres resolves", "A `data-raw/` script must load the source tree, not the installed package", "`tryCatch()` nests its handlers…", "A `function(...)` mock hides arguments the real callee no longer accepts", "A `pkg::` call in a test passes `devtools::test()` and fails `R CMD check` if `pkg` is undeclared", "Under `R CMD check`, tests run from a temp dir against the INSTALLED package". About 160 not read.
- code-check-shell.md: none read (the diff has no shell). About 95 not read.
- code-check-spatial.md: none read in full. The FWA measure-gap fix overlaps "FWA `upstream_route_measure` misses the next segment's start", which I took from the index line. About 120 not read.

## Findings

- **[severity: fragile]** tests/testthat/test-frs_habitat.R:302-312: the new #294 assertion in "integration: to_barriers persists gradient barriers table" can never fail. Its comment says the table "would also hold the parts of those lines outside the AOI" without the scope. The AOI, though, is a `wscode_ltree <@` subtree, and in the FWA every segment of a blue line carries the same watershed code. So the barrier finder's blue lines lie wholly inside the AOI: 0 of their 189 segments are outside it (measured on the docker fwapg, 2026-11-22).
  - Proof by mutation in a detached worktree: I changed `owned` in `.frs_persist_barriers()` to `TRUE OR linear_feature_id IN (…)`, so the delete and the insert both cover every row. That test still passed, with 10 expectations, 0 failed and 0 errors.
  - The scoping itself is covered by `test-persist_barriers_294.R` on synthetic tables, so nothing is untested. What is wrong is this test's comment, which claims coverage it does not give.
  - The fix is either an AOI whose blue lines extend past it (a polygon, or a single watershed group whose mainstem runs into another group), or rewording the comment to say what the assertion actually checks (no NULL-keyed rows).
  - **Rule:** code-check.md "A fixture that cannot reach the failure mode"

## Checked and found sound (no finding)

- **link:**
  - `<schema>.streams` is built from `fwa_stream_networks_sp WHERE watershed_group_code = <aoi>` (`lnk_pipeline_prepare.R:879`) and carries `linear_feature_id`. Before this branch `frs_habitat_classify()` already refused a NULL group on that same table. So the new guards in `frs_cluster` (via `.frs_run_connectivity`), `frs_order_child` and bridged `frs_habitat_overlay` cannot fire on a link run, and each costs one `EXISTS` over a single-group table.
  - link uses `frs_habitat_overlay()` only in bridged mode, so the #277 direct-mode guard does not reach it.
  - link uses neither `to_barriers` nor `.frs_enrich_breaks`. `frs_break_find`, `frs_break_apply` and `.frs_run_connectivity`'s signature are unchanged.
- **Round-1 fix 1 (bounding by `lead(downstream_route_measure)`):**
  - The window's order is unique: no `(blue_line_key, downstream_route_measure)` pair repeats in `fwa_stream_networks_sp` (0 duplicates, measured). Each barrier therefore falls in exactly one range and `UPDATE … FROM` matches at most one row.
  - The default arm is byte-identical to main's. `frs_network_segment()` and `frs_habitat_access()` still use it.
- **Round-1 fix 2:** the `ID_SEGMENT` case and the `tolower()` are gone. The remaining overlay #277 cases reach the guard: the stubs feed `to_cols` and `from_cols`.
- **`.frs_persist_barriers()`:**
  - The NULL-key guard runs before the delete.
  - The delete and the insert share one transaction, and a nested transaction is handled the way `.frs_persist_streams()` handles it.
  - An unkeyed barrier is excluded by `IN` (NULL is not in the set).
  - `streams_tbl` still exists at step 5b on both the sequential and the mirai paths, and it carries `linear_feature_id`. `frs_network_segment()` applies no stream guards, so every segment of the job's ground is in it.
- **Mocked tests:** with `.frs_group_required()` in the path, the mocked `frs_order_child` tests still pass, because the mock returns no `bad` column and `isTRUE(NULL)` is FALSE. The mocked `frs_cluster` tests stub the guard.
- **Test run on HEAD:** the test files persist_barriers_294, habitat_partition_293, frs_habitat_overlay, frs_cluster, frs_order_child and bucket_connected gave FAIL 0, ERR 0, SKIP 0, PASS 324 against the local fwapg.
