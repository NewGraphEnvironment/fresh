# Code-check: Phase 5 (docs) round 1

Diff: NEWS.md 0.40.0 entry, CLAUDE.md "Point snap" section and the R/ line, the
`frs_candidates_pick()` roxygen change, its man page, and the PWF files.

## Findings

- **[severity: bug]** NEWS.md, `frs_feature_find` bullet 2: "A `label_map` now works on an integer or logical `label_col`."
  This is false for a logical column. `.frs_label_expr()` (R/frs_break.R:388) builds
  `WHEN label_col::text = '<key>'`, and Postgres renders a boolean as text in lower case:
  `'true'` / `'false'`. A map written the way R users write it, `c("TRUE" = "blocked")`, never matches.
  The CASE then falls through to `ELSE label_col::text` and the label comes out as `'true'`.
  This was run against local fwapg:
  `SELECT CASE WHEN b::text = 'TRUE' THEN 'blocked' ELSE b::text END FROM (VALUES (true),(false)) v(b)`
  returns `true`, `false`.
  Before this branch the same call failed with `invalid input syntax for type boolean: "blocked"`. Now it
  silently writes the wrong label. With the default `label_block = "blocked"`, those features stop blocking
  access. The test meant to cover this, `tests/testthat/test-frs_break.R:214-220`, asserts the SQL string
  `WHEN barrier_ind::text = 'TRUE'`. A boolean can never match that string, so the test pins the defect.
  The integer case is correct: `i::text = '1'` matches.
  Fix one of two ways:
  - Normalise both sides, e.g. `lower(label_col::text) = lower('<key>')`.
  - Document that the keys for a logical column are `"true"` / `"false"`.

  Then change the test to run against a real boolean value.

- **[severity: bug]** NEWS.md, `frs_feature_find` bullet 2: "A failing call no longer drops an existing `to`."
  This holds only for failures in the R-side checks or the snap. `.frs_feature_find_write()`
  (R/frs_feature_find.R) still runs `DROP TABLE IF EXISTS to` and then `CREATE TABLE to AS ...` as two
  separate autocommitted statements. Anything that fails in the CREATE therefore drops `to`: a bad `where`,
  a missing `col_blk` / `col_measure` / `col_id` / `label_col` in `points_table`, or a missing `table`.
  Reproduced with temp tables: `frs_feature_find(conn, "pg_temp.ff_streams", to = "pg_temp.ff_to", points_table = "pg_temp.ff_pts", where = "no_such_col = 1")`
  errored, and `to_regclass('pg_temp.ff_to')` was NULL afterwards, so the existing `to` was gone.
  Fix one of two ways:
  - Narrow the claim to "a call that fails its checks or its snap".
  - Run DROP and CREATE in one transaction.

- **[severity: fragile]** NEWS.md, `frs_point_snap` bullet 5 ("Subsurface-flow (1425), placeholder (`999.*`) and unmapped segments are never candidates"), and CLAUDE.md:226.
  - The 1425 exclusion is only the default. `exclude_edge_types = NULL` admits 1425 (`.frs_snap_guards()`, R/utils.R:634), so "never" is false for that item. Placeholder and unmapped segments really are never candidates.
  - The CLAUDE.md line just above the new section still says `exclude_edge_types` "NULL = snap to everything". That is false: NULL still excludes `999.*` and NULL-localcode segments (`.frs_stream_guards()`). The new section's own statement of the guard contradicts it.

- **[severity: fragile]** NEWS.md, the `frs_watershed_split()` line and bullet 5 ("the `fwa_indexpoint()` path is gone").
  - The old default path, `whse_basemapping.fwa_indexpoint()` (definition read from fwapg), excluded `edge_type = 6010`. The new lateral snap does not.
  - fwapg has 137 segments of type 6010 ("connectors for streams that leave and re-enter a watershed group") that pass the placeholder and unmapped guards. `frs_watershed_split()`, and anyone who used the old default path, can now snap to them where they could not before.
  - The entry lists only exclusions that were added. It also does not say that `frs_watershed_split()` now excludes `999.*` and unmapped segments, which `fwa_indexpoint()` did not.

  A reader comparing old and new results would find differences the entry does not explain. Either list the 6010 change, or add 6010 to the default exclusions and say so.

## Checked and correct

- **Counts in NEWS and CLAUDE.md**: all match `ALL_summary.csv` and `ALL_nf1.csv`.
  - 19,905 PSCIS, 18,180 same, 22 tie and 11 link_999. With 1,692 neither, these add up to 19,905, and nf1_differ, link_only and fresh_only are all 0.
  - All 22 ties are on the same `blue_line_key` and the same distance, with |Δdrm| = 1 exactly ("at most 1 m" holds).
  - "No other differences" holds.
  - The logs were made at db1e959. No R/ code changed between db1e959 and HEAD or in the staging area, so the numbers still apply.
- **37,416**: confirmed against local fwapg with `wscode_ltree <@ '999' AND wscode_ltree != '999' AND localcode_ltree IS NOT NULL`.
  - The count is the same after excluding 1425 (37,416), because no placeholder segment has edge type 1425.
  - Side note: no segment has `wscode_ltree = '999'` exactly, so link's `!= '999'` guard excludes nothing at all.
- **link's guard** (link R/lnk_points_snap.R): `s.wscode_ltree != '999'::ltree`, `localcode IS NOT NULL`, default 1425, and `ORDER BY s.geom <-> pt` with no tie-break. This matches CLAUDE.md.
- **`frs_point_snap()` facts**:
  - The signature, the 100 m default (it was 5,000 m on main), the output columns, `candidate_rank` only when `num_features > 1`, and `id_point` all match.
  - `col_id` is required for a table, and a missing hint leaves a point unconstrained.
  - The temp table comes from `.frs_db_write_temp()`.
  - The clamp is CEIL(GREATEST(ds, FLOOR(LEAST(us, ...)))).
  - Ties break on `linear_feature_id`.
  - Both old forms of the call, `x = / y =` and positional numeric, raise the migration hint.
- **bcfishobs**: A/B matching is within 100 m (bcfishobs README and `process.sql`).
- **`fwa_indexpoint()`**: it uses `DISTINCT ON (blue_line_key)`, so candidates are per stream. The per-segment contrast in CLAUDE.md holds.
- **`frs_feature_find(points = <sf>)`**: on main it called `frs_point_snap(conn, points)` into a scalar `x` check, so it always failed. Both paths now write `feature_id` as text.
- **`frs_watershed_split()`**: it now snaps in one query, measures are whole metres, and 1425 is excluded by default.
- **Vertex-tie mechanism in CLAUDE.md** (two segments, 1 m apart): this follows from FLOOR on the downstream segment versus GREATEST(ds) then CEIL on the upstream one, and matches the logged ties.
- **Roxygen and man pages**: running `devtools::document()` on a clean copy of the tracked tree reproduces `man/` byte for byte, including `frs_candidates_pick.Rd`. `NAMESPACE` is unchanged.

## Note (not flagged)

- NEWS, CLAUDE.md and the roxygen all say the measure is "rounded to whole metres". The SQL floors it, and the clamp is the only place it is rounded up. A position at 107.9 m reports 107. This is not strictly false, but "truncated" would be accurate.
