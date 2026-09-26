# Code review, round 3 (#114: mad_m3s enrichment + `mad` rule predicate)

## Mechanism

All three earlier findings come from one assumption: **the value at a trust boundary
already has the shape the current code produces, so an implicit coercion can
reconcile any difference.** Nothing checks whether it actually does.

- Persisted tables: a positional `INSERT ... SELECT *` binds by column position and
  applies assignment casts, so a table written by an older run is "reconciled" by
  position. Round 1.
- YAML rules: `unlist()` and R's vector coercion turn whatever the parser returned into
  a numeric vector. `.inf` is a finite-looking double and `[true, 5]` becomes `c(1, 5)`.
  Rounds 2 and 3.

The fix pattern is the same both times. Discriminate at the boundary: explicit column
names instead of positions, and per-element type checks instead of checking after
`unlist`. Then fail loudly on anything the code did not produce itself.

## Where the mechanism reaches, checked

| Site | Status |
|---|---|
| `R/frs_habitat.R:463-480`, `:623-639` (`to_streams`, serial and parallel) | Fixed. Named insert plus `.frs_persist_columns()`. Verified on local PG: a stale target gains `mad_m3s`; ltree and geometry types round-trip through `format_type()`; column add and INSERT both run before the partition DELETE fails, so an error cannot orphan the delete. |
| `R/frs_break.R:668-711` (`frs_break_apply`) | Safe. Column lists come from `.frs_table_columns()` on the live table, so `mad_m3s` is carried through splits. |
| `R/frs_habitat.R:1077` (`frs_habitat_species`) | Safe. Fresh `CREATE TABLE AS`, no long-lived target. |
| `R/frs_col_join.R` via the new discharge join | Type is discovered from `information_schema`. Local check: `whse_basemapping.fwa_stream_networks_discharge` exists, `mad_m3s` is `double precision`, and `linear_feature_id` is unique under a PK (2,716,652 rows, 0 dups, 0 NULL), so it is 1:1 as claimed. |
| `.frs_load_rules` / `.frs_validate_rule` for `mad` | Per-element `is.numeric`, `is.finite`, length 2, `min <= max`. Verified that `[a, b]`, `[0.5]`, `.inf`, `[true, 5]` and `[]` all error. `[1e-3, 5]` parses `1e-3` as a string in R yaml, which errors loudly. That is acceptable. |
| `.frs_rule_to_sql` `mad` branch | Consumes the vector normalised by `.frs_load_rules`. The `unlist` there is a no-op on validated input. |

## Findings

- **[fragile] R/frs_params.R:199 and :166 (new `mad` guard): `mad:` with no value
  loads as "no MAD filter".** This is the same mechanism on the absent side. `mad:`,
  `mad: ~` and `mad: null` all parse to `NULL` in R yaml. `!is.null(rule[["mad"]])`
  then skips validation and `.frs_rule_to_sql` emits no predicate. Verified: a rule
  `{mad: , gradient: [0.0, 0.05]}` loads cleanly and produces
  `(s.gradient BETWEEN 0 AND 0.05)`. The committed config reads as MAD-filtered but
  applies none, which is a guard failing toward pass. Absent and present-empty are
  different states. Test `"mad" %in% names(rule)` and reject a NULL value (for
  example, error when `"mad" %in% keys && is.null(rule[["mad"]])`). The other
  predicates share this pre-existing shape; see below. `mad` is new in this diff.

- **[fragile] R/utils.R `.frs_persist_columns()`: it aligns column NAMES but not
  TYPES, so a type drift is still reconciled silently.** The helper adds missing
  columns, but any column that already exists keeps the target's type, and the named
  INSERT applies an assignment cast. Verified on local PG: a target with
  `mad_m3s text` accepted the `double precision` source value and stored `'0.5'` as
  text, with no error. Any later `s.mad_m3s BETWEEN ...` on that persisted table then
  fails with a text-vs-numeric operator error, or compares as text in a consumer. The
  realistic path into this state is `frs_col_join()`'s pre-existing fallback: when the
  `information_schema` lookup misses, it adds the column as `text`, and the first run
  that does so fixes `to_streams.mad_m3s` as text for every later run. Low
  likelihood, but this is the helper written to close the mechanism, so it should
  compare `format_type()` for the shared columns and `stop()` on a mismatch rather
  than cast.

The diff creates no other instance. The new discharge join, `frs_habitat_partition`
and the parallel worker path were all checked. Concurrent `ALTER TABLE ... ADD COLUMN
IF NOT EXISTS` from several mirai workers serialises on the AccessExclusive lock, and
the loser re-reads the catalog and no-ops.

## Pre-existing, out of scope (same mechanism, not touched by this diff)

- `R/frs_habitat_classify.R:139-150, 272`: `to_habitat` uses `CREATE TABLE IF NOT
  EXISTS` with a fixed schema and then a named INSERT that includes `wetland_rearing`.
  A `to_habitat` persisted before that column existed errors on INSERT after the
  per-WSG DELETE has already run. This is the round-1 shape; `.frs_persist_columns()`
  does not apply because the source is a SELECT, not a table.
- `R/frs_feature_find.R:161-167` (`append = TRUE`): a target created without
  `feature_id` errors on a later append with `col_id` set.
- `R/frs_col_join.R`: type lookup falls back to `text` silently when the source is not
  found in `information_schema` (unqualified name not matched in the parsed
  `search_path`, or a privilege gap). It also takes the last row when two schemas on
  `search_path` hold the same table name.
- `R/frs_params.R:334-342` (`gradient`, `channel_width` rule fields): these require an
  atomic numeric of length 2 but do not check `is.finite` or `min <= max`.
  `gradient: [0.05, 0.01]` passes and matches nothing, silently. `.inf` passes and
  emits `inf` into SQL, which errors loudly. Also, R yaml returns mixed int/float
  sequences such as `[0, 0.05]` as a list, which these validators reject, so valid
  configs must be written `[0.0, 0.05]`. That fails loudly.
- All rule fields: empty values (`gradient:`, `lake_ha_min:`, etc.) parse to NULL and
  are treated as absent, like `mad` above.
- `to_barriers` positional `INSERT ... SELECT *`: accepted tradeoff.

## Verification

- `test-utils.R`: 30 pass. `test-frs_params.R`: 142 pass, 3 fail. The 3 failures are
  the accepted `:92` failure and the bcfishpass-schema errors off-tunnel.
- Scratch tables `working.r3_src` and `working.r3_dst` were created and dropped.
