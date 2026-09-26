# Findings — Per-WSG cw/mad habitat model switch from parameters_habitat_method.csv (#220)

## Issue context

## Problem

#114 added a `mad: [min, max]` rule predicate and joined `mad_m3s` onto segmented streams. MAD only applies where a rules YAML asks for it explicitly: CSV MAD thresholds (`spawn_mad_min`, `rear_mad_min/max`, parsed by `frs_params()` into `ranges$*$mad_m3s`) are never applied or inherited.

bcfishpass uses channel width **or** MAD, chosen per watershed group through `parameters_habitat_method.csv` (`model = cw | mad`). fresh bundles that CSV (`inst/extdata/parameters_habitat_method.csv`) but never reads it. The bundled `example_newgraph` copy sets all 187 WSGs to `cw`, so nothing changes today. A config that sets `mad` for some WSGs would not be honoured.

## Proposed Solution

- Read the per-WSG `model` in `frs_habitat()` and thread it through to the species params.
- When `model == "mad"`, the CSV-ranges path and the rules-path CSV inheritance use `mad_m3s` ranges in place of `channel_width`.
- Default to `cw` when a WSG is missing from the CSV.

## Data note

In the local fwapg build, `whse_basemapping.fwa_stream_networks_discharge` covers 150 WSGs, and only 123 of those have any non-NULL `mad_m3s`. BULK and LDEN, the MAD-model examples in #114, are absent entirely. Check coverage on the shared DB before relying on MAD for a WSG. Segments with NULL `mad_m3s` fail a `mad` rule.

## Relates to

- #114
- #113

## Design (plan-mode exploration, 2026-09-25)

**Where the switch lives:** `frs_habitat_classify()` (not only `frs_habitat()`). The streams table can span several WSGs (partition mode, custom AOI, link calling classify directly), and every row carries `watershed_group_code`. So classify resolves a model per WSG present in the table and builds predicates to match:
- all `cw` → current predicates, SQL unchanged
- all `mad` → MAD predicates
- mixed → per predicate `CASE WHEN s.watershed_group_code IN (<mad wsgs>) THEN (<mad pred>) ELSE (<cw pred>) END`

**New param:** `params_method` (data frame `watershed_group_code`, `model`) on `frs_habitat_classify()` and `frs_habitat()`, named after `params_fresh`. `NULL` → read the bundled CSV. WSGs missing from it → `cw`. Invalid `model` values → error.

**`frs_habitat_predicates(sp_params, model = "cw")`**: `model = "mad"` swaps the size dimension from `channel_width` to `mad_m3s` everywhere the CSV ranges feed in:
- CSV-ranges path: spawn/rear use `ranges$*$mad_m3s`
- Rules path: `csv_thresholds` carries `mad_m3s` instead of `channel_width`
- Lake/wetland rearing: gated on and filtered by the rear MAD window instead of the rear CW window

**`.frs_rule_to_sql()` inheritance** (`R/utils.R:~297-320`): add `csv_thresholds$mad_m3s` inheritance. A rule's explicit `channel_width:` or `mad:` counts as its size threshold, so either one stops the inherited MAD being added. That way a size limit is never applied twice. Explicit `mad:` rules keep working as before. The lake/wetland (`L`/`W`) auto-skip covers MAD too.

**Species without MAD thresholds in a `mad` WSG** (BT, GR, KO, RB have NA): these match **bcfishpass**, where `mad > NULL` is never true, so the size predicate is `FALSE` (no spawning/rearing). This is on purpose and different from the cw path, where a NULL range means no constraint. It is documented, and I'll flag it in the PR.

**Guard:** if any WSG resolves to `mad` and the streams table has no `mad_m3s` column, stop with a clear error. The data note in #220 about NULL `mad_m3s` coverage goes in the docs. NULL values fail the predicate, same as bcfishpass.

**Out of scope (to note in findings):**
- bcfishpass's `stream_order >= 8` spawn bypass under `mad` (CO/CH/SK)
- bcfishpass uses strict `>` on the minimum; fresh keeps `BETWEEN`, same as cw
- `spawn_connected$channel_width_min` and `channel_width_min_bypass` stay cw-only
- the orphaned `frs_habitat_species()` (`R/frs_habitat.R:1061`, no callers)
- link threading `params_method` through `lnk_pipeline_*` (follow-up comms/issue)


## bcfishpass reference (model/02_habitat_linear/sql/load_habitat_linear_*.sql)

- `wsg.model = 'mad'` branch: `mad.mad_m3s > t.spawn_mad_min AND mad.mad_m3s <= t.spawn_mad_max` (BT, SK stream spawning); CO/CH/SK spawn use `(mad > min OR s.stream_order >= 8)`.
- Rear: `mad > rear_mad_min AND mad <= rear_mad_max`; CO adds `OR edge_type IN (1050, 1150)`.
- NA MAD thresholds (BT etc.) → comparisons with NULL → never true → no size-qualified habitat under `mad`.

## Plan-agent review (2026-09-25) — changes vs approved plan

