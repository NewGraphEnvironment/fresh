# #324 — Backlog move 7: docker image and loader rebuild

## Outcome

`docker/` builds a local fwapg from current fwapg again. `load.sh` runs fwapg's `db/migrate.sh` after `schema.sql` (#253, #68, PR #254 merged in), and the compose file pins `imresamu/postgis:17-3.6.1-trixie` (PostGIS 3.6.1, GEOS 3.13.1), overridable with `FRESH_DB_IMAGE`, with container, port, data directory and loader name taken from env so a second instance can run beside the first. A full load on an empty volume on that image succeeded, and fresh's whole suite on it matched a run on the live database test for test. Two of the gate's premises did not hold and were taken back to the owner: #304's missing lut rows are an arm64 effect, not a GEOS version (fixed upstream of fresh by NewGraphEnvironment/fwapg#60), and upstream fwapg's own image is bullseye / GEOS 3.9.0, not bookworm. The live database stays on bullseye until #335. PR: #337.

Closes #253, #68, #306, #302. #304 stays open (its body corrected). Filed: #334, #335, #336, NewGraphEnvironment/fwapg#60, NewGraphEnvironment/fwapg#61, and the Parquet re-export with its publisher.

## Measurement

- **Load:** 2 h 42 min (00:08:37Z to 02:50:24Z on 2026-11-26), exit 0, network-bound; disk 218 to 159 GB free, so a second instance costs about 60 GB. PR #254's October run took 5 h 52 min.
- **Post-conditions against live:** every table count equal except `fwa_stream_networks_channel_width` (+12) and `fwa_stream_networks_order_parent` (-1), the drift #254 also saw; functions answer identically; `fwapg.db_version` 202611131236 and `exbc` gone from `fwa_watershedatmeasure`.
- **Suite:** live and rebuild both `FAIL 0 | WARN 18 | SKIP 7 | PASS 2938`, 897 tests, 0 whose counts differ.
- **#304:** the boundary `ST_Intersects` is false on arm64 on every PostGIS 3.4-3.6 × GEOS 3.9-3.13 stack and true on amd64 GEOS 3.9.0, with bit-identical midpoints. The rebuild misses the same 18 BULK + ADMS streams (2,840 province-wide) as live. `ST_DWithin(..., 0)` recovers the 18 (2,835 province-wide). Turned "move the image" into a fwapg predicate fix (`research/fwapg_channel_width.md`, "Segments with no inputs").
- **#306:** Tahtsa Reach simplified at 100 m, 20 calls on one connection: arm64 GEOS 3.9.0 gives 556 ×4 / 557 ×16 and two `frs_lake_fetch()` layers; GEOS 3.13.1 one answer (514). GEOS 3.11 gives 556, 3.12+ 514. Closed by doc note per the plan's outcome rule; the durable verdict is `research/fwa_fetch_determinism.md`, "Repeating within one database".
- **GEOS 3.9.0 vertical line** (`research/fwa_downstream_walk.md`, "GEOS"): `LINESTRING EMPTY` for a line inside a box on 3.9.0, the line on GEOS 3.11 to 3.13 (arm64).
- **#302:** the header's 40,495 / 40,769 are the every-25th population; #302's 50,417 / 51,698 are the whole fixture's. Identical on live and on the rebuild, and on a second run.
- **Gate (#336):** on a newgraph-built fwapg, `fwa_locatealong()` at a stream's head returns no row (fwapg#41's measure rework is absent), while `fwa_watershedatmeasure()` no longer errors at the swept position.

## Evidence

`data-raw/logs/docker_rebuild_324/` — `image_probe*.txt`, `postconditions.txt`, `suite_*.csv` and `suite_summary.txt`, `simplify_repeat_*.txt`, `answer_pairs_*.tsv`, the attempt-3 loader files at the top level, and `attempt1_coldstart/` (healthcheck race, fixed) and `attempt2_bookworm_stopped/` (stopped for the switch to trixie). Producers: `data-raw/docker_image_probe.sh`, `data-raw/network_features_answer_pairs.R`, and the scripts beside the logs.

Wrong turns kept: the gate chose bookworm on my unchecked claim that upstream builds on it; the amd64 probe disproved both that and #304's GEOS diagnosis. The first #306 probe reported two point counts with one md5, because the planner evaluated the simplify twice.

## Owed

After the merge, for the owner (the third before the merge reaches each such machine):

- Remove the `fresh-rebuild` instance, `docker/postgres-data-rebuild/` and the fwapg worktree, unless the live-swap issue wants them kept
- Confirm PR #254 shows merged and PR #252 is closed
- Before the merge reaches any machine holding a bullseye-built `docker/postgres-data` (this Mac's main fresh checkout, and each other host running this compose file through its own override; code-check round 1): write `docker/.env` there with `FRESH_DB_IMAGE=imresamu/postgis:17-3.5-bullseye` before its next `up` (not `image:` in its override: code-check round 2), so the database is not moved onto trixie by accident (review G3; undone by #335). The main checkout has no `docker/.env` yet (round 1 listed it)

Code review: `/code-check branch`, 4 rounds, ended by enumeration (`review-verdict.md`, `review-round*.md`).

Closed by: PR #337
