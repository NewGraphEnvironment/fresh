# Code-check round 3 — branch 274-route-measures-reach-sql-through-s-15-si (HEAD c51bb4f)

## Checklist read

- Indexes: all five `index_code-check*.md` read (they are the same headings as the CLAUDE.md copies).
- `code-check.md`: the prose of all 14 H3s under `## Mechanisms`, with the `|` table rows skipped. None of the 27 sections under "Rules that stand alone", Security or Spreadsheets/PDFs; no heading there names a shape this diff uses.
- `code-check-r.md` (190,768 bytes): read 9 sections: "A value compared as `::text` in SQL has PostgreSQL's spelling, not R's"; "Postgres row order is never fixed unless the query fixes it..."; "`sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words..."; "Verify a float-formatting fix in its consumer, not through `as.numeric()`"; "An `information_schema` lookup by the literal table name misses what Postgres resolves"; "A `function(...)` mock hides arguments the real callee no longer accepts"; "Tests that silently do not run"; "`as.integer("NaN")` is `0`..."; "`expect_false(identical(x, y))` cannot fail when the two are different types". Not read: 106.
- `code-check-spatial.md` (156,392 bytes): read 2: "FWA `upstream_route_measure` misses the next segment's start" and "FWA main flow is not edge type 1000 alone". Not read: 92.
- `code-check-infra.md` (41,794 bytes, over the 40,000 limit): index lines only. Not read: 43. The diff contains no infra, Docker or tofu code.
- `code-check-shell.md` (131,937 bytes): index lines only. Not read: 70. The diff contains no shell.

## Verdict: Clean

No real issues found in the diff.

What I checked, and how:
- Ran the six changed mock test files from a copy (`--no-environ`, so DB tests skip; `NOT_CRAN=true`): 0 fail, 0 error.
- Mutation in the copy, one at a time: reverting `frs_check_upstream()`'s `up_drm` turned 3 tests red. Reverting `frs_network_waterbody()`'s upstream measure turned 1 red, `frs_network_direct()`'s upstream measure 2, and the `frs_network_waterbody()` downstream measure 2. So `sql_measure_picks()` catches each site the multi-table test covers.
- Gate test head case on local fwapg (read-only): blue line 360447231's guarded top is 1528.8506958829107. At `%.17g` it equals `max(upstream_route_measure)` exactly, and at `%s` (1528.85069588291) it does not. `skip_unless_head_case()` still returns old_rule = 0, closed = 1, at_top = TRUE at full precision, so the pin does not skip and is not vacuous. The top segment's geometry end M equals its `upstream_route_measure`, so `ST_LocateAlong()` at the exact top returns a point.
- Temp-table channel: `RPostgres` 1.4.10 `encode_data_frame()` writes 4494.61997946051 + 2^-40 as `4494.6199794605109` and 1234567.8912345678 as `1234567.8912345678546`. Measures and coordinates that reach SQL through `.frs_db_write_temp()` (`frs_point_snap()`, `frs_feature_find()`) therefore go out at full precision. I took this from the encoder offline; the read-only rule stopped me creating a temp table.
- Research-note claim: `format(c(4494.61997946051, 322.567, 2100.018, 10821.8246201562), scientific = FALSE)` gives `"4494.620"` and `"10821.825"`, as the note says.

## Mechanism and enumeration

**Mechanism.** The search was line-oriented, but the call it looked for is not. These SQL builders write the format string as a multi-line `paste0(...)` with one `%s` per line, and put the arguments in a block at the end of the `sprintf()` call. A grep that wants `sprintf` and `measure` on one line only matches calls that happen to fit on one line, so it reports fewer sites than exist. This is the case `code-check.md` "A fixture that cannot reach the failure mode" describes: "The same text scan used to *enumerate* fails the other way, under-counting: it misses a call whose argument sits on a continuation line ... Enumerate by parsing." Its termination clause is in "A guard's scope, escape hatches, and remedies": terminate by enumeration.

**Enumeration method.** I parsed every `R/*.R` file. For each `sprintf()` call (from `getParseData`), I evaluated the format when it is a literal or a `paste0` of literals and matched each `%s`/`%g`/`%f` spec to its argument: 1,123 pairs. A second pass covered every argument of `paste`, `paste0`, `glue`, `dbQuoteLiteral`, `format`, `formatC` and `as.character`. I filtered both lists for anything carrying a measure, key, blk, id, coordinate or threshold, then read each hit at its site.

### Positions sent to a segment pick or fwapg function: handled on this branch (all through `.frs_sql_exact()`)

