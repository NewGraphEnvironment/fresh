## Outcome

Segmented streams from `frs_network_segment()` and `frs_habitat()` now carry `mad_m3s`, joined from `whse_basemapping.fwa_stream_networks_discharge` on `linear_feature_id` (a 1:1 join). The rules YAML accepts `mad: [min, max]`, which becomes `s.mad_m3s BETWEEN min AND max`. Following the user's decision (the issue's Option B), CSV MAD thresholds are still parsed but never applied or inherited. The choice between channel width and MAD is a per-WSG model choice, and all 187 WSGs in the bundled bcfishpass `example_newgraph` method CSV are `cw`, so applying CSV MAD would have changed every current output. That switch is tracked in #220.

Code-check round 1 found a bug the new column exposed. `frs_habitat()` persisted `to_streams` with a positional `INSERT ... SELECT *` after a partition DELETE. Any `to_streams` table from an older run would therefore fail the insert, and that WSG's rows would already be gone. `.frs_persist_columns()` now adds the missing columns, fails on a type mismatch (round 3 found that gap inside the round-1 fix), and gives a named INSERT list. Three reviewer rounds ran, and the loop ended on an enumeration of coercion-at-trust-boundary cases (see `findings.md`).

## Measurement

Local fwapg, 2026-09-25:

- **Discharge table.** `fwa_stream_networks_discharge` has 2,716,652 rows, and 2,003,189 of them (about 74%) have a non-NULL `mad_m3s`. It covers 150 WSGs, of which only 123 have any MAD. **BULK and LDEN, the issue's MAD-model examples, are absent entirely.** Segments with NULL `mad_m3s` fail a `mad:` rule.
- **ADMS spot-check.** 10,449 of 11,520 segments get a `mad_m3s` value. For CO spawning, the stream/canal rule with cw + gradient thresholds matches 861 segments. Adding `mad: [0.164, 9999]` matches 597, a strict subset: no segment passes the mad rule without also passing the cw rule.
- **Full suite (local fwapg).** 1055 pass, 6 fail, and none of the failures come from this change:
  - 3 live tests hardcode the port-63333 tunnel.
  - 2 need the `bcfishpass` schema.
  - 1 already fails on main: `test-frs_params.R:92` expects 4 CO rear rules, and the bundled YAML has 5.

Closed by: PR for branch `114-phase-2-enrich-streams-with-mad-m3s-and`
