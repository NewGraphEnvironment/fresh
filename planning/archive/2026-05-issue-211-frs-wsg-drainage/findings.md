# Findings — frs_wsg_drainage (#211)

## Issue context

### Problem

`link` currently computes WSG drainage closure (every WSG a focal set drains through, downstream-first) inline in `data-raw/study_area_wsgs.R` — see `NewGraphEnvironment/link@v0.40.5`. The query reads `public.wsg_outlet`, joins focal → closure via `f.outlet <@ w.outlet`, sorts by `nlevel(outlet) ASC`.

This is FWA-topology — it belongs in `fresh`, not `link`. No bundle/species/overrides knowledge involved; pure network shape.

### Proposed

```r
frs_wsg_drainage(conn, wsgs)
```

- `wsgs`: character vector of WSG codes (the focal set)
- Returns: character vector covering the drainage closure (focal + every WSG they flow through), ordered downstream-first (`nlevel(outlet) ASC`)
- Pure FWA topology — no bundle / species / overrides logic

### Where it lives

`R/frs_wsg_drainage.R`. Sits alongside `frs_wsg_species()` as part of a `frs_wsg_*` family — the WSG-topology surface of fresh.

### Why fresh, not link

`wsg_outlet` is FWA infrastructure. Drainage closure is a network-shape question with no link/bundle knowledge. Other fresh consumers (vignettes, ad-hoc analyses, future provincial drivers in other packages) want this without going through link.

### Acceptance

- [ ] `frs_wsg_drainage(conn, c("PARS","BULK"))` returns the 15-WSG Skeena+Peace closure: `KISP, KLUM, LKEL, LSKE, MSKE, USKE, BULK, FINA, LBTN, LPCE, MORR, PARA, PCEA, UPCE, PARS` — matches `NewGraphEnvironment/link@v0.40.5` `study_area_wsgs.R` output
- [ ] DS-first ordering preserved
- [ ] Closure invariant to focal ordering
- [ ] Runnable `@example`
- [ ] Test against a small live focal set

### Replaces

Inline closure query in `NewGraphEnvironment/link@v0.40.5` `data-raw/study_area_wsgs.R` (lines 44-50 computing `wsg_outlet`-based closure).

### Composes with

`link::lnk_wsg_resolve` (`NewGraphEnvironment/link#207`) — the link wrapper adds the bundle's species-presence filter (#157).

### Naming considered

`frs_wsg_drainage` (chosen) is `frs_wsg_*`-family consistent. `wsg` is FWA-specific terminology — honest to fresh's current FWA-only scope. If fresh ever grows a second network (NHD/HUC), a `network = "fwa"` param can be introduced then (YAGNI today).

## Codebase exploration

### Family conventions

- One existing `frs_wsg_*` function: `R/frs_wsg_species.R:39` — `frs_wsg_species(watershed_group_code)`. Loads a bundled CSV; no DB connection. Validation via `stopifnot()`. Returns data frame.
- `@family` tags in use: `parameters` (frs_wsg_species), `fetch` (frs_stream_fetch), `traverse` (frs_network_downstream), `index` (frs_point_snap), `network` (frs_network_features, frs_point_match, frs_candidates_pick), `database` (frs_db_conn). No existing `wsg` family.

### DB-issuing function pattern (frs_stream_fetch)

`R/frs_stream_fetch.R:42-84` — signature is `function(conn, <filters>, <controls>, table = "...", cols = c(...), limit = NULL)`. Validates identifiers via `.frs_validate_identifier()`. Composes SQL with `paste0` + `sprintf`. Calls `frs_db_query(conn, sql)` to execute.

### SQL idiom

- `sprintf()` + `paste0()` dominate fresh; no `glue`. Helpers in `R/utils.R`: `.frs_quote_string` (line 39, manual escape), `.frs_validate_identifier` (line 54), `.frs_sql_num` (line 71).
- `DBI::dbQuoteLiteral` is the safest path for user-supplied string vectors — link uses it in `study_area_wsgs.R:44`.

### Test pattern

DB-gated tests skip on missing `PG_DB_SHARE`:
```r
skip_if(Sys.getenv("PG_DB_SHARE") == "", "PG_DB_SHARE not set")
conn <- frs_db_conn()
on.exit(DBI::dbDisconnect(conn))
```
Helper: `frs_db_conn()` (`R/frs_db_conn.R:24-44`) reads `PG_*_SHARE` env vars. Mocking via `mockery::local_mocked_bindings()` to capture SQL without a DB.

### Example convention

`\dontrun{}` for DB-requiring examples (per `R/frs_stream_fetch.R:30-41`); inline for CSV-loaded functions (per `R/frs_wsg_species.R:29-38`).

### Existing `wsg_outlet` usage

Zero references in fresh codebase (R + SQL + tests). This function is the first consumer.

### NEWS.md style

`# fresh X.Y.Z` section header, lead with bold one-liner + issue link, then bullets. Reference: `NEWS.md:1-10` (v0.31.0).

### Source SQL to port (from `link@v0.40.5 data-raw/study_area_wsgs.R:44-50`)

```sql
SELECT DISTINCT w.wsg, nlevel(w.outlet) AS depth
FROM public.wsg_outlet w
JOIN public.wsg_outlet f ON f.wsg IN (<focal-lit>)
WHERE f.outlet <@ w.outlet
ORDER BY depth ASC, w.wsg ASC
```

Column name `wsg` to be confirmed in Phase 1.
