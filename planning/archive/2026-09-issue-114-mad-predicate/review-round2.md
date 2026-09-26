# Review round 2: fresh#114 (mad_m3s enrichment + `mad` predicate)

## Clean

No issues found.

## What was verified

### Fix (a): `.frs_persist_columns()` and explicit INSERT at both persist sites

- **Both call sites are fixed**: the sequential `.run_job` (R/frs_habitat.R:466/478) and the mirai worker (R/frs_habitat.R:626/637). The helper runs before the partition DELETE at both sites, so if it fails (for example, the target is a view) the DELETE never runs and no data is lost.
- **regclass resolution**: tested against the local fwapg.
  - `'working.RV114_Dst'::regclass` folds case exactly as the unquoted `CREATE TABLE working.RV114_Dst` does.
  - Unqualified names resolve through `search_path`, the same way the preceding `CREATE TABLE IF NOT EXISTS` does.
  - `.frs_quote_string` escapes the literal.
- **Identifier quoting**: `attname` comes from `pg_attribute` in its exact case, so `dbQuoteIdentifier` preserves it for both the ALTER and the INSERT/SELECT lists. `format_type()` produces a usable DDL type: `geometry(LineStringZM,3005)`, `ltree`, `double precision`, `bigint`. It schema-qualifies any type that isn't visible on the search path.
- **Column ordering**: the explicit list makes ordering irrelevant. This also fixes an older silent-misalignment risk. `frs_col_generate()` drops and re-adds generated columns, which moves them to the end, and `gradient_recompute` changes which columns get moved. Under a positional `SELECT *`, same-typed double columns (gradient, the two route measures, `length_metre`) could have been swapped with no error. That risk predates this diff and is now closed.
- **Generated columns**:
  - A generated column in the source is read by the SELECT, which is fine. The column is added to the target as a plain column of the same type. This was verified with a `GENERATED ALWAYS ... STORED` source column.
  - A target built by CTAS has no generated columns.
  - A user-built target with generated columns would fail on the explicit list, but it would equally have failed under `SELECT *`, so nothing is worse.
- **Target has columns the source lacks**: those columns get NULL or their default. Verified with an extra `integer` column. Under the old positional insert this case errored or misaligned, so the change is strictly better.
- **Dropped columns and system columns**: excluded by `attnum > 0 AND NOT attisdropped`.
- **Concurrency across mirai workers**:
  - Each statement autocommits.
  - `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` takes an AccessExclusiveLock before checking whether the column exists, so concurrent workers serialize. The second worker hits the no-op NOTICE rather than a duplicate-column error.
  - A worker whose snapshot said "missing" still inserts correctly after another worker has added the column.
  - With single-statement transactions there is no lock-order deadlock.
  - The CTAS `IF NOT EXISTS` race on a cold start (pg_type unique violation) predates this diff and isn't made worse by it.
- **Namespace access in workers**: the mirai worker reaches the internal helper through the closure's fresh namespace, the same way it already reaches `.frs_run_connectivity` and `.frs_validate_gradient_thresholds`.
- **Other persist or insert paths that gain `mad_m3s`**:
  - `frs_break_apply` builds its INSERT from `.frs_table_columns(exclude_generated = TRUE)`, so `mad_m3s` is carried to child segments.
  - `frs_habitat_species` uses DROP + `CREATE TABLE AS SELECT *` with no append, so it's unaffected.
  - The `to_habitat` INSERT names its columns explicitly.
  - The `to_barriers` sites persist the breaks table, which gets no `mad_m3s`.
  - No other positional append into a table that carries `mad_m3s` was found.
- **Tests**: `test-utils.R` passes against the local fwapg: 30 pass, 0 fail. `test-frs_params.R` has 1 failure and 2 errors, all expected:
  - The failure at `:92` is pre-existing and out of scope.
  - The errors at `:918` and `:931` happen because the local DB has no `bcfishpass` schema. They're environmental.

### Fix (b): the `mad` validator requires `is.finite`

- `.inf` and `.nan` are rejected because `is.finite` is FALSE for both. `[~, 1]` collapses to length 1 and is rejected. A string element makes the vector character, which fails `is.numeric`. `[10, 1]` is rejected by the min <= max check.
- `.frs_load_rules` stores the value as a plain numeric vector. `.frs_rule_to_sql` also calls `unlist`, so a rules list passed directly (without going through the loader) still works.
- `fwa_stream_networks_discharge` has 2,716,652 rows and 2,716,652 distinct `linear_feature_id` values, which confirms the join is 1:1.

## Notes (not bugs; recorded for awareness)

- **`mad` on a lake or wetland rule is silently ignored**: `build_wb_pred` in R/frs_habitat_predicates.R builds the `lake_rear` and `wetland_rear` predicates from CSV channel_width only. A `mad` on a `waterbody_type: L/W` rule (including an `area_only` one) therefore has no effect on those predicates. This matches how rule-level `gradient` and `channel_width` already behave there.
- **YAML booleans are accepted as numbers**: `unlist()` coerces logicals to numeric, so `mad: [true, 5]` validates as `c(1, 5)`. The `gradient` and `channel_width` rules have the same exposure. This is unlikely to come up in real use.
- **The helper test doesn't pin the call sites**: the new test covers `.frs_persist_columns()` directly. Reverting either `frs_habitat()` site back to `INSERT ... SELECT *` would not make any test fail. This is recorded only for the "restore the bug and prove the guard fires" checklist item. Nothing is broken.
