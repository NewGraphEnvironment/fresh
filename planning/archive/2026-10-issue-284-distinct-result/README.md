# fresh#284: `frs_network_features(result = "distinct")`

**Outcome:** a third result mode returns each segment's feature IDs once each, sorted by the ID, from the same `walk_from` join as `"ids"` and `"exists"`. Built for link#401, whose access walk asks which fish species are recorded upstream of each segment over every watershed group's records. Small change, so no PWF; this directory holds the review record.

## Measurement

Over every group's records, fresh's own `"distinct"` call costs less than the `"ids"` walk link made over the group's own records (m1, fresh at aabba77, each group's segments copied from `fresh_default` to a temp table, twice each at a load of about 2.5): LFRA 65 → 37–39 s (3.18 M elements → 35,987 rows), BULK 21 → 8 s, SETN 47 → 44–46 s. One existence walk per species instead cost 3 to 7 times the `"ids"` walk (SETN 320 s), which is why the mode exists.

## Evidence

link `data-raw/logs/obs_province_401/` (`walk_time.csv`, `walk_distinct.csv`, `walk_fresh_distinct.csv` and the scripts beside them).

## Review

`/code-check branch`, three rounds (`review-fresh284-round*.md`): all Clean. Round 1's note (the live parity test compared IDs through `as.character()` of a double) was fixed in b3557d0, round 2's (a roxygen sentence named the wrong condition for the saving) in 1b2d4bc. Round 3 listed the diff's ten claims about the result and ran each. The loop ended on a clean round 3 with no defect found inside a fix.
