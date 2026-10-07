## Outcome

Added `frs_channel_width()`, which writes a channel width predicted from upstream area and mean annual precipitation onto a working table.

- **Models:** `poisson2021` (the model behind fwapg's MODELLED widths), `hall2007` (the VCA bankfull regression flooded uses), or a custom power law.
- **Fill vs. compare:** by default it fills only NULL widths, which gives first-order streams a width (#28). Pointing `to` at a new column gives an independent estimate to compare against (#29).
- **`value`:** a constant for rows with no inputs, labelled `ASSIGNED`.

It stays standalone, not wired into `frs_network_segment()` / `frs_habitat()`, so bcfishpass parity holds.

Findings that outlive the issue are in `research/fwapg_channel_width.md`:
- fwapg's NULLs come from one `stream_order > 1` filter, not from the model.
- MODELLED parity depends on aggregating area per watershed-code pair.
- Placeholder and unmapped segments carry no inputs (fresh#246).

The follow-up R CMD check sweep found two broken callers. `frs_break()` errored on every call, and `frs_habitat_access()`'s `break_sources` path was broken; both had passed arguments that #95 removed. A vignette and two data-raw scripts carried the same stale call and also missed the ltree enrichment `frs_classify(breaks =)` needs. All are fixed. A static sweep of 1,789 calls against callee `formals()` found no more.

Lessons:
- A property measured on one sample (the hall/poisson crossover) is not a law.
- Mocks that swallow `...` can't see dropped arguments.

## Measurement

- **poisson2021 vs stored MODELLED** (Bulkley, n = 11,334): 3,445 exact and 10,640 (94%) within 5% with the group-max area, against 141 exact with per-segment area. Exact on every row when given fwapg's own inputs.
- **Byman-Ailport AOI:** max |diff| 0.03 m over 9 MODELLED rows. All 4 NULL order-1 widths filled; the 11 existing widths are byte-identical.
- **Input coverage:** 15,830 of 15,831 real-network order-1 Bulkley segments have both inputs. 366,377 of 4,907,441 segments province-wide (7.5%) are placeholder or unmapped and have none.
- **R CMD check:** 1 error / 5 warnings / 3 notes → Status OK. Full suite 1,361 pass.

Closed by: PR (see `/gh-pr-push`), commits 9973c2f (#29), f8cc30a (#28), 50f3fa4 (check fixes)
