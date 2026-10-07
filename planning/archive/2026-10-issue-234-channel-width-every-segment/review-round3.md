# Code check, round 3: frs_channel_width() (#234, phase 1)

Scope: `R/frs_channel_width.R` and `tests/testthat/test-frs_channel_width.R`. Read against the checklist's R section and its general mechanisms section, and against fwapg `channel_width_modelled.sql` / `channel_width.sql` and flooded `fl_flood_surface.R`. Every number below was re-measured on local fwapg (2026-10-07) unless marked "source".

## Mechanism

**Something that agrees on one sample gets written as a general law.** It shows up in two forms:

1. **Population.** A property measured on one fixture (Bulkley, the Byman-Ailport AOI, one worked point) is stated with no scope. R1's "hall2007 < poisson2021" and R2's "below ~30 ha" are this form.
2. **Definition.** Two predicates happen to agree on the sample and get written as if they were the same thing. Example: "non-positive input" vs "non-positive base". They coincide only when the offset is 0, which is true of hall2007 and not of the default model.

The test for each claim: was it derived from the formula or source, or read off a sample? If read off a sample, does it say so?

## Enumeration

| # | Location | Claim | Basis | Scoped? | Verdict |
|---|---|---|---|---|---|
| 1 | R:5-7 | "gives **every segment** a width" | sample/intent | no | **Wrong** (F1) |
| 2 | R:7 | first-order streams that `..._channel_width` leaves NULL | source (`channel_width.sql` `stream_order > 1`) | n/a | holds |
| 3 | R:39 | one power-law form | formula | n/a | holds |
| 4 | R:47-48 | poisson2021 coefficients, offsets, 2 dp | source SQL | n/a | holds. fresh SQL vs fwapg's own formula on current inputs: **0 differences over 11,337 BULK MODELLED rows** |
| 5 | R:52-54 | hall2007 = flooded `(area_km2^0.280)*0.196*(precip_cm^0.355)`, no rounding | source (`fl_flood_surface.R:101`) | n/a | holds |
| 6 | R:54-57 | hall2007 below poisson2021 except on small catchments; crossover 65 / 16 / 5 ha at 100 / 1000 / 4000 mm | formula | yes | holds (64.9 / 15.6 / 5.2 ha). Omits two details: a lower crossing at 0.04-0.8 ha, below which hall2007 is lower again; and no crossing at all above ~7,785 mm (54 precipitation rows province-wide). Immaterial: 0 BULK order-1 segments sit below the lower crossing. Not flagged |
| 7 | R:63 | written only where both bases are positive | code | n/a | holds |
| 8 | R:64 | "Rows with a NULL or **non-positive input** stay NULL" | generalised from offset-0 (hall) | no | **Wrong for the default model** (F2) |
| 9 | R:64-65 | unlike fwapg, NULL precipitation is not treated as 0 | source (`coalesce(p.map_upstream, 0)`) | n/a | holds |
| 10 | R:67-70 | fwapg MODELLED is constant per wscode/localcode pair, from the max upstream area, so each segment gets the width at the reach's downstream end | source SQL | n/a | holds. fwapg also groups by `watershed_group_code`; harmless within one WSG |
| 11 | R:71-73 | Bulkley: group-max join puts 94% within 5%, about 10% with own area | sample | yes (Bulkley) | holds: 10,637 / 11,337 = 93.8% |
| 12 | R:103-116 | example: "fwapg-matching area" subquery hardcodes `'BULK'` | sample leaked into a recipe | partly (literal is visible) | **Misleading** (F5) |
| 13 | R:217-218 | k kept as SQL text "so rounding at 2 dp matches fwapg on .xx5 boundaries" | unmeasured when written | no | now measured: 0 / 11,337 BULK rows differ from fwapg's own formula. Holds on that population |
| 14 | R:283-285 | precipitation is an integer column in FWA | source schema | n/a | holds (`map_upstream integer`) |
| 15 | R:306-307 | negative base to a fractional power errors; NULL fails the guard | Postgres behaviour | n/a | holds |
| 16 | T:40-56 | literal regex on the emitted SQL | formula | n/a | holds |
| 17 | T:64-72 | one point (A = 2500, P = 800) against hand-copied fwapg and flooded formulas, tolerances 1e-9 / 1e-12 | formula | n/a | holds. "Area already carries the +1" matches `max(...) + 1` in the SQL |
| 18 | T:252 | test **name**: "...; hall2007 runs lower" | sample (this AOI) | no | **Wrong** (F3) |
| 19 | T:274 | `nrow(modelled) > 0` | premise | n/a | holds (9) |
| 20 | T:275-276 | "9 MODELLED rows, max diff 0.03 m. Residual is input-snapshot drift, not the formula" | sample (dated) plus a causal claim | yes (dated) | holds. 9 rows and 0.03 m reproduced. Causal half now measured: fwapg's own formula on current inputs equals fresh on all 11,337 BULK rows, and differs from the stored table by up to 0.52 m. findings.md still says "likely"; record the measurement there |
| 21 | T:277 | tolerance 0.05 m | sample (AOI max 0.03) | AOI-scoped (accepted) | holds here, fails loudly on refresh. BULK-wide the stored-vs-current gap reaches 0.52 m, so this tolerance is valid only for this AOI |
| 22 | T:281-283 | SQL agrees row by row with the R preset; no fixed inequality holds | formula | n/a | holds (15 / 15) |
| 23 | T:291-292 | exact equality after `round(, 2)` and unrounded | formula | n/a | holds. A .xx5 double-vs-numeric rounding split is possible but negligible and would fail loudly |
| 24 | T:293 | `all(is.na(cw_poisson[!has]))`, i.e. NULL inputs stay NULL | sample | — | **Vacuous** (F4) |
| 25 | T:294 | `cw_hall > 0` | formula | n/a | holds |
| 26 | T:302-304 | overwrite reproduces values and label count | formula | n/a | holds |
| 27 | T:323-324 | `nrow(before) > 0`, `n_null > 0` | premise | n/a | holds (11, 4) |
| 28 | T:337 | every NULL-width row gets filled | sample (all 4 have inputs) | AOI (accepted) | holds here, fails loudly elsewhere |
| 29 | T:339 | filled rows are all order 1 | sample | AOI (accepted) | holds here, fails loudly elsewhere |

