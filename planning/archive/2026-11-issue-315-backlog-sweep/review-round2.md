# Review round 2: planning/backlog.md (#315)

## Checklist read

- `planning/backlog.md` at f1f4994 (working tree clean), whole file.
- `backlog_moves.sh` header (grammar), then `bash backlog_moves.sh lanes planning/backlog.md`. Read-only.
- Body and every comment of all 34 member issues: #294 #308 #277 (batch 1), #218 #300 (2), #267 #222 #239 #251 #250 (3), #310 #312 #311 (4), #21 #30 #244 (5), #219 #189 #178 #258 (6), #253 #68 #304 #306 #302 (7), #85 #257 (8), #303 #255 #299 #11 #227 #316 #317 (9). Every repo path each one names, plus the files that hold each helper it names (`git grep` on origin/main 1dcc7a3: `.frs_opt` utils.R:17, `.frs_load_rules`/`.frs_validate_rule` frs_params.R, `.frs_persist_columns`/`.frs_key_match`/`.frs_near_river_sql`/`.frs_group_required`/`.frs_add_id_segment` utils.R, `.frs_conn_params` frs_db_conn.R:256, `frs_habitat_access`/`frs_habitat_species` frs_habitat.R).
- Vignette, README and data-raw text the issues act on: `vignettes/subbasin-query.Rmd.orig:79-111`, `vignettes/habitat-pipeline.Rmd:59,300`, `data-raw/vignette_habitat_pipeline.R:50-58`, `research/fwapg_channel_width.md`, `research/fwa_downstream_walk.md:46`, `CLAUDE.md:252`.
- Umbrella bodies #318-#325 (Touches lines), the three edited ones (#319, #321, #323) in full.
- Privacy: grep of the file and all eight umbrella bodies for private repo names, hosts, ports, tunnels; the only repos named are `NewGraphEnvironment/link` and `NewGraphEnvironment/fwapg`, both PUBLIC (`gh repo view`).

Ordering check on the `lanes` output. All 16 CLASH pairs are ordered through `waits on`: 1-2, 1-3, 1-4, 1-5, 1-6, 1-8, 2-3, 2-6, 3-5, 3-6, 3-7, 3-8, 4-5, 5-6, 5-8 directly, and 2-5 through 5 -> 3 -> 2. No cycle: 1 and 7 wait on nothing; then 2 <- 1; 4 <- 1; 3 <- 1, 2, 7; 6 <- 1, 2, 3; 5 <- 1, 3, 4, 6; 8 <- 1, 3, 5. Six pairs have no ordering at all, direct or transitive: **1-7, 2-4, 2-7, 3-4, 4-6, 4-7**. Findings 1 to 3 below are paths that would turn three of those six into clashes.

## Mechanism

The Touches lines were written from what each issue is *about* (the function it fixes), not from the whole surface the fix reaches. Three kinds of surface get missed that way:

1. **Text that quotes the behaviour being changed.** These are vignettes, vignette data scripts, `CLAUDE.md` prose and research numbers. A fix that changes a default or a key makes them wrong, and the repo's own rules require the edit: CLAUDE.md design principle 1 ("the vignette IS the intended use case") and r-packages "check every number the prose quotes".
2. **Helpers in shared files.** An issue names `.frs_opt()` or `.frs_add_id_segment()`, not `R/utils.R`.
3. **Files a new export or new file must also touch.** These are `_pkgdown.yml` (once #255 groups the index), the `CLAUDE.md` architecture tree and `DESCRIPTION`.

Round 1's three misses were all kind 2 or kind 1. The same mechanism produces findings 1 to 3, where the missed path sits in batch 9's `vignettes/` or `research/` and the two moves are otherwise unordered. Finding 5 lists the same omission in pairs that `waits on` already orders.

## Findings

### 1. Batch 5 omits `vignettes/`, so moves 3 and 4 read FREE

- **Where:** planning/backlog.md:77, batch 5's Touches (and #320's batch 5 Touches).
- **What:** #21's whole Problem section is the code in `vignettes/subbasin-query.Rmd.orig:79-111`, nearly verbatim. That code interpolates `ST_MakeEnvelope(%s, ...)` with `sprintf()` into `frs_db_query()`. Adding `params` is meant to replace that pattern, and CLAUDE.md's design principle 1 makes the vignette the case to update. Batch 9 holds `vignettes/` (#11, citations in the vignettes).
- **Evidence:** `lanes` prints `FREE 3 4`. Move 4 waits on 1 only, and move 3 waits on 1, 2, 7, so nothing orders them.
- **Also, conditional on the gate:** #21's optional `frs_db_bbox_query()` would be a new export. After #255 groups the `_pkgdown.yml` reference index (batch 9), any new export must be listed there, or `check_pkgdown()` errors. So `_pkgdown.yml` belongs on the line if that helper is built.
- **Fix:** add `vignettes/` to batch 5's Touches, and order 3 and 4. Either 4 waits on 3, or 3 waits on 4; neither creates a cycle.
- **Rule:** none.

