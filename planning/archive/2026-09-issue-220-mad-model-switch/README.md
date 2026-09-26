## Outcome
fresh now honours bcfishpass `parameters_habitat_method.csv`. `frs_habitat_classify()` and `frs_habitat()` take `params_method` (NULL reads the bundled all-`cw` copy). Classify resolves `cw` or `mad` per watershed group in the streams table, defaulting to `cw`, and combines per-model predicates with `CASE` on `watershed_group_code` when groups are mixed. Output SQL is unchanged when every group is `cw`. `frs_habitat_predicates(model = "mad")` swaps the CSV channel-width ranges for `mad_m3s` ranges on both the CSV and rules paths and for lake/wetland rearing.

The plan review and bcfishpass SQL changed three design points:
- Rule-level `channel_width:` (the cw-model river-polygon bypass) is dropped under `mad`.
- Species with no MAD thresholds get no stream habitat on inheriting rules (`mad > NULL` parity).
- SK/KO keep polygon-based lake rearing.

Code-check found an `Inf` SQL literal, then a defect inside that fix (yaml list scalars). It also found an empty-table crash, an information_schema column lookup that misses mixed-case tables, and NA-key matching. Each loop ended on an enumeration.

Known divergences from bcfishpass, accepted: inclusive `BETWEEN` instead of strict `>`, and no `stream_order >= 8` spawn bypass.

## Measurement
Local Docker fwapg, ADMS sub-basin AOI (10,449 of 11,520 ADMS segments have `mad_m3s`), `frs_habitat()` with ADMS set to cw vs mad:

| Species | Measure | cw | mad |
|---|---|---|---|
| BT | spawning | 90 | 0 |
| BT | rearing | 214 | 38 |
| BT | lake_rearing | 4 | 8 |
| CO | spawning | 44 | 39 |
| CO | rearing | 55 | 50 |

Full ADMS with `workers = 2`, mad: CO spawning 470 and BT spawning 0, which confirms the mirai path. The integration test's mad spawning count equals a direct SQL count on `mad_m3s`.

Full test suite: 1122 pass. The 6 failures come from the environment (tunnel / `bcfishpass` schema) or are pre-existing: `test-frs_params.R:92` fails on main too.

Follow-ups:
- link threading `params_method` through `lnk_pipeline_classify()`
- the NULL-watershed-group overwrite DELETE duplicates rows on rerun
- `test-frs_params.R:92` (CO rear rule count 4 vs 5)

Closed by: PR for #220
