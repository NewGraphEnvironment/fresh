# Task: Channel width for every segment (#234)

**If we do it:** every segment, including first-order streams, has a channel width, and there is an independent bankfull estimate to fill or check it against. **If we never do:** consumers that buffer by channel width silently skip the smallest streams.

#28 depends on #29: the regression is what fills the missing widths. One phase per sub-issue; each phase commit carries `Fixes #N`.

Decisions: standalone building block (no wiring into `frs_network_segment()` / `frs_habitat()`, which would move bcfishpass parity); optional constant `value` for segments the regression can't reach. Investigate that gap and file an issue if deriving it looks reachable.

## API

```r
frs_channel_width(conn, table,
  model = "poisson2021",          # "poisson2021" | "hall2007" | list(k, a, b, a_div, p_div, a_off, p_off[, digits])
  to = "channel_width",           # target column; added (double precision) if missing
  col_area = "upstream_area_ha",
  col_precip = "map_upstream",
  col_source = paste0(to, "_source"),  # NULL = don't label
  overwrite = FALSE,              # FALSE = fill NULLs only; TRUE = write every row
  value = NULL,                   # constant for rows still NULL after the regression
  verbose = TRUE)                 # report n modelled / n assigned / n still NULL
```

## Phase 1: Bankfull regression estimate (#29)
- [ ] Failing unit tests (mocked SQL): poisson2021 and hall2007 expressions, custom coef list, default writes only `WHERE <to> IS NULL` and labels only those rows, `overwrite = TRUE` clears then writes every row, inputs guarded `(A + a_off) > 0 AND (P + p_off) > 0`, validation errors (unknown model, incomplete/non-finite coef list, bad identifiers, missing `col_area` / `col_precip` → error names the `frs_col_join()` recipe, `to`/`col_source` colliding with inputs or each other, existing `to` not numeric / `col_source` not text)
- [ ] Internal `.frs_channel_width_models()` presets + `.frs_channel_width_sql()` expression builder. Poisson k emitted as `exp(0.30713)` in SQL; rounding is a preset attribute (`digits = 2` poisson, none hall)
- [ ] `frs_channel_width()`: add target (double precision) + source (text) columns, fill-NULL regression write, `to` / `col_area` / `col_precip` / `overwrite` / `col_source` args; regression labels `MODELLED_POISSON2021` / `MODELLED_HALL2007` / `MODELLED_CUSTOM`
- [ ] Live test (Byman-Ailport `test_streamline.rds`, `skip_if_no_conn()`): extract, `frs_col_join()` area (group-max per wscode/localcode, fwapg's convention) and precip, run poisson2021 into a comparison column, compare to fwapg `MODELLED` (n compared > 0; tolerance ≥ 0.01, set from measurement). hall2007 gives positive widths, below poisson2021. Default call leaves pre-existing widths byte-identical
- [ ] Roxygen (formulas, units, Poisson 2021b / Hall 2007 refs, `@family habitat`) + `@examples` in the `frs_col_join()` style; `devtools::document()`, lintr clean
- [ ] Commit `Fixes #29`

## Phase 2: Fill NA channel width (#28)
- [ ] Failing unit tests: `value` pass runs after the regression with the `ASSIGNED` label, `value` validation (positive finite numeric scalar), verbose counts (modelled / assigned from rows affected, still-NULL from one count query)
- [ ] Implement `value` + count reporting
- [ ] Live test, Byman-Ailport: order-1 NULLs drop to 0 with the regression; pre-existing FIELD_MEASURMENT / FWA_RIVERS_POLY / MODELLED rows byte-identical before and after; `value` fills a synthetic NULL-input row (AOI has no placeholder/unmapped segments)
- [ ] Docs: the fill example in roxygen; `frs_col_join()` `@seealso` → `frs_channel_width()`
- [ ] Commit `Fixes #28`

## Phase 3: Gap follow-up + bookkeeping
- [ ] Write up the placeholder/unmapped input gap in findings.md (counts by edge type, why fwapg's lut excludes them, candidate derivations: spatial-midpoint → fundamental watershed for unmapped; inherit from the paralleled mainstem for side channels; none for placeholders). File an issue if it looks half reachable (public tone: package logic only)
- [ ] CLAUDE.md architecture line for `R/frs_channel_width.R` (no `_pkgdown.yml` reference index exists; NEWS + version bump land in the release commit via `/gh-pr-merge`)
- [ ] Full `devtools::test()` + `devtools::check()` clean

## Validation

- [ ] Tests pass
- [ ] `/code-check` clean on each commit
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
