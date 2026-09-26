# Findings — Phase 2: enrich streams with mad_m3s and add mad predicate to rule evaluator (#114)

## Exploration (2026-09-25)

- `whse_basemapping.fwa_stream_networks_discharge` exists in local fwapg: `linear_feature_id int, watershed_group_code text, mad_mm double, mad_m3s double`. 2,716,652 rows; 2,003,189 non-NULL `mad_m3s` (~26% NULL).
- `.frs_build_ranges()` (`R/frs_params.R`) already builds `ranges$spawn$mad_m3s` / `ranges$rear$mad_m3s` from CSV; unused downstream.
- `.frs_validate_rule()` hard-stops on `mad` (Phase 1 deferral to #114).
- `.frs_rule_to_sql()` lives in `R/utils.R`; gradient/channel_width follow override-then-inherit pattern from `csv_thresholds`.
- `frs_habitat_predicates()` CSV-only path builds gradient + channel_width + edge types; ignores mad.
- channel_width join sites: `R/frs_network_segment.R:147`, `R/frs_habitat.R:818`.
- Bundled `parameters_habitat_method.csv` (bcfishpass example_newgraph): all 187 WSGs = `cw`. fresh never reads it.
- Decision: rules-explicit only (Option B). CSV MAD not inherited/applied — avoids changing cw-model outputs. Per-WSG model switch → follow-up issue.

## Issue context

## Problem

Habitat eligibility rules (#113 Phase 1) handle edge_type, waterbody_type, gradient, and channel_width predicates. They cannot evaluate `mad` (mean annual discharge) predicates because the segmented streams table produced by `frs_network_segment()` (fresh 0.11.0) does not carry a `mad_m3s` column.

bcfishpass v0.5.0 uses MAD-based habitat classification for many southern BC watershed groups (BULK, LDEN, etc.) — the `parameters_habitat_method` table sets `model = 'mad'` for those groups. Per-species MAD thresholds in `parameters_habitat_thresholds.csv` (e.g. CO `spawn_mad_min = 0.164`, `rear_mad_min = 0.03`, `rear_mad_max = 40`) are required to match those WSGs.

For ADMS the model is `cw` (channel width) so MAD doesn't apply. Phase 2 unblocks the rest of the province.

## Proposed Solution: Phase 2 of #113

### 1. Enrich segmented streams with mad_m3s

`R/frs_network_segment.R` already calls `frs_col_join` to add `channel_width` from `whse_basemapping.fwa_stream_networks_channel_width` joined on `linear_feature_id`. Add a parallel call:

```r
frs_col_join(conn, to,
  from = "fwa_stream_networks_discharge",
  cols = c("mad_m3s"),
  by = "linear_feature_id")
```

Verify the source table exists in fwapg (`whse_basemapping.fwa_stream_networks_discharge` or similar).

### 2. Add `mad` predicate to the rule evaluator

In `R/frs_habitat_classify.R`, extend the rule evaluator from #113 to support:

```yaml
- mad: [0.164, 9999]
```

Translates to `s.mad_m3s >= 0.164 AND s.mad_m3s <= 9999`.

### 3. Update CSV defaults if needed

The CSV-only species classification path (for species not in the rules file) currently builds `spawn_cond`/`rear_cond` from `params$ranges$spawn$mad_m3s` and similar. fresh 0.11.0 already parses MAD ranges in `frs_params()` (verified — `params$CO$ranges$spawn$mad_m3s` is set to `c(0.164, 9999)`) but `frs_habitat_classify()` doesn't apply them. Either:
- A: Apply MAD predicates in the CSV-only path too
- B: Require MAD-using species to be in the rules file

Option A is more transparent (CSV row "just works"). Option B is simpler implementation.

## Test approach

Use a MAD-model WSG (BULK or LDEN) sub-basin. Run frs_habitat with a rules file that uses MAD predicates for CO/CH/SK/ST. Assert MAD-filtered classification matches expectations.

For ADMS (cw model) this should be a no-op — MAD predicates not used.

## Dependencies

- #113 Phase 1 (rule format and evaluator)
- Verify `whse_basemapping.fwa_stream_networks_discharge` schema in fwapg

## Relates to

- #113 Phase 1 — depends on this for the evaluator to extend
- bcfishpass v0.5.0 — reference for which species/WSGs use MAD model


## Code-check enumeration (2026-09-25)

Round 3 found a defect inside round 1's fix: `.frs_persist_columns` matched names but not types. So the loop ended on an enumeration, not a quiet round. **Mechanism:** a value crosses a trust boundary (a persisted table, a parsed YAML value), and an implicit coercion reconciles the shape difference without checking it. The candidate set this diff touches, with each item closed:

**Persist boundary: `to_streams` in `frs_habitat()`, serial and mirai paths (7)**
1. Column set: missing columns are added by `ALTER ... ADD COLUMN IF NOT EXISTS`.
2. Column order: the INSERT now uses a named column list.
3. Shared-column type: a mismatch stops the run before any ALTER or DELETE (test added).
4. Target-only columns: they get NULL (verified by the round-2 reviewer).
5. Generated or NOT NULL columns on the target: CTAS copies neither, and a violation would error loudly.
6. Concurrent ALTER: the table lock serialises it, and IF NOT EXISTS makes the later calls a no-op.
7. Other append sites (`break_apply`, `habitat_species`, `to_habitat`, `to_barriers`): none of them receive `mad_m3s` through a positional insert.

**YAML `mad` boundary (8)**

Rejected, each with a test:
1. Missing value: `mad:`, `~`.
2. Non-numeric element: `[a, b]`, `[true, 5]`.
3. Nested element: `[[0.1, 0.2], 5]`. `[[0.1], 5]` is collapsed by yaml to `[0.1, 5]` before R sees it, so it means the same thing and is harmless.
4. Wrong length: `[0.5]`, `[0.5, 1, 2]`, `0.5`.
5. Non-finite: `.inf`.
6. Reversed range: `[10, 1]`.

Handled without rejection:
7. Mixed int and float, e.g. `[0.164, 9999]`: normalised with `as.numeric`.
8. Scientific notation, e.g. `1e-3`: yaml reads it as a string, so it's rejected loudly (round 3).

**Evaluator boundary (1)**
- The only entry point is `.frs_load_rules()`, reached via `frs_params(rules_yaml=)`. `.frs_sql_num()` errors on character input.

Pre-existing instances outside this diff are listed in `review-round3.md`: `to_habitat` persist, `frs_feature_find` append, the `frs_col_join` text fallback, and `gradient`/`channel_width` validation. They're candidates for a follow-up.
