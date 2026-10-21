# Code-check round 1: branch 263-inherit-near-river-from-the-thresholds-c (merge-base c5015f0)

## Checklist read

- `code-check-infra.md`: in full (36,939 bytes).
- `code-check.md` (329 KB): the prose of all 14 H3s under `## Mechanisms`, table rows and evidence blocks skipped. Of `## Rules that stand alone`, Security and Spreadsheets/PDFs I read the index lines only (20 headings not opened), because none names a tool or shape this diff uses.
- `code-check-r.md` (175 KB): I read 8 sections in full: "CSV whitespace: `trim_ws` and `strip.white`…", "`$` on a list partial-matches…", "`nzchar(NA)` is TRUE…", "Postgres row order is never fixed…", "`sprintf("%g", x)` writes `Inf` and `NA`…", "A value compared as `::text`…", "`data.frame()` recycles a scalar…", and "R's `yaml` returns a mixed int/float…" (heading only, already known). I read the other index items as index lines only.
- `code-check-shell.md` (121 KB): index lines only. The diff has no shell code; the psql/heredoc items do not apply.
- `code-check-spatial.md` (154 KB): index lines only. I checked the two FWA items against the walk SQL ("FWA main flow is not edge type 1000 alone", "FWA `upstream_route_measure`…"); the diff leaves the walk's edge-type and measure logic as it was.

## What I verified clean

I checked the invariant (pairs walked equal pairs read) by reading the code and running it.
- The compiler and `.frs_near_river_specs()` see the same rules: both go through `.frs_stage_rules()` (area_only filter, and under mad the `channel_width` drop).
- They see the same inheritance: both use `.frs_stage_inherit()`.
- They use the same resolver: `.frs_rule_near_river()`, whose default `size_parts` is the compiler's own `.frs_rule_size_parts()`.
- `pred_models` selects exactly what `.frs_preds_by_model()` consumes: all mad gives mad, an empty table gives cw, a mix gives both.
- `sp_classify` matches the `species_params` filter.
- Lake/wetland bucket predicates never take a pair.
- The walk SQL's `sprintf` has 19 placeholders and 19 arguments.

Tests in a scratch copy, with `NOT_CRAN=true` and the local fwapg:

| test file | pass | fail | error |
|---|---|---|---|
| `test-near_river_inherit.R` | all | 0 | 0 |
| `test-near_river_rules.R` | all | 0 | 0 |
| `test-frs_near_river.R` | 54 | 0 | 0 |
| `test-frs_habitat_predicates.R` | 111 | 0 | 0 |
| `test-frs_params.R` | 178 | 0 | 0 (2 skips) |

The roxygen examples of `frs_habitat_predicates()` also run.

## Findings

- **[severity: bug] R/frs_params.R `.frs_build_near_river()`, the `get()` helper (about line 763) and the `measure` check below it.**
  - **What happens:** a blank `<stage>_river_measure` cell stops `frs_params()`. `utils::read.csv()` reads an empty field in a character column as `""`, not `NA`. `get()` treats only `NA` as unset, so `""` becomes the measure and fails the `%in% measures` check with `CH rear: rear_river_measure must be one of discharge, channel_width, stream_order, model, got ''`.
  - **When it bites:** this is the ordinary way to write the column when only some species set a measure. The empty cell can come from a spreadsheet edit, `write.csv(na = "")`, or a writer that emits `""` for empty strings. link's own thresholds CSVs already write `""` for an empty `rear_edge_types`. So the first bundle that sets `rear_river_measure` for one species fails to load for every species.
  - **Reproduced:** in a scratch copy, BT set to `channel_width` and the other species blank stops `frs_params()`. The same frame written with `NA` loads.
  - **Why the tests miss it:** the byte-identity and "NA columns" tests write the cells with `write.csv()`'s default `na = "NA"`, so they never reach this case (`code-check-r.md`, "`nzchar(NA)` is TRUE…": `read.csv()` yields `""` for an empty field).
  - **Fix:** treat `""` (after `trimws`) as unset in `get()`.

- **[severity: fragile] R/frs_habitat_classify.R, around lines 201-216 vs 322-327, and R/frs_near_river.R `.frs_near_river_table()`.**
  - **What happens:** the refusal of a 0.41.0-shape `<to>_near_river` table fires after classify has already deleted the group's rows from `to`. Classify checks the measure columns up front (the NEWS line reads "checks each measure's column before it writes anything"). But the shape check lives in `frs_near_river()`, which runs after the `CREATE TABLE IF NOT EXISTS <to>`, the per-group `DELETE FROM <to>` (overwrite) and the access-table builds.
  - **Effect:** a host carrying a 0.41.0 `<to>_near_river` table, the documented upgrade case, loses that group's habitat rows in `to`, leaves `<table>_acc_*` tables behind, and only then gets "drop it and re-run".
  - **Reproduced:** scratch schema; `to` held one CH row for group TEST; 0.41.0-shape `hab_near_river`; inherited pair set; `gate = FALSE`. After the stop, `to` held 0 rows and `streams_acc_all` was left behind.
  - **Why it matters:** in link's pipeline `to` is a working schema, so a re-run recovers, but the delete is not atomic with the work that replaces it (`code-check-infra.md`, "Two-statement DELETE/INSERT into a persist table is not atomic"; `code-check.md`, "Where the guard sits").
  - **Fix:** run the shape check (or `.frs_near_river_table()` itself) beside the column check, before any write.

No other real issues found.

/Users/airvine/Projects/repo/fresh/planning/active/review-round1.md
