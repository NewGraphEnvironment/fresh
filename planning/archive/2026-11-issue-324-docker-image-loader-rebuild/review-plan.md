# Plan review for #324 (Plan agent, spawned 2026-11-24T18:09:54Z, delivered ~18:24Z)

Blockers raised: 2
Owner forks: 0

Findings, verbatim in substance; verdicts are added below each after a probe.

- B1 (Blocker): run.sh's disk watchdog stops `fresh-loader-rebuild`, but compose 2.15.1 `run` ignores `container_name` (the loader is `fresh-rebuild_loader_run_<hash>`), so the guard is a no-op. FRESH_LOADER_CONTAINER only acts under `up`; README implies it names the run container.
- B2 (Blocker): test-frs_fwapg_gate.R's FRESH_FWAPG_CURRENT gate keys on `include_disconnected` in fwa_indexpoint's arguments (helper-db.R:65-71); fwapg newgraph's 202610240132__indexpoint_tiebreak.sql is upstream's version (3-arg), the rework fresh gates on is on fwapg branch 41-fwa-indexpoint-one-tie-rule-and-measure (fwapg#41 open). So the gate test fails on the rebuild.
- G1 (Gap): migration 202611131236__namedstreams.sql is a data migration (TRUNCATE + INSERT into fwa_named_streams); run before load.sh it inserts 0 rows, and load.sh line 118 rebuilds the table with the old SQL. db_version reads current while the table is pre-migration. fresh does not read fwa_named_streams.
- G2 (Gap): the worktree's compose dir is also named `docker`, the live project's name; a compose command there without -p addresses live. README's `export` example makes a later bare command recreate live's db. Add COMPOSE_PROJECT_NAME.
- G3 (Gap): merging arms the deferred swap: the next `docker compose up -d db` in the live checkout recreates fresh-db on bookworm over the bullseye data. Suggest `image: ${FRESH_DB_IMAGE:-...bookworm}` with the live host holding bullseye in a gitignored docker/.env until the follow-up.
- G4 (Gap): ~/.Renviron sets PG* to another machine; set PG* with Sys.setenv() in R and prove the target with `SELECT tag FROM fwapg.db_version` (live has no such table).
- O1 (Ordering): #302 never needed the rebuild; reword plan line 55.
- A1 (Assumption): #304's mechanism: GEOS predicates (ST_Relate, ST_Disjoint, ST_Touches) agree the point touches; only ST_Intersects / ST_Covers (PostGIS point-in-polygon shortcut) say false. Unmeasured hypothesis: every probe ran on arm64; FMA could move the interpolated point's last bits. Probe with --platform linux/amd64.
- S1 (Scope): plan text left stale by the probe (lines 53, 61, 62, 57, 76).
- S2 (Acceptance): #306 closes on the pinned GEOS, but live stays on bullseye; #335 should re-run the #306 probe after the swap; the doc note should say output differs between GEOS 3.11 and 3.12+.
- A2: the exact tag can be re-pushed; pin tag@digest if "never floating" is literal.
- A3: README's second-instance example never sets FWAPG_DIR (default is a possibly stale checkout).
- Privacy: stamp.txt (and attempt1's) records an absolute home path in a public repo. Don't quote PR #252's title in the closing comment.
- Acceptance: compare the suite on the rebuild against a live run rather than reading it as a plain pass.

## Verdicts (probed 2026-11-24)

- B1 reproduced (`docker ps`: `fresh-rebuild_loader_run_dba75d0455fa`); fixed in run.sh with `run --name`.
- B2 reproduced (rebuild's fwa_indexpoint args: `point geometry, tolerance ..., num_features ...`); expected failure, issue to file.
- G1 reproduced (load.sh:118 rebuilds fwa_named_streams with `ST_Simplify(ST_Union(geom), 25)`); fwapg issue to file.
- G2, G3 folded: COMPOSE_PROJECT_NAME in README; FRESH_DB_IMAGE with gitignored docker/.env, owed after merge.
- G4: to apply in Phase 3.
- O1: #302 counted on live, done before the review landed.
- A1 confirmed by measurement: amd64 answers true (image_probe_amd64.txt).
- S1, S2: plan text corrected under "Corrections after the plan review".
- A2: kept the exact tag; digest recorded in the probe log. A3: README sets FWAPG_DIR. Privacy: stamps scrubbed.

## Files the plan names

docker/load.sh
docker/docker-compose.yml
docker/README.md
docker/tuning.md
docker/.gitignore
data-raw/docker_image_probe.sh
data-raw/network_features_answer_pairs.R
data-raw/logs/docker_rebuild_324/run.sh
tests/testthat/test-frs_network_features-local.R
tests/testthat/test-frs_near_river.R
tests/testthat/test-frs_fwapg_gate.R
R/frs_lake_fetch.R
R/frs_wetland_fetch.R
R/frs_watershed_at_measure.R
research/fwa_fetch_determinism.md
research/fwa_downstream_walk.md
research/fwapg_channel_width.md
