## Outcome

`frs_lake_fetch()`, `frs_wetland_fetch()` and `frs_stream_fetch()` end on `ORDER BY` their unique key (`order_by`, one or more columns, `NULL` for none), take `simplify_m` (normalized for polygons, not for streams, whose direction `ST_Normalize()` would reverse) and an `aoi` polygon filtered with `ST_Intersects()`. `frs_watershed_at_measure()` takes `simplify_m`, simplifying a subbasin once after the difference. The user's gate question (do lines churn without normalizing?) was answered by measurement: no, not even across GEOS versions. Review turned up a class that was already on main: R's formatters decided the SQL text of numbers, so a round blue line key went out as `3.56e+08` (no matching fwapg function) and a 10-digit measure fell below its own segment. Rounds 2–4 each found the next instance inside or beside the previous fix (`%s` → `%.10g` → a sibling builder at 15 digits), and the loop ended on an enumeration of every value the changed code writes into SQL (findings.md). What is now known is in [research/fwa_fetch_determinism.md](../../../research/fwa_fetch_determinism.md).

## Measurement

- Simplified streams, BULK and MORR (52,291 segments) at 25 m and 100 m: 0 WKB differences across two connections and across GEOS 3.9.0 vs 3.10.2. Settled the gate decision to skip `ST_Normalize()` on lines.
- Simplified BULK lakes at 25 m: 46 of 1,754 differ by 1–2 vertices across those GEOS versions, the issue's known limit, now documented with the `postgis_full_version()` advice.
- Without `ORDER BY`, BULK lakes, wetlands and streams all came back out of key order (plan review), so the live `is.unsorted()` guard bites locally.
- `frs_watershed_at_measure(conn, 360609038, 2415.57257727526)`: 1 row on main, 0 after round 2's `%.10g` fix, 1 after `%.17g`. Postgres reads `%.17g` text back exactly for 2,000 of 2,000 doubles, and R's parser for 1,612, which is why the round trip is tested through Postgres.
- Mutation table (scratch copy, failing tests per planted defect): no ORDER BY 8; Normalize on streams 3; `st_as_text` default digits 1; no empty-drop 1; aoi not appended 5; subbasin unsimplified 1; key via `%s` 6; measure via `.frs_sql_num()` 4; exact formatter at `%.10g` 5; builder at `%.15g` 2.
- Full suite: FAIL 0 | PASS 2386.

## Owed

- Comment on wet#155 that the fetchers are ready (our repo, after merge)

Closed by: PR (opened next, from branch `286-fetchers-fix-row-order-and-add-simplify`)