## Findings

- **F1 [doc, misleading]** R/frs_channel_width.R:5-7. The headline sentence promises "every segment a width". Measured on BULK with the documented joins: 2,427 of 32,472 segments (2,427 of the 17,118 NULL-width rows) stay NULL after the default call. All but one are placeholder (`999` wscode) or unmapped (NULL localcode) segments, which are missing from `fwa_streams_watersheds_lut` and so get no area. WSG-level `frs_extract()` does not exclude these segments, and they are the in-waterbody and secondary-flow edges a width buffer would draw. The Details section (line 64) states the NULL-input rule, but the opening sentence is the claim a caller acts on. Fix: scope it, e.g. "every segment with both inputs (in FWA, every real-network segment; placeholder and unmapped segments have no upstream area)".

- **F2 [doc, wrong]** R/frs_channel_width.R:64. "Rows with a NULL or non-positive input stay NULL" is true only when the offsets are 0, i.e. hall2007. The guard is `input + offset > 0`, so under the default poisson2021 (offset +1) an input of `0`, or anything above `-1`, **is written**. There is no FWA impact: min `map_upstream` is 12 and min `upstream_area_ha` is 2.8e-5, with zero non-positive rows. It does matter on another network, which the package design explicitly targets. There, a `0` used as a missing-value sentinel gets a plausible width while the doc promises NULL. Fix: say "rows whose base (`input + offset`) is not positive stay NULL", or drop the second sentence, since line 63 already states the rule correctly.

- **F3 [test name, wrong]** tests/testthat/test-frs_channel_width.R:252. The test is still named "poisson2021 reproduces fwapg MODELLED widths; hall2007 runs lower". R2 removed that inequality from the body, and the comment at 281-283 says no fixed inequality holds. The name is the R1 claim surviving in the one place the fix did not reach. It is also false for exactly the population the function fills: on BULK order-1 segments with per-segment area, hall2007 > poisson2021 on **4,905 of 15,830 (31%)**. Fix: rename, e.g. "poisson2021 reproduces fwapg MODELLED widths; both presets match their formulas".

- **F4 [test, vacuous]** tests/testthat/test-frs_channel_width.R:293. `expect_true(all(is.na(res$cw_poisson[!has])))` runs over zero rows. All 15 AOI rows have both inputs, so `!has` is empty and `all(logical(0))` is TRUE. It reads as a live check that NULL inputs stay NULL, but it cannot fail on this fixture. That behaviour is pinned only by the SQL-string match at lines 158-159. Fix: either assert the premise (`expect_gt(sum(!has), 0)`), which would currently fail and so needs an AOI row without inputs (none exists here), or delete the line and let the unit test carry the claim.

- **F5 [example, misleading]** R/frs_channel_width.R:103-116. The "fwapg-matching area" recipe filters `WHERE s.watershed_group_code = 'BULK'`, which is the fixture's group copied into a general example. On a table outside BULK the join matches nothing, and nothing errors. After the first example has run, `upstream_area_ha` already exists and keeps its per-segment values. On its own, the column is all NULL and `frs_channel_width()` writes nothing. Either way the caller does not get the parity the paragraph above promises. Fix: write it as `WHERE s.watershed_group_code = <your WSG>` with a comment, or group by `(wscode_ltree, localcode_ltree, watershed_group_code)` and join on all three, as fwapg does.

## Verdict

No code defects. The SQL, the guard, the overwrite path and the type checks are unchanged since R2 and hold. The five findings above are claims, in roxygen and in tests, that a sample made look general. F1 and F2 are what a caller reads and acts on. F3 and F4 are what a reviewer reads as coverage.

Probes (scratchpad): `r3_math.R` (crossovers), `r3_db2.R` (BULK coverage and regime counts), `r3_db3.R` (fresh vs fwapg formula vs stored, 11,337 rows), `r3_live.R` (AOI rows; drops its own table).
