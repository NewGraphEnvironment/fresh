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