- **Blocker, fixed in design:** gating lake/wetland rearing on the rear MAD window would make SK/KO lake rearing (NA `rear_mad`) disappear in mad WSGs. bcfishpass SK rearing is lake-area based whatever the model (`load_habitat_linear_sk.sql`). Under mad: use the rear MAD window if present, else polygon membership only. The cw path is unchanged.
- **Blocker, handled:** a NULL `csv_thresholds$mad_m3s` means "inherit nothing" and would give NA-MAD species MORE habitat. Fixed with a `c(NA, NA)` sentinel → `FALSE` part for inheriting rules only.
- **Gap, design changed:** the approved plan said an explicit rule `channel_width:` blocks inherited MAD. But the bundled YAML has `waterbody_type: R` + `channel_width: [0, 9999]` for every species, which is the cw-model river bypass (bcfishpass cw branch: `cw > min OR r.waterbody_key IS NOT NULL`). bcfishpass's mad branch has no river bypass. Under mad, rule-level `channel_width` is dropped and MAD is inherited unless the rule has an explicit `mad:`.
- `frs_habitat_partition()` / `frs_habitat_species()` are exported and cw-only via `frs_classify()`, not orphaned. Documented as not model-aware, not changed.
- link `lnk_pipeline_classify.R:95` calls classify by name. `params_method` goes after `params_fresh` with a NULL default, so nothing breaks.
- Pre-existing failure on main: `test-frs_params.R:92` (CO spawn rule count vs `inst/testdata/test_params.csv`). It fails with this branch's changes stashed too, so it's unrelated.

## Code-check (Phase 2)

- Round 1: `frs_params()` fills a blank `*_max` with `Inf`, and `.frs_sql_num(Inf)` rendered a bare `Inf`, which Postgres parses as a column. This is the first diff to put CSV MAD ranges into SQL. Fixed: `.frs_sql_num()` now emits `'Infinity'::double precision`. It was latent for channel_width too.
- Accepted divergence: bcfishpass mad spawning for CH/CM/CO/PK/SK/ST is `mad > min OR stream_order >= 8`. fresh does not implement the order-8 bypass, so large mainstems with NULL or low MAD are not spawning in fresh. Recorded in NEWS.
- Round 2: clean. All 30 `.frs_sql_num()` call sites put the value straight into SQL.
- Round 3: found a defect inside the round 1 fix. `is.infinite()` errors on a length-1 list, which is what yaml returns for mixed int/float sequences (`[0, 0.05]`); before, sprintf coerced the list silently. Fixed with `unlist()` + a `length == 1L` guard. The round ended on an enumeration: round 3 listed every site where params values reach SQL, and a test pins every input shape of `.frs_sql_num()` (numeric, integer, list, list(Inf), vector, NA). Bare `NA`/`NaN` on the cw path is pre-existing and out of scope.

## Verification (Phase 3, local Docker fwapg)

- `frs_habitat()` on the ADMS sub-basin AOI, sequential, with `params_method` ADMS=cw vs ADMS=mad:
  - BT spawning 90 → 0 (no MAD thresholds), rearing 214 → 38 (non-inheriting rules only), lake_rearing 4 → 8 (polygon-only gate, no rear MAD window)
  - CO spawning 44 → 39, rearing 55 → 50
  - SK 0 / 0 both
- Full ADMS `wsg`, `workers = 2` (mirai path), mad: CO spawning 470, BT spawning 0, so `params_method` reaches the workers. Took 34 s.
- Integration test: the mad-model spawning count equals a direct SQL count on `mad_m3s` (gradient min comes from `parameters_fresh.csv`, 0.0025 for CO).

## Code-check (Phase 3)

- Round 1, bug: with an empty streams table no model resolved, so `preds` was NULL and the INSERT `sprintf()` returned `character(0)`, which `dbExecute` rejects. `.run_job` reaches this when `n_seg == 0`. Fixed: the cw predicates are always built.
- Round 1, fragile: the `mad_m3s` guard used `.frs_table_columns()`, whose information_schema lookup on the literal name misses mixed-case AOI labels (`working.streams_<Label>`), temp tables and non-public search_path schemas. The result was a false "no mad_m3s column" stop. Fixed: columns now come from `SELECT * FROM <table> LIMIT 0`.
- Round 2: `.frs_habitat_models()` matched an NA `watershed_group_code` in `params_method` to NULL-group rows (mad under all-mad, cw under mixed). Fixed: `match(..., incomparables = NA)`. This was in the original helper, not inside a round 1 fix.
- Round 3: clean, and it ended on an enumeration. The shared mechanism: the watershed-group set R reads via `SELECT DISTINCT` must match the rows the CASE/INSERT touches. Models resolution, the `IN (...)` list, the all-cw and all-mad short-circuits, the guard and the per-WSG DELETE all checked consistent.
- Out of scope, pre-existing (`R/frs_habitat_classify.R` overwrite DELETE): `.frs_quote_string(NA)` gives `'NA'`, so rows with a NULL `watershed_group_code` are never deleted and a rerun duplicates them. Only custom networks are affected. Candidate follow-up issue.
