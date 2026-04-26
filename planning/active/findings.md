# Findings

## Param naming review (2026-04-25)

Surveyed fresh's existing exported functions for parameter naming
conventions to keep the new helper consistent.

| param | meaning | seen in |
|---|---|---|
| `conn` | DBI connection | every DB function |
| `table` | input streams table (schema-qualified) | `frs_habitat_classify` etc. |
| `to` | output table (schema-qualified) | `frs_habitat_classify`, `frs_break_apply` |
| `species` | species code(s) — vector or scalar | `frs_habitat_classify`, `frs_aggregate` |
| `barrier_overrides` | optional schema-qualified table for per-species barrier skip | `frs_habitat_classify` |
| `gate` | logical, optional access gating | `frs_habitat_classify` |
| `overwrite` | logical, replace vs append | most write fns |
| `verbose` | logical, progress output | every long-running fn |
| `where` | optional SQL predicate | `frs_aggregate` |

**Decision for `frs_habitat_known()`:** use `known` for the
known-habitat table arg (analogous to `barrier_overrides`), `species`
for the filter, `habitat_types` as a defaulted vector. No `to` /
`overwrite` because the function is in-place UPDATE on `table`.

## Existing helpers to reuse

- `.frs_db_execute(conn, sql)` — wraps DBI::dbExecute with logging.
- `.frs_quote_string(x)` — quotes string literals safely for SQL.
- `.frs_validate_identifier(x, label)` — schema/table identifier safety.
- `.frs_sql_num(x)` — numeric scalar to SQL.

## bcfishpass column-mapping convention

`bcfishpass.streams_habitat_known` columns:

```
segmented_stream_id (PK)
spawning_bt, spawning_ch, spawning_cm, spawning_co, spawning_pk, spawning_sk, spawning_st, spawning_wct
rearing_bt, rearing_ch, rearing_co, rearing_sk, rearing_st, rearing_wct
```

Pattern: `{habitat_type}_{lcase(species)}`. Booleans (or null = no
known data). bcfishpass's `streams_habitat_linear` then derives
the integer encoding `spawning_sk = 3` for known-only segments.

link's `user_habitat_classification.csv` has the same shape.

**Decision for fresh helper:** assume the known table follows the
`{habitat}_{species_lower}` column convention. If a column is absent,
treat it as "no known data for this species/habitat pair" and emit a
verbose message — don't error.

## Update SQL shape

```sql
UPDATE <table> AS h
SET <habitat> = TRUE
FROM <known> AS k
WHERE h.id_segment = k.id_segment            -- assuming both have id_segment
  AND h.species_code = '<sp>'
  AND k.<habitat>_<sp_lower> IS TRUE;
```

Wait — fresh's `streams_habitat` uses `id_segment` and `species_code`
(long-format). bcfishpass's `streams_habitat_known` uses
`segmented_stream_id` (wide-format, one row per segment, columns per
species). Need to map id_segment ↔ segmented_stream_id.

In link's pipeline, `<schema>.user_habitat_classification` is loaded
via `lnk_pipeline_prepare` with `linear_feature_id, blue_line_key,
downstream_route_measure, ...` plus the per-species columns. The
join key on the link side will be `(blue_line_key, downstream_route_measure)`
which fresh's segmented streams also carry. Use that compound key.

**Decision:** the helper takes the join key as an argument
(`by = c("blue_line_key", "downstream_route_measure")`) so callers
can choose whichever stable key they have. Default to that pair.
