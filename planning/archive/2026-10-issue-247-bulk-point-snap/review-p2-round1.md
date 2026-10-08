# Code review: #247 Phase 2, round 1

Scope: `R/frs_point_snap.R`, `R/frs_watershed_split.R`, the snap and watershed tests, and the
small test edits in `test-frs_network_{upstream,downstream,prune}.R` and `test-frs_point_locate.R`.
I also read the helpers in `R/utils.R` and `R/frs_db_query.R`.

I ran all six changed test files against local fwapg. They have 0 failures, 0 skips and 0 errors.

## Findings

- **[severity: bug]** R/frs_point_snap.R:189-190 — When `to` names the same table as a table
  `points`, the source table is destroyed. The function runs `DROP TABLE IF EXISTS <to>` before
  `CREATE TABLE <to> AS ... FROM <points>`, so it drops the input first and the CREATE then fails
  with `relation ... does not exist`.
  - Reproduced live: `frs_point_snap(conn, "working.zz_review_pts", col_id = "site_id", to = "working.zz_review_pts")`
    errored, and `dbExistsTable()` returned FALSE afterwards.
  - Spellings that fold to the same name (`"Working.Pts"` vs `"working.pts"`) hit the same path.
  - Fix: refuse when `tolower(to) == tolower(points)` for a character `points`. Better still,
    build into a scratch name and then `DROP` + `ALTER TABLE ... RENAME` inside one transaction.
    That also stops a failed CREATE from discarding an earlier `to`; for example, a hint outside
    the bigint range fails at fetch time after the DROP has already run.

- **[severity: fragile]** R/frs_point_snap.R:169 and :323, and R/frs_watershed_split.R:103 — One
  bad coordinate now aborts the whole batch.
  - A lat/lon outside the valid range makes PostGIS `ST_Transform` raise
    `transform: latitude or longitude exceeded limits`, which fails the entire query. Swapped
    lon/lat columns trigger this, as does a lat of 95. The error does not say which row is bad.
  - Reproduced live with `data.frame(x = c(-126.5, -126.5), y = c(54.5, 95))`, and with one row
    whose x/y were swapped.
  - For `frs_watershed_split()` this is a regression. The old per-point loop wrapped each snap in
    `tryCatch` and skipped a bad point with "failed to snap - skipping". Now the whole split
    errors with the raw PostGIS message.
  - Fix: when `srid == 4326`, set coordinates outside [-180, 180] / [-90, 90] to NA in
    `.frs_point_snap_df()` so the existing `IS NOT NULL` filter drops them, ideally with a message
    naming the ids. Otherwise, at least document that one out-of-range point fails the call.

- **[severity: fragile]** R/frs_point_snap.R:133 and :359 — A `bit64::integer64` `tolerance`
  passes `.frs_check_scalar_num()` and `tolerance <= 0`. `.frs_sql_num()` then formats its raw bits
  as `4.940656458e-322` (verified), so `ST_DWithin` matches nothing and every point is dropped
  without an error. This is the same bug class as fresh#248. A bigint read from a database
  arrives as integer64.
  - Fix: `tolerance <- as.double(tolerance)` after validation. `num_features`,
    `stream_order_min`, `srid` and the hint already go through `as.integer()` / `as.numeric()`,
    which bit64 handles correctly.

## Probed and fine

- **Temp table:** no `frs_tmp_*` tables were left after successful calls or after calls that
  errored.
  - `tmp` is assigned only after the write succeeds, and `on.exit` reads it lazily.
  - Names are lowercase hex and unique per R process. Temp tables are per DB session, so mirai
    workers do not collide.
- **id round-trips:** these all round-trip through `dbWriteTable` and back:
  - character, including tab, newline, backslash, quotes, leading spaces and non-ASCII;
  - integer and double (bit-exact);
  - integer64;
  - factor, which becomes character;
  - Date and logical.
- **sf input:**
  - Empty POINTs become NA and are dropped.
  - POINT Z uses the first two coordinates.
  - MULTIPOINT is rejected.
  - Extra `x`/`y`/`id`/`hint` columns are ignored, because the geometry is used.
  - Zero rows gives "points has no rows".
  - A tibble works as input.
- **Hints:** a NaN hint is treated as NULL.
- **Empty results:** a zero-row result comes back from `st_read` as a plain data.frame.
  `sf::st_drop_geometry()` accepts it, so `frs_watershed_split()` reaches its "No points could be
  snapped" stop. Verified live with an open-Pacific point.
- **Extra columns in `frs_watershed_split()` points:** columns named `id`/`x`/`y`/`hint`/`geom`/`id_point`
  do not interfere. The payload is rebuilt as `id`/`x`/`y`/`hint` and `idx = id_point` is the row
  index.
- **Table input:** the count check handles integer64 counts and treats NULL ids as non-unique.
  A mixed-case table name folds and fails loudly. `col_id` is quoted, so a mixed-case id column
  must match exactly; a mismatch fails loudly.
