# Findings — frs_candidates_pick: score + filter + dedup candidates per key (#207)

## Issue context

## Problem

When matching point datasets along the FWA network, a single "key" entity (a PSCIS crossing, an observation, a field-assessed crossing) can have multiple candidate matches in another table. Picking the best candidate often requires more than distance — it requires column-to-column comparisons against shared attributes that disambiguate beyond pure geometry: stream name, watershed group, stream order, channel width, species code, observer name, etc.

Concrete driver: bcfp's `04_pscis.sql` at `smnorris/bcfishpass@v0.7.14-125-g6e9cf1c` (bcfp tunnel rebuilt 2026-05-05, `bcfishpass.log.model_run_id=121`) does this for PSCIS-to-stream matching:

```sql
-- per candidate (PSCIS, stream): compute scores
SELECT *,
  CASE WHEN normalize_name(stream_name) = normalize_name(gnis_name) THEN 100
       WHEN stream_name IS NULL OR gnis_name IS NULL THEN 0
       ELSE -100 END AS name_score,
  CASE WHEN downstream_channel_width < 2 AND stream_order >= 5 THEN -100
       ...
       ELSE 0 END AS width_order_score,
  distance_to_stream - distance_to_stream * 0.1 * has_modelled_match AS weighted_distance
FROM candidates p
JOIN streams s ON ...
-- filter obvious disqualifiers
WHERE name_score != -100 AND width_order_score != -100
-- rank by composite criteria
ORDER BY p.stream_crossing_id, name_score DESC, weighted_distance
-- pick best per key
DISTINCT ON (p.stream_crossing_id)
```

The pattern generalizes: filter disqualifiers, score by caller-defined rules, dedup-on-key by composite ORDER BY. fresh doesn't have a primitive for this; it's reinvented per use case.

Discovered while bringing up `frs_point_match` (#206). That primitive does b-side dedup match given single-stream-per-row input; but the *upstream* problem — "which stream is the right one for this PSCIS when multiple are within tolerance?" — needs scoring rules that `frs_point_match` can't (and shouldn't) implement. See `link/research/bcfp_table_map.md` for the full table-relationship analysis. BULK validation surfaced this directly: 5 of 78 expected matches in `frs_point_match` output diverge from `bcfishpass.pscis` because the upstream snap step picked a different stream than bcfp's multi-criteria scoring would have.

## Proposed primitive

`frs_candidates_pick(conn, table_in, table_to, col_key, ...)` — score and pick the best candidate per key from a pre-staged candidates table.

### Signature

```r
frs_candidates_pick(
  conn,
  table_in,            # schema-qualified candidates table (e.g. output of frs_point_snap with num_features > 1)
  table_to,            # schema-qualified destination
  col_key,             # column that identifies which rows compete (e.g. stream_crossing_id)
  score_expr = NULL,   # optional SQL fragment yielding a `score` column, evaluated per row
  filter_expr = NULL,  # optional SQL WHERE clause (disqualifiers, e.g. "score != -100")
  order_by             # vector of "expr ASC/DESC" strings for DISTINCT ON tiebreak
)
```

Returns `conn` invisibly. Side effect: drops + recreates `table_to` with all `table_in` columns plus (when `score_expr` is set) a `score` column, deduped to one row per `col_key` value following the `order_by` ranking.

### Semantics

1. Compute `score` column from `score_expr` (if supplied). Caller writes the SQL.
2. Apply `filter_expr` as a WHERE clause (drop disqualifiers).
3. `DISTINCT ON (col_key) ORDER BY col_key, <order_by clauses>` — keep one row per key, highest-ranked.
4. Write output table.

### `col_<role>` parameter naming follows link/CLAUDE.md convention.

## Generic — examples beyond bcfp PSCIS

- **Field-assessed vs user-added crossings dedup**: candidates from `frs_point_match`; pick by `assessment_date DESC, distance_instream ASC`.
- **Observations vs habitat-confirmation points**: candidates from `frs_point_match`; pick by `score_expr` based on species_code match.
- **Multi-stream-per-PSCIS resolution**: candidates from `frs_point_snap(num_features = 5)`; pick by name + width + distance per bcfp.

## Composition with existing primitives

```r
# 1. Multi-stream candidates per PSCIS
fresh::frs_point_snap(conn, ..., num_features = 5)
# → table_in has multiple rows per PSCIS

# 2. Score + filter + pick best stream per PSCIS
fresh::frs_candidates_pick(
  conn,
  table_in = "<schema>.pscis_stream_candidates",
  table_to = "<schema>.pscis",
  col_key  = "stream_crossing_id",
  score_expr = "
    CASE
      WHEN LOWER(stream_name) = LOWER(gnis_name) THEN 100
      WHEN stream_name IS NULL OR gnis_name IS NULL THEN 0
      ELSE -100
    END",
  filter_expr = "score >= 0",
  order_by = c("score DESC", "distance_to_stream ASC")
)

# 3. Match to modelled crossings (single-stream-per-row input now)
fresh::frs_point_match(conn, ..., col_a_id = "stream_crossing_id", ...)
```

This composition closes the BULK byte-identical gap in fresh#206 (the 5 multi-stream divergences) by moving the scoring decision upstream into a primitive that explicitly owns it.

## Acceptance

- [ ] `frs_candidates_pick` exists, exported from NAMESPACE
- [ ] Validation tier: input arg checks (`expect_error()` for missing/malformed args)
- [ ] SQL composition tier: mocked tests confirm score + filter + DISTINCT ON + ORDER BY all appear
- [ ] Live tier: round-trip test with synthetic candidates table
- [ ] Combined with `frs_point_snap(num_features = N)` + `frs_point_match` reproduces bcfp's PSCIS-to-stream + PSCIS-to-modelled selection — BULK byte-identical (closes the 5-diff gap surfaced in #206)
- [ ] Roxygen + lintr clean

## Out of scope

- Built-in scoring helpers (`type = "name_match"`, `type = "exact_equal"`). Caller passes raw SQL fragments; library of common rule-types can be added later as a separate concern (`frs_score_rules_*` helpers).
- Multi-key dedup (e.g. `DISTINCT ON (a, b)`). Single-key only for v1; extend later if needed.
- Geometry-aware operations. The primitive is purely SQL composition over the candidates table.


## Plan-mode exploration (2026-05-11)

Brief targeted exploration since fresh's patterns were already established in #206 (just shipped as v0.30.0). Verified:

1. **`frs_point_snap(num_features = N)` returns one row per (point, candidate)** — exactly the shape `frs_candidates_pick` consumes. Default path (no blue_line_key/stream_order_min) passes `num_features` to `fwa_indexpoint()`; KNN path passes it to `LIMIT`. Test `test-frs_point_snap.R:198` confirms `nrow(multi) <= num_features`.
2. **Reusable helpers all present** in `R/utils.R`: `.frs_validate_identifier`, `.frs_db_execute`, `.frs_table_columns`, `.frs_sql_num`. Same building blocks as `frs_point_match`.
3. **`frs_point_match` is the structural template** — sprintf SQL composition, DROP+CREATE split (RPostgres can't run multi-statement SQL), DISTINCT ON ordering matches PostgreSQL requirement.

## Naming convention update

`exp_score` / `exp_filter` rather than `score_expr` / `filter_expr`, matching `table_<role>` and `col_<role>` precedent. CLAUDE.md update planned for Phase 4.
