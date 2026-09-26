## Outcome

The test `frs_params bundled rules has expected species blocks` had failed on main since v0.34.0. It expected 4 CO rear rules, and the link-generated `parameters_habitat_rules.yaml` now has 5 (a lake rule with `lake_ha_min` was added). The test now checks what the rules contain rather than how many there are or where they sit. It finds the `thresholds: false` carve-out by predicate and checks its edge types (1050, 1150). It checks that the rear rules cover the R, W and L waterbody types, with the wetland and lake area minimums present. It checks the spawn rules the same way. Future link resyncs that append rules will no longer break it. Learned: an index-based test on an externally generated bundle breaks every time that bundle is resynced.

## Measurement

- `frs_params` tests: FAIL 0 | SKIP 2 | PASS 153 (was FAIL 1 on main).
- Full suite on m4 (local fwapg): FAIL 3 | SKIP 2 | PASS 1145. All 3 errors come from `test-frs_network_features-live.R`, which is gated only on `PG_PASS_SHARE`, so it errors instead of skipping when the tunnel on port 63333 is down. That is unrelated to #223; see findings.md.
- Sanity check: flipping the carve-out to `thresholds: true` leaves 0 matching rules, so the assertion fails as it should.

Closed by: commit dbec947 / PR (see branch 223-test-frs-params-r-92-expects-4-co-rear-ru)
