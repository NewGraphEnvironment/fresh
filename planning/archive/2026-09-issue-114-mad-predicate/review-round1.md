# Code review round 1: #114 mad_m3s enrichment + `mad` predicate

Scope: uncommitted diff vs HEAD (R/frs_params.R, R/utils.R, R/frs_network_segment.R,
R/frs_habitat.R, R/frs_habitat_predicates.R, man/). Checked against soul
`code-check.md` + `code-check-r.md`.

Verified against local fwapg: `whse_basemapping.fwa_stream_networks_discharge` is on the
search_path, `mad_m3s` is `double precision` (so `frs_col_join` types the new column
correctly, not `text`), and `linear_feature_id` is unique (2,716,652 rows = 2,716,652
distinct), so the `UPDATE ... FROM` join cannot fan out. `frs_break_apply()` carries the
new column dynamically through `.frs_table_columns()`.

## Findings

- **[severity: bug]** R/frs_network_segment.R:156-160 (new join), with R/frs_habitat.R:476-478
  and R/frs_habitat.R:634-635 (pre-existing persist step). The persist step runs
  `CREATE TABLE IF NOT EXISTS <to_streams> AS SELECT * ... LIMIT 0` and then
  `INSERT INTO <to_streams> SELECT * FROM <streams_tbl>`, which maps columns by position.
  The new `mad_m3s` column goes in after `channel_width_source` and before `id_segment`,
  because `.frs_add_id_segment()` runs after enrichment. Any `to_streams` table that a
  pre-#114 run already created is therefore one column short. The next per-WSG or
  incremental `frs_habitat(..., to_streams = <existing>)` run fails with "INSERT has more
  expressions than target columns". The earlier `DELETE FROM <to_streams> WHERE
  watershed_group_code = ...` has already run in the same non-transactional sequence, so
  that WSG's persisted rows are removed and nothing is written back.
  Fix options: build the INSERT from an explicit column list (the intersection of the
  columns in both tables, or `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` for missing ones
  before inserting). Otherwise, state in NEWS that existing `to_streams` tables must be
  dropped or rebuilt.
  (code-check.md: "Written data outlives the fix".)

- **[severity: fragile]** R/frs_params.R:199-207 and R/utils.R:313-318. The `mad` validator
  accepts non-finite bounds. YAML `mad: [0.1, .inf]` parses to `c(0.1, Inf)`, which passes
  `is.numeric` / `anyNA` / `min <= max`. `.frs_sql_num(Inf)` then emits `Inf`, and the
  predicate becomes `s.mad_m3s BETWEEN 0.1 AND Inf`, which Postgres rejects ("column inf
  does not exist") at classify time rather than at parse time. This is a plausible input,
  because `frs_params()` itself uses `Inf` for an open-ended CSV `mad_max` (frs_params.R:495).
  Adding `all(is.finite(mad))` to the validator would catch it at load.

No other issues found. The `unlist()` normalization handles mixed int/float YAML lists.
`mad: []`, a 1-element list, strings and logicals all fail validation. `[[` is used
throughout, so there is no partial matching. The CSV-range non-inheritance is intentional
and was not flagged.
