# Findings — drop format param

## Why drop, not extend

`format = c("wide", "long")` was scoped for two source-table shapes:

1. **wide (per-species suffix):** `spawning_sk`, `rearing_sk`, ... — one row per segment, all species' all habitats in one row. Originally for direct reads of `bcfishpass.streams_habitat_known`. **Zero current production consumers.**
2. **long:** `species_code` + `habitat_type` + `habitat_ind` text rows. One row per (segment × species × habitat_type). Was link's read of pre-2026-04-26 bcfishpass `user_habitat_classification.csv`. **Bcfishpass moved away from this shape.**

Bcfishpass's authoritative CSV (post-2026-04-26) is a third shape: row-per-(segment × species) with per-habitat indicator columns (`spawning`, `rearing`). PR #176 first tried to bolt this on as `species_col` parameter inside `format = "wide"`. That compounded the API.

YAGNI says: ship the one shape that has a real consumer. Add format back when a real second consumer with a different shape appears.

## What stays parameterized

Column names remain caller-customizable:

- `species_col` — name of the column in source carrying species (default `"species_code"`)
- `by` — join keys (default `c("blue_line_key", "downstream_route_measure")`)
- `habitat_types` — habitat columns to overlay (default the four standard ones)

Indicator coercion is universal: `lower(trim(<col>::text)) IN ('true', 't', '1')` matches `1`, `'true'`, `'t'`, boolean TRUE; everything else (NULL, `0`, `'false'`, `'f'`) falsy.

Bridge mode (3-way join via segments table) is orthogonal to source shape and stays.

## Non-canonical sources (Option B)

A consumer with a non-canonical source transforms first — SQL view, R pivot, or (forthcoming) link's `lnk_ingest_bcfishpass()`. fresh stays a thin SQL adapter for one shape; shape-knowledge lives where it belongs (with the consumer).

That keeps fresh's API narrow and lets each consumer own its shape adapter. The pre-2026-04-26 bcfishpass long format is recoverable via a 5-line SQL view (the same one I drafted earlier in `lnk_pipeline_classify.R` and reverted). Wide-suffix similarly.

## Test fixture audit

Existing `test-frs_habitat_overlay.R` (~660 lines, 67 tests) breaks into:

- **Argument validation** (lines 32-65, 149-173, 225-235): mostly retained, drop checks for dropped params (`format`, `long_value_col`)
- **Empty target table** (69-87): retained; canonical shape
- **Missing source column** (91-113): adapt — `mk_dbq` used wide-suffix; rewrite for canonical shape (missing habitat column instead of missing per-species-suffix)
- **SQL shape** (117-147): rewrite for canonical shape — verify single-dispatch SQL emits the right WHERE clause with `species_col` + indicator predicate
- **Custom `by`** (177-196): retained; bridge orthogonal
- **NULL species** (200-223): retained; species discovery from target table
- **Wide integration** (237-379): adapt to canonical shape
- **Long-format unit + integration** (382-528): drop entirely
- **Bridge** (532-660): retained for the canonical shape

Net: ~150 lines of test code removed, ~60 lines added/adjusted.

## Migration mapping for link

Link's `lnk_pipeline_classify.R` currently calls:

```r
fresh::frs_habitat_overlay(conn,
  from   = paste0(schema, ".user_habitat_classification"),
  to     = "fresh.streams_habitat",
  bridge = "fresh.streams",
  species = species,
  format = "long",                # drop
  long_value_col = "habitat_ind", # drop
  verbose = FALSE)
```

Becomes (after fresh 0.22.0):

```r
fresh::frs_habitat_overlay(conn,
  from   = paste0(schema, ".user_habitat_classification"),
  to     = "fresh.streams_habitat",
  bridge = "fresh.streams",
  species = species,
  species_col = "species_code",
  habitat_types = c("spawning", "rearing"),
  verbose = FALSE)
```

Source table shape (already loaded by `lnk_pipeline_prepare`) is the new bcfishpass shape since the daily auto-sync. Caller-side change is the function args — three lines.

## Why species_col defaults to "species_code"

Bcfishpass uses `species_code` as the column name. So does fresh's own `streams_habitat`. So does link's `parameters_fresh.csv`. Convention across the ecosystem. Default-args-match-convention is cleaner than "user must always specify".

## Version bump rationale

0.21.0 → 0.22.0. Minor (not patch) because of breaking signature change. Pre-1.0, single consumer (link), coordinated release window — documented breaking changes are acceptable per the convention reflected in 0.21.0's NEWS ("Pre-1.0 cleanup driven by review of v0.20.0; no deprecation alias").

No deprecation alias for `format` either. The two callers (link's broken `format = "long"` call site; fresh's own tests) both update in this same coordinated work.
