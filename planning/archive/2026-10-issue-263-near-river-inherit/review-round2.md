# Code-check round 2: #262 / #263 (branch 263-inherit-near-river-from-the-thresholds-c)

## Checklist read

- `code-check-infra.md`: in full (36,939 bytes).
- `code-check.md`: the prose of all 14 H3s under `## Mechanisms`, with evidence blocks and `|` rows skipped. Of the 37 H3s in the file, the 23 outside Mechanisms were not read; none names a tool or shape this diff uses.
- `code-check-r.md`: 9 of 111 H3s read: "`nzchar(NA)` is TRUE", "`$` on a list partial-matches", "Postgres row order is never fixed", "`sprintf("%g", x)` writes `Inf`", "An `information_schema` lookup by the literal table name", "CSV whitespace", "A `data-raw/` script must load the source tree", "R's `yaml` returns a mixed int/float sequence", "`on.exit()` at a script's top level". The other 102 were not read.
- `code-check-shell.md`: 0 of 67 read (the only shell is one `system("git rev-parse")` call in a data-raw script).
- `code-check-spatial.md`: 1 of 92 read: "FWA main flow is not edge type 1000 alone". The other 91 were not read.

I went through every index line against the diff. Beyond the sections above, none named a pattern the diff uses.

## Round-1 fixes

1. **A blank `<stage>_river_measure` cell.** Fixed. `get()` now treats NULL, NA and a blank or whitespace-only cell as unset, for every `_river_` field. Numeric blanks were already NA after `as.numeric()`. I checked the same question in the other places it could arise:
   - YAML `near_river: ""` is refused, loudly, by the "named mapping" error.
   - `near_river: {}` and an empty `near_river:` are refused too.
   - On the DB path (`conn`), a text column holding `''` goes through the same `get()`.
   - The test `a blank cell is unset, as NA is` passes.
2. **A 0.41.0-shape near-river table.** Fixed for that table. `.frs_near_river_check_shape()` runs in classify before `CREATE TABLE <to>` and the per-group DELETE, and `to_regclass()` resolves the name the way the later statements do. The round-1 test passes. I then listed every `stop()` in `frs_near_river()` and asked which of them classify runs before its delete. One is not covered (finding 1).

Test runs, from a `git archive HEAD` copy with `NOT_CRAN=true` (failed / error / skipped / passed):

| file | failed | error | skipped | passed |
|---|---|---|---|---|
| test-near_river_inherit | 0 | 0 | 0 | 187 |
| test-near_river_rules | 0 | 0 | 0 | 76 |
| test-frs_near_river | 0 | 0 | 0 | 54 |
| test-frs_habitat_classify | 0 | 0 | 0 | 55 |

## Findings

- **[severity: fragile]** R/frs_habitat_classify.R:200-216 together with R/frs_near_river.R:148-165. The round-1 defect is still there, one axis over: `frs_near_river()`'s other input checks run after classify has deleted the habitat rows.
  - **What classify checks before writing:** only the measure columns (`near_cols`) and the table shape.
  - **What classify leaves unchecked:** `frs_near_river()` also stops when the streams table lacks any of `blue_line_key`, `watershed_key`, `downstream_route_measure`, `wscode_ltree`, `localcode_ltree`, `edge_type`, `waterbody_key`, `length_metre` or `geom` (`cols_need`). Classify calls it at line 327, which is after the `DELETE FROM <to> WHERE watershed_group_code = ...` at lines 236-242. Some of those columns, such as `watershed_key` and `geom`, are read by nothing else in classify.
  - **Reproduced** (scratch copy, the round-1 test's setup with `watershed_key` dropped from `pg_temp.nr_streams`): classify stops with "pg_temp.nr_streams has no watershed_key column (frs_near_river() needs the columns frs_network_segment() writes)", and `pg_temp.nr_hab` has gone from 1 row to 0. This is the "DELETE/INSERT is not atomic" shape, and the guard-placement rule: "A check that exists only in the post-write verifier refuses after the write it should have prevented".
  - **Why it matters now:**
    - In 0.41.0 the path needed an explicit `near_river:` mapping on a rule.
    - With #263, a populated `<stage>_river_*` cell in a thresholds CSV puts every classified species with a size-tested rule on this path.
    - A caller-built table that classified fine before can therefore now lose that call's groups' habitat rows and then stop.
    - A table from `frs_network_segment()` carries every column, so the normal pipeline is unaffected.
  - **The same gap, programmatic rules only:** `frs_near_river()`'s `ok_num()` check on `threshold` / `distance_max` also fires after the delete, for a rule set in R (bypassing `.frs_validate_near_river()`) with a value of 0 or less or not finite.
  - **Fix:** move the full `cols_need` check, and the numeric checks on `near_specs`, into a write-free helper. Call it from classify beside `.frs_near_river_check_shape()`, as round 1 did for the shape check.

No other issues found:
- **Shared resolver:** the compiler and the walk use `.frs_rule_near_river()` with the same `.frs_stage_rules()` / `.frs_stage_inherit()` / `pred_models`. Species are filtered the same way in `sp_classify` and `species_params`.
- **`pred_models` and `.frs_preds_by_model()`:** they agree for all-cw, all-mad, mixed, and an empty or NULL-group table.
- **Byte identity with the columns absent or NA:** `out[[size_col]] <- NULL` and `out[["near_river"]] <- NULL` are no-ops, matching the old `[[<-`. The fixture test passes.
- **Partial matching:** the `$` reads on `csv_thresholds` (`gradient`, `channel_width`, `mad_m3s`) have no prefix siblings, and `near_river` is read with `[[`.
- **Data-raw scripts:** they load the source tree unconditionally.
