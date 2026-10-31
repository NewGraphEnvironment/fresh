# Plan review — #286 (Plan agent, 2026-10-31, after Phase 1 landed at 5b7d9be)

Returned as reply text (Plan agents cannot write); transcribed here. Verdict per finding after probing is in findings.md.

- **Blocker 1** — `.frs_resolve_aoi()` character branch is `geom && (SELECT ST_Union(geom) ...)`: envelope, not intersection. `aoi = "BULK"` on lakes: 5,118 rows, 3,364 outside BULK. Plan presented WSG form as polygon extent. Planned "aoi subset of bbox" live test passes under `&&` too.
- **Blocker 2** — sf `aoi` goes through `sf::st_as_text()`, which formats with `getOption("digits")` (7): x = 1234567.891 sent as 1234568. Same polygon, different SQL per session. Pass `digits = 15` or WKB; pin with a mocked test.
- **Gap 1** — `linear_feature_id` not unique in fresh's segmented tables (`R/utils.R:576`); allow a vector `order_by` or document.
- **Gap 2** — SQL `ST_Difference` returns one `POLYGON EMPTY` row where `sf::st_difference` returns 0 rows.
- **Gap 3** — new args should go after the current last arg so positional calls keep working.
- **Gap 4** — sf aoi with NA CRS errors in `st_transform` (untested, undocumented); `area_ha_min` still pasted unchecked.
- **Ordering** — line-churn check should run before Phase 2 finishes.
- **Assumption** — one database cannot answer the line-churn question; only a second GEOS can. State what is recorded if none is reachable.
- **Acceptance 1** — live `identical()` can't catch a missing ORDER BY/Normalize; `is.unsorted()` catches ORDER BY locally (BULK lakes 1,754, wetlands 3,684, streams 32,472, streams LIMIT 5 all unsorted without it) but depends on disk layout. Mocked SQL tests are the guard; say so.
- **Acceptance 2** — NEWS: with ORDER BY, `limit = n` returns the n lowest keys. Sort under limit 0.7–104 ms.
- Checked fine: ORDER BY before LIMIT; `AS geom` alias read as geometry; Normalize(Simplify(Difference)) valid POLYGON on real subbasin; GEOMETRYCOLLECTION passes through; lakes 2D, streams 4D; `.frs_build_where` has no other callers.