| site | value |
|---|---|
| R/frs_point_locate.R:31 (`fwa_locatealong(%d, %s)`) | measure; the key is now `%d` of `as.integer()` |
| R/frs_network.R:363 (`frs_network_direct`, no upstream) | downstream_route_measure |
| R/frs_network.R:386, 394 (`frs_network_direct`, upstream) | downstream_route_measure, upstream_measure |
| R/frs_network.R:489 (`frs_network_waterbody`, no upstream) | downstream_route_measure |
| R/frs_network.R:520, 528 (`frs_network_waterbody`, upstream) | downstream_route_measure, upstream_measure |
| R/frs_network.R:622, 630 (`frs_check_upstream`) | down_drm, up_drm |
| R/frs_network_upstream.R:82 | downstream_route_measure |
| R/frs_network_downstream.R:71 | downstream_route_measure |
| R/frs_network_prune.R:128 | downstream_route_measure |
| R/frs_waterbody_network.R:73 | downstream_route_measure |
| R/frs_watershed_at_measure.R:185 (`.frs_watershedatmeasure_sql`, before this branch) | measure; reached from `frs_watershed_at_measure()` :101/:112/:145/:153, `.frs_resolve_aoi()` R/utils.R:984 (aoi blk + measure), and `frs_watershed_split()` |

Every blk next to these goes in through `as.integer()`: R/frs_network.R:352-353 and 447-448, and `as.integer(...)` in the other four files and in `frs_check_upstream`. The `%s` on an R integer is exact.

### Out of scope under the accepted tradeoffs (left as is)

| site | what it writes | why it is out of scope |
|---|---|---|
| R/frs_wsg_drainage.R:102 | `dbQuoteLiteral(as.numeric(outlet drm))` | named exception (fwa_downstream answers the same; bundled outlets have <= 10 digits) |
| R/utils.R:107 `.frs_sql_num()` (`%.10g`) and all its callers: utils.R:320-419 and 484; frs_order_child.R:249 (`distance_max`); frs_habitat.R:1555 (dist_m); frs_cluster.R:215/261/480/503 (confluence_m); frs_near_river.R:346/456 (threshold, distance_max) | thresholds, distances, caps | thresholds and distances are not positions |
| R/frs_classify.R:220 (`BETWEEN %s AND %s`, raw `%s` on `r[1]`, `r[2]`) | classification range bounds | thresholds, not positions (also before this branch) |
| R/frs_barriers_minimal.R:132 (`format(tolerance, scientific = FALSE)`, 7 significant digits) | `fwa_upstream()` tolerance argument | a distance tolerance, not a position (before this branch) |
| R/utils.R:716-718 (`ST_MakeEnvelope(%s, %s, %s, %s)`) | bbox coordinates at 15 digits | same class as the WKT digits = 15 exception (about 1e-9 m at BC Albers) |
| R/utils.R:971 (`ST_GeomFromText('%s')`, `st_as_text(digits = 15)`) | AOI WKT | named exception |
| R/utils.R:996 (`as.character(aoi$id)`) | a numeric AOI table id | an id, not a measure. Exact for whole numbers below 1e15; `1e+05` spelling still compares equal in Postgres. Before this branch |
| data-raw/point_snap_tie_sweep.R:334-336 (`format(d$m, scientific = FALSE)`) | sweep measures at 7 significant digits | not R/; follow-up #289 |

### Checked and found exact or not SQL

- **Integer `%d`.** `measure_precision` (frs_break.R:613 and elsewhere), `stream_order` (frs_order_child.R:243/246), `blue_line_key` (utils.R:709, `paste0` of `as.integer`).
- **Column, table and ltree text.** `blk`, `mds`, `loc` in frs_aggregate.R:158 and frs_classify.R:262 are `.frs_opt()` column names; `col_*`, `by_values` and every `*_tbl` are identifiers.
- **Messages, not SQL.** frs_watershed_split.R:107 and 132 (`%.4f`, `%.0f`) and frs_params.R:782/793/814.
- **Session temp tables.** Measures and coordinates written through `.frs_db_write_temp()` (`frs_point_snap()`, `frs_feature_find()`) go out at full precision, per the RPostgres encoder above.
- **Column references in SQL.** fwa_downstreamtrace (frs_cluster.R:353) and the fwa_upstream / fwa_downstream calls take column references, never R values.
- **No other route.** No `glue()` call in R/ writes SQL, and no other `dbQuoteLiteral` takes a numeric.

Nothing in R/ sends an R-side position into SQL text at fewer than 17 significant digits outside the accepted exceptions above.