### 2. Batch 6 omits `vignettes/habitat-pipeline.Rmd` and its data script, so moves 6 and 4 read FREE

- **Where:** planning/backlog.md:85, batch 6's Touches (and #323).
- **What:** #219 proposes changing the bundled `spawn_gradient_min` from 0.0025 to 0. It says outright that "fresh-only runs and the vignette" see these values. Three places state the old value:
  - `vignettes/habitat-pipeline.Rmd:59`: "experimenting with a default set at 0.25%"
  - `vignettes/habitat-pipeline.Rmd:300`: a "Min 0.25%" label
  - `data-raw/vignette_habitat_pipeline.R:58`: "spawn_gradient_min = 0.0025 (0.25% ...)", which reads `parameters_fresh.csv` at :54

  The change makes all three wrong, and the vignette data would need regenerating.
- **Evidence:** batch 9 holds `vignettes/`. `lanes` prints `FREE 4 6`, and neither move waits on the other. (`data-raw/` is held by batch 2, but move 5 already waits on 6.)
- **Fix:** add `vignettes/` and `data-raw/vignette_habitat_pipeline.R` to batch 6's Touches, and order 4 and 6. "4 waits on 6" adds no cycle, since 6 waits on 1, 2, 3.
- **Rule:** none.

### 3. Batch 7 bears on `research/fwapg_channel_width.md`, which batch 9 re-measures; moves 4 and 7 are unordered (judgement)

- **Where:** planning/backlog.md:93 (batch 7) and :109 (batch 9).
- **What:** #304's fix rebuilds `fwa_streams_watersheds_lut` on a new GEOS, and its step 3 asks which other derived tables to rebuild. `research/fwapg_channel_width.md` describes that same lut's spatial-midpoint fallback, the `ST_Intersects` path #304 found broken. It also states Bulkley input counts that depend on the lut ("15,830 of the 15,831 real-network order-1 segments have both inputs"). #304 says 9 of the 18 missing rows are in BULK.
- **Why it matters:** #317 (batch 9) re-runs that file's measurement "against the local fwapg as it stands". If move 4 runs before or during move 7, it records pre-fix numbers, and stamps them Verified, on a database move 7 is about to change. Move 7 may also edit the file itself.
- **Evidence:** batch 7's Touches doesn't list the file. `lanes` prints `FREE 4 7`, and move 4 waits on 1 only.
- **Fix:** add the file to batch 7's Touches, or simply have move 4 wait on 7 (no cycle: 7 waits on nothing).
- **Rule:** none.

### 4. Umbrella #321's Touches doesn't match the file

- **Where:** #321 body vs planning/backlog.md:109.
- **What:** #321 lists `research/` (the whole directory, "including `research/id_segment_identity.md`"). The file lists three research files by name. `lanes` reads the file, so a session reading the umbrella sees a wider scope than the one that was clash-checked. The wider `research/` would also clash with batch 7's `research/fwa_fetch_determinism.md`, which the file's version does not.
- **Fix:** make the two agree. Whichever list is right, the file is what `lanes` reads.
- **Rule:** none.

The other two edited umbrellas match the file exactly: #319 carries `R/frs_habitat_classify.R` and #323 carries `R/frs_habitat.R`. No umbrella states its `waits on`; the file is the only record of it.

### 5. Same mechanism, pairs already ordered (no ordering change, Touches incomplete)

`lanes` already reports a CLASH, or `waits on` orders the pair transitively, so none of these leaves a pair unordered today. Each line is still short of what its issues edit. Each could matter if the order is revised.

- **Batch 4** (:69): `R/utils.R` is missing. #310's first option registers `fresh.schema_working` in `.frs_opt()`'s defaults list (utils.R:17-28). Batches 1, 2 and 3 hold utils.R; move 3 waits on 1 and 2, and move 5 waits on 3.
- **Batch 2** (:53):
  - `CLAUDE.md` is missing. CLAUDE.md:252 spells out `.frs_add_id_segment()`'s assignment, which #218 and #300 change; batch 4 holds CLAUDE.md, and move 5 waits on 3.
  - `R/frs_near_river.R` is missing. #218's unique index goes "wherever the tables are created", and the shared `near_river` table is created at frs_near_river.R:479 on the same key (CLAUDE.md). Batch 1 holds that file, and move 5 waits on 1.
- **Batch 8** (:101): `CLAUDE.md`, `_pkgdown.yml` and possibly `DESCRIPTION` are missing.
  - #257 adds a new R file, and CLAUDE.md's architecture tree (from :33) lists every R file.
  - Its new exports must go in the reference index once #255 groups it.
  - Lidar sampling likely adds Suggests.

  Batches 4 and 9 hold those files. Move 8 waits on 3, and on 5, which waits on 4.

Not findings, since no other batch holds the path:

- `research/fwa_downstream_walk.md:46` repeats the "22 of 40,495" that #302 re-derives.
- The test files #189 and #277 edit: `test-frs_habitat_overlay.R`, `test-frs_habitat.R`, `test-frs_network_features-live.R`.
- `research/libpq_connection_bounds.md` for #312.
