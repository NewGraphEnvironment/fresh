# Findings — #263 with #262

## #262 body

**If done:** a `near_river` rule can define "a river nearby" by modelled channel width or stream order, not only discharge, so groups with no usable discharge (and `cw` groups generally) can use it. **If never:** `near_river` works only where the bundle's discharge covers the main stems, and a `cw` group sizes habitat by width but rivers by discharge.

## Problem

`near_river: {discharge_min, distance_max}` (#259, PR #261) finds the nearest river by `mad_m3s` alone. Discharge is missing where it matters most in some sources: fwapg's table has no value on any of BULK's 1,118 river-polygon (1250) rows, so under a bundle on fwapg discharge the Bulkley is never found. Width and order are complete there.

Coverage on BULK main-flow rows (raw FWA joined to `fwa_stream_networks_channel_width`, 2026-10-21):

| edge type | rows | with stream order | with channel width |
|---|---|---|---|
| 1000 single-line stream | 21,609 | 21,609 | 10,661 |
| 1050 through wetland | 2,745 | 2,745 | 1,719 |
| 1200 through lake | 2,935 | 2,935 | 1,145 |
| 1250 river polygon | 1,118 | 1,118 | 1,118 |

Missing widths are mostly first-order streams, which fwapg never models. Those segments are still measured as origins; only targets need a value.

## Proposed

One size key per `near_river` mapping, named like the thresholds, exactly one required:

```yaml
near_river:
  channel_width_min: 20   # or discharge_min (m3/s) or stream_order_min
  distance_max: 1000
```

The walk's two size tests take the named column: a target is a row at or above the threshold, an origin is a row below it or with no value. The bank rule, jumps, the prefilter cut and one walk per pair are unchanged. `<to>_near_river` records the measure and threshold of each walk, and the predicate matches both.

Points to settle:

- **Lakes.** Under discharge a lake's flow line can be a target; most lake lines carry no width (1,145 of 2,935 on BULK), so under width they rarely count, and under order they do. Which a "river nearby" should include is a biology call.
- **Stream order is topological**: an order-5 stream in a dry basin can carry less water than an order-4 one in a wet basin. It needs no discharge source.
- **Width is modelled** (fwapg's regression), the same width the `cw` model sizes habitat with. An option is to let the key follow the group's model (width under `cw`, discharge under `mad`), so each group has one notion of "big".
- **The live check** (`data-raw/near_river_check.R`) compares against an independent walk that reads discharge only; width and order need a reference too.

Consumer: NewGraphEnvironment/link#364.

## #263 body

**If done:** a species' near-river rule (a river of at least some size within D m downstream) lives in `parameters_habitat_thresholds.csv` beside its gradient, width and MAD ranges, per stage, with the measure of "a river" chosen there too (discharge, channel width or stream order, #262), and applies to every rule that inherits thresholds; a rule carries `near_river: false` to opt out, or its own mapping to override. A bundle that `extends:` another can carry its own values, and a threshold ladder can score the measure, Q and D on held-out groups the way MAD ranges are scored. **If never:** the condition exists only as a rule key (0.41.0, #259), so every change to it is a rules rebuild, a thin bundle cannot differ from its parent, and link's variants harness, which varies thresholds cells on one shared segmentation, cannot test it (NewGraphEnvironment/link#364).

Builds on #262: this issue is where its size keys are *inherited from*; #262 is where the walk learns to measure by width or order. The two can land as one PR or two; link pins whichever release carries both.

## What we want

Thresholds columns, read by `frs_params()` like the others (NA = absent), for `spawn` and `rear`:

| column | type | meaning |
|---|---|---|
| `<stage>_river_measure` | text | `discharge`, `channel_width`, `stream_order`, or `model` (width under `cw`, discharge under `mad`, as the size test does). Absent means `model`. |
| `<stage>_river_discharge_min` | m³/s | the river's threshold under that measure |
| `<stage>_river_channel_width_min` | m | |
| `<stage>_river_stream_order_min` | order | |
| `<stage>_river_distance_max` | m | reach, along the network, downstream |

A stage has a pair when `distance_max` and the `_min` of its resolved measure are both set; both finite and above zero. `distance_max` with no usable `_min`, or a `_min` with no `distance_max`, stops at `frs_params()` naming the species and stage. The three `_min` columns may coexist (a ladder compares measures on one CSV); the measure column picks. `<stage>_river_measure` joins `char_fields` so it is not `as.numeric`'d.

- **Where it lives:** `params[[sp]]$near_river$<stage>` — a sibling of `ranges`, not inside it. `ranges` is typed as `list(column = c(min, max))` by `.frs_classify_ranges()` (`R/frs_classify.R:214-219`) and `frs_habitat_species()` subsets it (`R/frs_habitat.R:1154-1159`); a stage whose only entry were the pair would turn `NULL` into a list and stop `frs_classify()`.
- **Resolution, one function, two callers.** `.frs_rule_near_river(rule, csv_near_river)`: an explicit mapping wins; `false` means none; otherwise the stage's inherited pair **when the rule inherits thresholds and has a size part** (`thresholds` absent or true, not `waterbody_type: L/W`, and a `channel_width` / `mad` test, explicit or inherited, including the `FALSE` marker of a `mad` species with no range). A rule with no size test keeps 0.41.0's "EXISTS alone" only when it asks for it explicitly: under `cw` a rule whose stage has no width range has no size test today, and an inherited pair would *tighten* it to "near a river only". `.frs_rule_to_sql()` and `.frs_near_river_specs()` both call the resolver, so the walk and the predicate cannot disagree; today the specs collector reads rule keys only (`R/frs_habitat_predicates.R:284-306`), which with inheritance would leave a pair with no walk rows: an EXISTS that never matches, no error, no relaxation.
- **The compiled form is unchanged:** `(<size parts> OR EXISTS …)`; the EXISTS matches the walk's `(measure, threshold, distance_max)` per #262.
- `frs_habitat_predicates()` builds `csv_thresholds_<stage>` itself (`:184-187`, `:209-211`); the pair goes in there under both models (it is not a size column, so it must not ride the `mad`-only path). `model_rules()` drops only `channel_width` under `mad` (`:173-179`); a mapping or `false` passes through.
- **`waterbody_type: R` rules inherit** (`inherit_thresholds` stays TRUE for `R`, `R/utils.R:267-270`); with the bundled `channel_width: [0, 9999]` that is `(cw BETWEEN 0 AND 9999 OR EXISTS)`, which admits a NULL-width river line near a bigger river. Stated and pinned, not hidden; a consumer that means "the river polygon is the river" stamps `near_river: false` on it (link does).
- **`near_river: false`:** valid on any rule that could inherit; refused on `waterbody_type: L/W` like the mapping (nothing to opt out of); a no-op on a `thresholds: false` rule. The loader's coercion (`R/frs_params.R:170-174`, `lapply(rule$near_river[c("discharge_min","distance_max")], as.numeric)`) must be guarded by `is.list()`: today `false` becomes an unnamed `list(NA, NA)` that compiles to `n.discharge_min = NA` and reaches the specs. `.frs_validate_near_river()` tests `isFALSE()` before `is.list()` and refuses `true` with its own message; the `scalar` test case keeps matching "named mapping".
- The bundled `inst/extdata/parameters_habitat_thresholds.csv` gains the columns as NA. With them absent or NA every rule compiles byte-identically to 0.41.0: `.frs_build_ranges()` is untouched (NULL stays NULL), and the resolver takes the `is.null` branch.
- `frs_params()` has no column allow-list (`:88-96`), so a consumer can add the columns before pinning this release (inert) — and a misspelt one is inert too. Warn on an unknown `*_river_*` column.
- `frs_habitat_classify()`: filter `species` by `params_fresh` before `.frs_near_river_specs()` (`:180` runs before `:220-233` drops them, so a pair for a species with no `params_fresh` row is walked for nothing); the "table has no `<measure column>`" stop now fires on every group once any classified species has a pair, `cw` included — say so in its roxygen (`:20-28`).
- Rules-path only: species with no rules block compile from `ranges` directly (`:191-203`, `:222-236`) and get no pair; one sentence in the roxygen.

## Tests to pin

- Inheritance under `cw` and `mad`, by each measure; `model` resolving to width under `cw` and discharge under `mad`; an explicit mapping over an inherited pair; `false` over an inherited pair; `false` on a `thresholds: false` rule is a no-op; `false` or a mapping on L/W refused; `true` refused.
- Absent or NA columns → byte-identical SQL for every bundled rule (`test-frs_habitat_classify.R:389-433` reads the bundled CSV).
- The specs equal the compiler's effective pairs: one species inheriting, one overriding, one opting out on every rule → two distinct walks, not three; `params` with `rules` only and no `near_river` slot still gives the empty frame (`test-near_river_rules.R:255-275`).
- A rule with no size part inherits no pair (the `cw` tightening case); a `mad` species with no range still reads `(FALSE OR EXISTS)` (`:123-131`).
- The `R` rule's form under `cw` and under `mad`.
- Half pairs stop, including `Inf` (`as.numeric("Inf")` passes `!is.na`); `distance_max` without a resolvable `_min` stops; mirror `frs_near_river()`'s `ok_num` (`R/frs_near_river.R:107-120`).
- `near_river: false` round-trips through `yaml::read_yaml()` as logical; an empty key still errors.

Not a test: `channel_width_min_bypass` is a loader passthrough (`R/frs_params.R:419-422`) that link applies after classify through `frs_order_child()`; fresh compiles no OR for it.

## Docs

`R/frs_params.R:13-25`, `R/frs_habitat_predicates.R:38-70, 89-94`, `R/utils.R:225-241`, `R/frs_habitat_classify.R:20-28`, `R/frs_habitat.R:101-104`, the 0.41.0 NEWS entry's "a rule can carry" wording, `man/` regenerated.

## Acceptance

- `devtools::test()` green with the cases above; NEWS; docs name the columns and the sibling slot.
- A release tag; link pins it in NewGraphEnvironment/link#364 Phase 1.

## Phase 3 — what the live check can and cannot show (2026-10-21)

- The #259 independent reference (`pg_temp.ch_dist_profile`) lives outside this repo and reads wet's discharge on raw FWA. It cannot score a width or order walk, so #262's "the live check gains width and order references" is narrowed to an equivalence check (`data-raw/near_river_measure_check.R`). Each walk by width or order must equal, row for row, the discharge walk on a copy whose `mad_m3s` holds that measure. The SQL is otherwise the one #259 validated, so this tests exactly what #262 changed: the column threading.
- A `CREATE TABLE AS` copy has no network indexes. On it, the walk's `FWA_Downstream()` join ran over 10 minutes before it was cancelled; the direct walks took seconds. The copy is now `LIKE ... INCLUDING ALL`.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| Equivalence walk on a `CREATE TABLE AS` copy ran >10 min | Copy with `LIKE ... INCLUDING ALL` so the network indexes exist |

## Code-check enumeration (round 2, 2026-10-21)

Mechanism found in rounds 1 and 2: classify writes (`CREATE TABLE <to>`, the per-group DELETE, the access tables) before it calls `frs_near_river()`, so any stop inside the walk's checks ran after habitat rows were deleted. Candidate set, enumerated from `R/frs_habitat_classify.R` (`data-raw`-free script over the function body, first write at the `CREATE TABLE IF NOT EXISTS %s (` line): after the first write the near-river path reaches only `frs_near_river()` and `frs_habitat_predicates()`.
- `frs_near_river()`'s body now holds no check of its own: its only call before its first write is `.frs_near_river_check()`, which carries all 8 checks (two identifiers, threshold, distance_max, measure, distinct pairs, columns, table shape). Classify runs the same helper with the same arguments before its first write.
- `frs_habitat_predicates()` can stop on a near-river pair only when `near_river_table` is NULL, which needs a predicate to read a pair the specs did not collect. The specs and the predicates use the same params, the same species filter (`sp_classify` / `species_params`), the same models (`pred_models`) and the same resolver, so that cannot happen.
- The remaining post-write stops (`.frs_access_label_filter()`, `.frs_access_with_overrides()`, rule-shape stops validated at load) predate this branch and do not touch near_river.

## Code-check round 3 and the terminal fix (2026-10-21)

Round 3 named the mechanism: each guard was a hand-written copy of what the walk accepts, run before classify's DELETE and INSERTs, which no transaction holds. The walk's SQL enforces more than any copy can list (column types, `FWA_Downstream()`, the polygon tables), so a list-based enumeration of R `stop()` calls could not close it. Round 3's instance was a `text` size column, as `frs_col_join()` types one.
- **Fix that closes the class:** classify now runs `frs_near_river()` before it creates or deletes from `to`. The walk reads only `table` and writes only `<to>_near_river`, so any failure inside it, at R or SQL level, leaves the group's habitat rows in place. A test mocks the walk's SQL into an error and asserts the habitat row survives. With the old ordering restored in a scratch copy, that test fails.
- **Enumeration after the first write to `to`:** the only near-river code left is `frs_habitat_predicates()`, which is pure R. Its one near-river stop (`near_river_table` NULL) needs a predicate reading a pair the specs did not collect, and the shared resolver, params, species filter and models rule that out.
- Kept as well: `.frs_near_river_check()` now also refuses a non-numeric size column, so the error names the cast.

