# Findings — Lake and wetland rearing buckets: size by polygon area, require connected spawning (#240)

## Issue context

**If done:** `lake_rearing` and `wetland_rearing` mean "an accessible lake or wetland big enough for the species, connected to its spawning". Lake and wetland hectares then measure habitat the species can use. **If never:** they count every accessible polygon above an area floor whose centreline happens to pass a stream-size test. That includes polygons with no connection to the species' spawning, and the gate is the inflow's size, not the lake's.

## Problem

`build_wb_pred()` (`R/frs_habitat_predicates.R:194`, fresh@v0.36.3 `30e8733`) gates the bucket columns twice:
1. **Polygon area** (`lake_ha_min` / `wetland_ha_min`). This is the right size test for a lake or wetland.
2. **The stream size range of the line through the polygon**:
   - under `cw`, modelled channel width;
   - under `mad`, the line's `mad_m3s`. This came in with the MAD predicates (`33601f9`, #220).
   - under `cw`, a species with no width range gets `FALSE` outright.

   This test measures the flow passing through the polygon, not the polygon. A 50 ha lake on a small creek fails it, and the same lake on a river passes. On NATR under `mad` with a 0.021 m³/s rear minimum, BT lake bucket length fell 521 → 304 km and wetland 1,287 → 710 km (NewGraphEnvironment/link#307, `data-raw/logs/habitat_thresholds_307/`).

**Connectivity never reaches the buckets.** `frs_cluster()` clears only `label_cluster = "rearing"` (`R/frs_cluster.R:109`). So a polygon keeps `lake_rearing = TRUE` with no same-species spawning anywhere near it. Measured on link's persisted `fresh_default` (52 WSGs, BT):

| column | rows | not `rearing` | km |
|---|---|---|---|
| `lake_rearing` | 16,652 | 16,651 | 7,223 |
| `wetland_rearing` | 40,785 | 2,133 | — |

(The lake gap is mostly a link rule problem: its L rule admits only edges 1000/1100, and lake lines are 1200/1450/1475. That is filed in link. Either way the bucket is uncoupled from connectivity.)

**What bcfishpass does** (`smnorris/bcfishpass@f8db4b9`, `model/02_habitat_linear/sql/`):
- **SK lake rearing** is `lk.area_ha >= rear_lake_ha_min` (lakes and reservoirs), with no stream-size test. Spawning is tied to the lake: within 3 km downstream, or upstream.
- **CO wetland rearing** (edges 1050/1150) skips the size test ("any wetlands are potential rearing") and must cluster with CO spawning.
- No bcfishpass species sizes a lake or wetland by the line through it.

## Proposal

1. **Area only.** Lake and wetland bucket predicates test polygon membership and `*_ha_min` (plus access), with no channel width or discharge test, under either model. The `cw` "no width range → `FALSE`" branch goes too.
2. **Connected to spawning, at a distance the rules state.** An L/W rear rule may carry the keys spawn rules already use (`R/frs_params.R:140`, `R/frs_habitat.R:1198-1215`):
   ```yaml
   - waterbody_type: L
     lake_ha_min: 10
     requires_connected: spawning
     connected_distance_max: <m>
   ```
   After connectivity, a polygon keeps `lake_rearing` / `wetland_rearing` only if a line of it is within `connected_distance_max` of same-species spawning, upstream or downstream. The polygon is the unit: one connected line keeps the whole polygon. A rule without `requires_connected` keeps today's behaviour, so existing bundles do not move until they opt in.
3. **Tests:**
   - A lake on a sub-threshold inflow keeps its bucket under both models.
   - A disconnected lake loses it.
   - A lake beyond `connected_distance_max` loses it.
   - A rule with no `requires_connected` is unchanged.

The distances per species, and which species opt in, are link's to set: NewGraphEnvironment/link#310.

## Not in scope

- The main `rear` predicate and the `rearing` flag.
- Converting lake habitat to km. Lakes are habitat in hectares.

Relates to #220, #237.


## Plan-mode exploration (2026-10-06, fresh@30e8733)

- Classify wraps the bucket predicates in `CASE WHEN a.accessible AND (...)` (`R/frs_habitat_classify.R:312`), so access gating survives dropping the size clause.
- `requires_connected` / `connected_distance_max` are already valid rule keys (`R/frs_params.R:140`, validated `:313-335`). No shipped rules file (fresh or any link bundle) puts them on a rear rule — spawn blocks only (SK/KO). On a rear rule they are currently ignored silently.
- `.frs_run_connectivity()` (`R/frs_habitat.R:1171`) is the single post-classify hook: both `frs_habitat()` paths (`:468`, `:631`) and link's connect phase call it.
- `.frs_trace_downstream()` is the reusable distance primitive (FWA_Downstream predicate join on the broken streams table, cumulative distance cap, gradient stop; mainstem only). It returns `linear_feature_id` without the origin.
- Predicate tests are string-level; connectivity tests are SQL-capture mocks (`test-frs_habitat.R:440+`) and cannot prove behaviour, so Phase 3 needs a synthetic DB fixture.

### Noted, not in scope

- `R/frs_habitat.R:1133` (legacy non-rules path) still sizes `<sp>_lake_rearing` by channel width.
- The L bucket joins `fwa_lakes_poly` only; `.frs_waterbody_tables("L")` (used by the main rear rules and SK connectivity) also includes `fwa_manmade_waterbodies_poly`. bcfishpass SK lake rearing includes reservoirs.

## Errors Encountered

| Error | Resolution |
|-------|------------|
| `round(double precision, integer) does not exist` in the live-check SQL | Cast to `numeric` before `round(x, 1)` |
| First "no UPDATE" mutation stayed green | The mutation (`)); if (FALSE)`) swallowed the next line, not the UPDATE: the probe was broken, not the guard. Redone as `SET col = TRUE`, which went red |
| First "no distance cap" mutation went red for the wrong reason | Scaling `distance_max` also scaled the ST_DWithin prefilter. Round 1 of P3's review found the cap itself unpinned; fixed with a folded-geometry fixture |
| Live check ~50-70 s per species on NATR | Temp tables are never auto-analyzed, and working tables have no GiST on geom. Both are needed; with them, 2.5 s |
| Branch R CMD check ran against link | `cd` sat inside a backgrounded `( … ) &` list, so the second subshell ran in the session cwd. Re-run from fresh |
| `ls` output carried ANSI colour codes into a path | `ls` is aliased with `--color`; use `find` |

## Plan review (Plan agent, 2026-10-06) — what was taken

- Habitat joins must match `watershed_group_code`: `frs_habitat(to_habitat =)` writes every WSG job into one table and split-segment ids collide (on NATR the next 5,000 ids hold 1,451 MIDR/TAKL segments). Done, with a test.
- One outlet per `(waterbody_key, blue_line_key)`: done, with a test.
- `requires_connected` on a second L rule silently unread: now a load error.
- Pre-existing, not fixed here: `frs_cluster()`, `.frs_distance_filter()` and `.frs_connected_waterbody()` join a shared habitat table on `id_segment` alone (the last one's subtractive UPDATE has no group scope at all). link is unaffected (per-WSG schema). Drafted as a separate issue, awaiting approval.
- Cross-repo: link's `lnk_rules_build()` `add_rc()` stamps `rear_requires_connected` on every rear rule, which fresh now rejects; inert today (all NA); recorded in link#310.
