# Code-check round 4: #324 branch

## Checklist read

- code-check-infra.md: in full.
- code-check-r.md: read "`on.exit()` at a script's top level never fires", "A `data-raw/` script must load the source tree, not the installed package", "testthat counts an uncaught error under `error`, not `failed`", "`stats::aggregate()` has three separate silent behaviours…", "Postgres row order is never fixed unless the query fixes it…", "Under `R CMD check`, tests run from a temp dir against the INSTALLED package". That is 6 read and 126 not.
- code-check-shell.md: read "A failed `cd` lets every later command run in the directory you were already in", "An amd64-only image needs `--platform`…", "Empty arrays under `set -u` on bash 3.2", "Put cleanup on the EXIT trap, not RETURN…", "A second `trap … EXIT` replaces the first", "`a && b || c` runs `c` when any step before the `||` fails", "`mktemp` template needs enough X's…". That is 7 read and 68 not.
- code-check-spatial.md: read "`sf::st_as_binary()` returns a LIST of raw vectors…" and "Canonicalize geometry before hashing it…" (`simplify_repeat.R` hashes WKB). That is 2 read and 96 not.
- code-check.md: the prose of all 14 H3s under `## Mechanisms` (table rows and evidence blocks skipped), plus "Documentation Staleness".
- Rounds 1 to 3 reports and the round 3 fixes diff were read.
- Logs read: `image_probe.txt`, `image_probe_amd64.txt`, `postconditions.txt`, `simplify_repeat_543{2,3}.txt`, `suite_summary.txt`, `answer_pairs_543{2,3}.tsv`, `stamp.txt`, `planning/active/findings.md` and `progress.md`.
- Probes run this round:
  - Read-only SELECT on both `fresh-db` and `fresh-db-rebuild`. For 17060680: lut rows 0, `ST_Intersects` midpoint 0 polygons, `ST_DWithin(…,0)` 2, on both databases.
  - `docker buildx imagetools inspect postgis/postgis:16-3.5`: the registry digest today is `94146ac…`, the digest probed in `image_probe_amd64.txt`. It has an amd64 manifest only.
  - `gh api` of smnorris/fwapg `docker/db/Dockerfile`: `FROM postgis/postgis:16-3.5`.
  - `gh issue view smnorris/fwapg 193`: merged, "load schema to dockerized db…".
- No worktree created, nothing run against either database beyond SELECTs.

Index, diff and changed files read from file.

## Re-walked enumerations (HEAD dc0893e)

### A: every documented docker invocation, and every command one documented workflow runs beside one

Key: N = names it, I = inherits it from the shell, D = compose default (the first instance's), and a dash where it does not apply. Rows marked **new** were added by round 3's fixes, or missed by round 3's table.

| # | file:line | invocation | project | files | image | container / path | shell it is documented for | verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | README:17 | `docker compose up -d db` | I | I (+override) | I (.env / D) | D | first | safe (accepted) |
| 2 | README:21, 24 | `docker compose run --rm loader [--bcfishobs]` | I | I | I | D | first | safe (accepted) |
| 3 | README:35 | `docker compose up -d db` (restart) | I | I | I | D | first. The pointer at :29 sends a second-instance reader to that section. | safe. In an exports shell it starts the second, and the pointer plus :107 say the section assumes no exports. |
| 4 | README:38-39 | `docker exec fresh-db pg_isready` / `psql` | – | – | – | N literal: first | first; :29 says "the `fresh-db` below is the first" | safe now. Misleading at worst, never destructive, and it is labelled. |
| 5 | README:74 | `FWAPG_DIR=… docker compose run --rm loader` | I | I | I | D | first | safe (accepted) |
| 6 | README:99-103 | `cd docker; export COMPOSE_PROJECT_NAME COMPOSE_FILE FRESH_DB_IMAGE FRESH_DB_CONTAINER FRESH_DB_PORT FRESH_DB_DATA FWAPG_DIR; docker compose up -d --wait db` | N | N, no override | N (export outranks .env) | N | second | safe. A failed `cd` or a later `cd` elsewhere fails loudly, because `COMPOSE_FILE` is relative. |
| 7 | README:104 | `docker compose run --rm --name fresh-loader-2 loader` | N | N (same as `up`) | N | N | second | safe |
| 8 **new** | README:110 | `docker compose down` (teardown) | N (export) | N (same files as `up`) | – | N | second | safe |
| 9 **new** | README:111 | `rm -rf postgres-data-2` | – | – | – | literal path, relative to cwd | second, cwd `docker/` from :99 | safe. It names the second's directory by the same literal the export uses, and never the first's. From another cwd, :110 errors loudly and `rm -rf` of an absent path is a no-op, so the second survives rather than the first being touched. |
| 10 **new** | README:112 | `unset` of the seven exported names | – | – | – | – | second → first | safe. The list equals :100-102's export list, so no leftover `FRESH_DB_IMAGE` outranks the first's `.env` pin. |
| 11 | README:138 | `docker compose down` | I | I | – | I | first. The pointer at :134 covers the exports shell. | safe |
| 12 | README:141-142 | `docker compose down -v`, `rm -rf postgres-data` | I | I | – | N literal: first | first; :134 says that in an exports shell `rm -rf postgres-data` deletes the first's data and to use the second's section | safe now. The warning sits directly above the block and names the consequence (the accepted pre-existing section). |
| 13 | README:145 | `docker compose build loader` | I | I | – | – | either | harmless |
| 14 | compose:4-9 | Usage block | I | I | I | D | first | safe (accepted) |
| 15 | compose:18-21 | one-shot prefix `COMPOSE_PROJECT_NAME=fresh-2 COMPOSE_FILE=docker-compose.yml FRESH_DB_IMAGE=… FRESH_DB_CONTAINER=… FRESH_DB_PORT=5433 FRESH_DB_DATA=… docker compose up -d db` | N | N, base only | N | N | that one command | safe for the command shown. It points to the README for the rest (unchanged from round 3). |
| 16 | tuning.md:71 | `docker compose exec db psql …` | I | I | – | I | either | safe: follows the shell |
| 17 | tuning.md:79-80 | `docker compose down; docker compose up -d db` | I | I | I | D | first | safe (accepted: the `.env` pin is an owed step) |
| 18 | load.sh:10-11 | usage `docker compose run --rm loader [--bcfishobs]` | I | I | I | D | first | safe (accepted). load.sh itself reaches `db` only through `DATABASE_URL`. |
| 19 | probe:42 | `docker exec "$SRC" psql … COPY … TO STDOUT` | – | – | – | N (arg) | any | safe: read only, plus session temp objects |
| 20 | probe:107 | `docker run -d --rm --name probe-$i-$$ [--platform …] -e POSTGRES_PASSWORD=probe "$img"` | – | – | N | N, unique per pid | any | safe |
| 21 | probe:92, 113-114 | `docker exec [-i] "$c" pg_isready / psql` | – | – | – | N | any | safe |
| 22 | probe:37, 97, 119 | EXIT-trap `docker stop` of `STARTED` only; `docker inspect`; `docker image inspect` | – | – | N | N | any | safe |
| 23 **new** | probe:17-19 | documented invocation `bash data-raw/docker_image_probe.sh fresh-db fwapg <2 images> > data-raw/logs/docker_rebuild_324/image_probe.txt` | – | – | N (2 images) | output target: the committed log | repo root | **unsafe re-run.** The log it names holds 4 images. Re-running the line as written overwrites it with 2 of them, which drops the only GEOS 3.12.2 and PostGIS 3.4.3 evidence (finding 1). |
| 24 **new** | probe:20-22 | documented `… postgis/postgis:16-3.5::linux/amd64 > …/image_probe_amd64.txt` | – | – | N + platform | committed log | repo root | safe. The re-run gives equivalent output. The committed log was produced without a platform (its WARNING line says so), by the script before round 1 added `::`. Provenance is minor and noted in finding 1. |
| 25 | postconditions.sh:12 | `docker exec "$c" psql -d fwapg` over `CONTAINERS` | – | – | – | N | any | safe: SELECTs only |
| 26 | run.sh:23, 28, 48 | `"${DC[@]}" config --images db`, `up -d --wait db`, `run --rm --name fresh-loader-rebuild loader` | N (`-p`) | N (`-f` both) | N (export) | N | its own | safe. `.env` and override are bypassed, and the empty-dir check at :26 comes first. |
| 27 | run.sh:29, 38 | `docker exec fresh-db-rebuild psql`; watchdog `docker stop fresh-loader-rebuild` | – | – | – | N, same names as `DC` creates | its own | safe |

Round 3's finding 1 is now resolved for the two pre-existing sections:
- The second instance has its own teardown that selects through the same exports (rows 8-10).
- Each pre-existing section that names the first by literal carries a pointer, and "Managing data"'s pointer states the destructive consequence.

I judge that sufficient: no documented sequence now deletes or recreates the first instance from a second-instance shell without the reader passing a sentence that names that outcome.

### B: every quantified or scoped claim the diff adds or changes

Verdicts: OK = at or below its source. WIDER = above it. minor = above, or loosely cited, in a way that does not change what a reader does.

| # | file:line | claim | source | verdict |
|---|---|---|---|---|
| 1 | lake/wetland_fetch.R:13-14 (+ man) | "3.11 and 3.12 to 3.13 gave different vertices" | `image_probe.txt`: 3.11.1 = 556 points, 3.12.2 and 3.13.1 = 514 | OK (bounded, past tense; it states existence) |
| 2 | lake/wetland_fetch.R:15-16 | "GEOS 3.9.0 on arm64 can also give different rings on two calls" | `image_probe*.txt` source runs, `simplify_repeat_5432.txt` | OK |
| 3 | lake/wetland_fetch.R:16-17 | "3.11 to 3.13 repeated (one lake, arm64)" | `image_probe.txt` 20 calls each | OK |
| 4 | watershed_at_measure.R:23-26 (+ man) | "On GEOS 3.11 to 3.13 that simplifier repeated its answer between calls on one database (measured on a lake, arm64); on GEOS 3.9.0 under arm64 two calls can differ" | same | OK. It is no longer claimed for this function or "every call". |
| 5 | watershed_at_measure.R:27-29 | "(3.11 and 3.12 to 3.13 did)" | `image_probe.txt` | OK |
| 6 | probe:7-8 | midpoint "which ST_Relate puts on its watershed's boundary" | `F0FFFF212` on all six stacks | OK |
| 7 **new** | probe:17-19 | the usage line produces `image_probe.txt` | the log holds 4 images (17-3.5.3-bookworm, 17-3.6.1-trixie, 16-3.4.3-bookworm, 16-3.4-alpine3.20); the line lists the first two | **WIDER / wrong** (finding 1) |
| 8 **new** | probe:20-22 | the `::linux/amd64` line produces `image_probe_amd64.txt` | the log's WARNING line: "no specific platform was requested" | minor (equivalent output; the label differs) |
| 9 | probe:23-24 | without a platform an image lacking the host's "fails unless an other-platform copy is already cached" | that same WARNING line | OK |
| 10 | probe:26 | "a container named probe-<n>" | :103 names it `probe-<n>-<pid>` | minor, cosmetic (round 3 noted it) |
| 11 | postconditions.sh:3-4 | live loaded months earlier, "row counts may drift" | `postconditions.txt` (+12, −1) | OK |
| 12 | postconditions.sh:65 | "BULK + ADMS expected 40,504" | `postconditions.txt` 40,504 on both | OK |
| 13 | run.sh:7 | "Changed after attempt 3 ran (code review, 2026-11-26)" | commit 4550d36 | OK |
| 14 | second.yml:1-5 | 32 GB preset; 12gb under two parallel hash joins at 1GB; loader alone, one session | tuning.md; infra "Tuning vs host RAM" | OK |
| 15 | simplify_repeat.R:4-5 | OFFSET 0 stops the double evaluation | findings.md (the first try's split row) | OK |
| 16 | suite_run.R:81-82; suite_summary.txt:117-119 | the frame counts blocks; "897 … 0 whose … differ"; reporter totals equal | both summary blocks `FAIL 0 WARN 18 SKIP 7 PASS 2938`; round 3 re-compared the CSVs | OK |
| 17 | suite_summary.txt:106 | "first of four tags; latest 202611131236" | `postconditions.txt` | OK |
| 18 | answer_pairs.R:4-6, 14-17 | "22 of 40,495 … 22 of 40,769"; both populations; "connects as the live tests do (FRESH_PG*)" | `answer_pairs_543{2,3}.tsv` | OK |
| 19 | README:92 | listens on 5432 unless `FRESH_DB_PORT` | compose `ports:` | OK |
| 20 | README:96 | exported project and files keep "every later `docker compose` in that shell" on the second | rounds 1-2; a `cd` elsewhere errors loudly | OK |
| 21 | README:96 | no files named merges the override; fewer files than the `up` recreates | rounds 1-2 measured | OK |
| 22 | README:96 | `.env` "is read by every project in this directory, and only an exported variable outranks it" | round 1 measured | OK |
| 23 | README:107 | "`docker compose run` ignores `container_name`" | Compose `run` naming | OK |
| 24 **new** | README:107 | "Every other section of this file assumes a shell without these exports: its literal `fresh-db` and `postgres-data` name the first instance" | sections at :17-145 | OK. The literals in Restart, QGIS, R, Managing data all name the first. |
| 25 **new** | README:134 | in an exports shell "`rm -rf postgres-data` deletes the first instance's data" | `FRESH_DB_DATA` default `./postgres-data`, cwd `docker/` | OK |
| 26 | README:115 | second.yml "sized for the loader alone, one session" | second.yml header | OK |
| 27 | README:119; compose:24-26 | old GEOS "returns an empty intersection for an exactly vertical line lying (wholly) inside a box" | `image_probe.txt` and `image_probe_amd64.txt`: EMPTY at x = 1000 and 1500 on both architectures | OK (round 3's finding 3 is fixed) |
| 28 | README:119; compose:25-26 | "on arm64, simplifies a polygon differently from one call to the next" | arm64 3.9.0, one polygon (existence) | OK |
| 29 | README:119 | "Upstream fwapg's own db image is still PostGIS 3.5.2 / GEOS 3.9.0 (`postgis/postgis:16-3.5`, amd64)" | the registry digest today equals the probed `94146ac…`, amd64 manifest only; smnorris/fwapg Dockerfile `FROM postgis/postgis:16-3.5` (both checked this round) | OK. This resolves round 3's minor. |
| 30 | README:121; compose:27-29 | new glibc collation version; PostGIS "one minor version ahead" | `postconditions.txt` 2.31 → 2.41, 3.5.2 → 3.6.1 | OK |
| 31 | README:121; compose:29-36 | "Every machine holding a data directory built on the old image…"; `image:` in an override cannot be outranked | instruction (accepted owed step); round 2 measured | OK |
| 32 | README:127 | Stage 1 "every migration in `db/migrations/` … recorded in `fwapg.db_version`" | fwapg `migrate.sh`; `postconditions.txt` 4 tags | OK |
| 33 | README:129 | 3,294 falls | `postconditions.txt` | OK |
| 34 | compose:16-21 | the example names "own project name, files, container names, port and data directory" | the prefix names each of them; it names no loader container because it runs no loader | OK |
| 35 | compose:66-69 | the socket check passed during init and the loader got "Connection refused" | attempt 1 logs; infra "Postgis init time" (15 m) | OK |
| 36 | tuning.md:3 | "tuned for a 128 GB, 16-core machine" | settings table | OK |
| 37 | tuning.md:33-38 | any `-c` flag "must also be added to every host's override"; "silently leaves that host on PostgreSQL defaults" | Compose `command:` replace semantics | OK |
| 38 | load.sh:29-33 | needs `db/schema.sql` (smnorris/fwapg#193); a `db/create.sh` checkout predates it | #193 merged, "load schema to dockerized db…" | OK |
| 39 | load.sh:58-75 | `schema.sql` carries no db settings; migrations hold the exbc and tie fixes; `migrate.sh` "starts `fwapg.db_version` at 0, applies every migration in order and stops on the first error" | `migrate.sh` (`set -euo pipefail`, `ON_ERROR_STOP`, bootstrap inserts 0); `postconditions.txt` | OK |
| 40 | fwa_downstream_walk.md:3, :46 | re-verified 2026-11-24; "22 of 40,495 in SKGT (re-derived 2026-11-24)" | `image_probe.txt`, `answer_pairs_5432.tsv` | OK |
| 41 | fwa_downstream_walk.md:130 | 3.9.0 EMPTY for an exactly vertical line; "sees it at both" | both probes, both architectures | OK |
| 42 | fwa_downstream_walk.md:130 | "GEOS 3.11.1, 3.12.2 and 3.13.1 return the line" | arm64 only (`image_probe.txt`); no amd64 run of any GEOS ≥ 3.11 | **minor WIDER** (architecture). Round 3's finding 5 named this line and it was not changed (finding 2). |
| 43 | fwa_fetch_determinism.md:3-7 | header dates and producers | logs dated 2026-11-24 and 2026-11-26 | OK |
| 44 | fwa_fetch_determinism.md:35-40 | table rows | `image_probe*.txt` (row 1 is one run of three) | OK |
| 45 | fwa_fetch_determinism.md:42-45 | fetch layers 14 / 6 and 20 / 20; SQL 556 ×4, 557 ×16 | `simplify_repeat_543{2,3}.txt` | OK |
| 46 | fwa_fetch_determinism.md:46-47 | "Only GEOS 3.9.0 on arm64 varied"; "3.11, 3.12 and 3.13 each repeat" | the table's rows, all arm64 except the one amd64 3.9.0 row | OK in the table's context |
| 47 **new** | fwa_fetch_determinism.md:48-50 | "one database returned one polygon for this lake (arm64; one polygon at one tolerance, not a sweep, and `frs_watershed_at_measure()`'s subbasin path was not repeat-tested)" | `image_probe.txt`, `simplify_repeat_5433.txt` | OK (round 3's finding 5 is fixed) |
| 48 | fwa_fetch_determinism.md:51-52 | 556 → 514 between 3.11 and 3.12 | `image_probe.txt` | OK |
| 49 | fwapg_channel_width.md:3 vs :43 | header "re-measured 2026-11-24"; bullet "2026-11-24 and 2026-11-26" | – | minor inconsistency (unchanged) |
| 50 **new** | fwapg_channel_width.md:43 | 17060680: "`ST_Intersects` answers false on a database built on arm64 (re-measured 2026-11-24 and 2026-11-26…)" | live (round 3) and, this round, both databases: 0 intersecting polygons, 2 within 0, no lut row | OK |
| 51 **new** | fwapg_channel_width.md:43 | "On amd64 the same test answered true for three other edge midpoints of this shape (#304's probe); this one was not probed there." | `image_probe_amd64.txt`: `intersects` t on the three | OK on scope (round 3's finding 2 is fixed). minor on the pointer: the run is `image_probe_amd64.txt`, made by #324's script, while "#304's probe" can be read as #304's own control, whose architecture findings.md:96 calls "presumably amd64". |
| 52 | fwapg_channel_width.md:43 | "an arm64 build leaves 2,840"; fwapg#60 "recovered 2,835 … on the arm64 build (one measurement)"; "on amd64 it answers true on the three points probed" | `postconditions.txt`; findings.md:82, 118; `image_probe_amd64.txt` | OK |
| 53 **new** | test-frs_near_river.R:187-189 | "GEOS 3.11 to 3.13 return the line (image_probe.txt)" | 3.11.1, 3.12.2, 3.13.1 on arm64 only | **minor WIDER** (architecture) (finding 2). Round 3's finding 4 (the unbounded "later") is fixed. |
| 54 | test-frs_network_features-local.R:17-20 | "22 of 50,417 and 22 of 51,698"; "Counted on the full province … 2026-11-24" | `answer_pairs_5432.tsv` (4,907,441 segments, 246 groups) | OK |
| 55 | all amd64 statements (B 8, 44 row 2, 51, 52; README "amd64") | "amd64" | findings.md:88: the amd64 image ran "under emulation" on an arm64 host | minor, not a finding. The emulator executes the amd64 build's own instruction stream, so this describes that build. No native amd64 host ran it. |

### Sets these lists would have missed

- **Documented commands whose target is a committed log** (A23, A24; B7, B8). Round 3's set A covered only docker invocations and set B covered only prose claims. The probe's usage lines are both: a command that writes over evidence, and a claim about what produced that evidence. Other documented producer lines checked:
  - `postconditions.sh`, `simplify_repeat.R`, `answer_pairs.R` and `suite_run.R`: each usage reproduces its log's population.
  - `run.sh`: writes beside itself and refuses a non-empty data dir.
- **Round 3's own fixes.** Each added line is in the tables above: A8-A10, B24, B25, B47, B50, B51, B53. Only B53 inherits an old gap (architecture). None reintroduces round 3's findings.

## Findings

- **[severity: fragile]** data-raw/docker_image_probe.sh:17-19. The usage example says `bash data-raw/docker_image_probe.sh fresh-db fwapg imresamu/postgis:17-3.5.3-bookworm imresamu/postgis:17-3.6.1-trixie > data-raw/logs/docker_rebuild_324/image_probe.txt`.
  - The committed `image_probe.txt` holds four images: those two, then `imresamu/postgis:16-3.4.3-bookworm` (PostGIS 3.4.3 / GEOS 3.11.1) and `imresamu/postgis:16-3.4-alpine3.20` (PostGIS 3.4.3 / GEOS 3.12.2). It has been so since f5373d9, which committed the script and the log together, so the line was never the command that produced it.
  - Re-running the documented line overwrites the log with two images. That drops the only measurement of GEOS 3.12.2 and of PostGIS 3.4.3, which these lines cite:
    - the roxygen "3.12 to 3.13" in `frs_lake_fetch`, `frs_wetland_fetch` and `frs_watershed_at_measure`;
    - `fwa_fetch_determinism.md`'s table rows "GEOS 3.11.1 (PostGIS 3.4.3, 3.5.3)" and "GEOS 3.12.2, 3.13.1 (PostGIS 3.4.3, 3.6.1)";
    - `fwa_downstream_walk.md:130`'s "3.12.2";
    - the test comment's "3.11 to 3.13".
  - Both research files name this script as their producer, so the documented re-derivation is the one that loses the evidence. Git keeps the old file, so nothing is lost for good, but the recipe does not reproduce the record it points to.
  - The same block's amd64 line shows `postgis/postgis:16-3.5::linux/amd64`. `image_probe_amd64.txt` was made without a platform: its WARNING reads "no specific platform was requested". The script that made it predates round 1's `::` syntax. The output is equivalent, so this half is minor.
  - Fix: list all four images in the first example, in the log's order (`imresamu/postgis:17-3.5.3-bookworm imresamu/postgis:17-3.6.1-trixie imresamu/postgis:16-3.4.3-bookworm imresamu/postgis:16-3.4-alpine3.20`). Optionally note that the amd64 log predates the `::` form.
  - **Rule:** none (closest: code-check.md "Documentation Staleness", whose "usage comments" covers a moved script, not a usage that never matched its output).

- **[severity: fragile]** tests/testthat/test-frs_near_river.R:187 and research/fwa_downstream_walk.md:130. "GEOS 3.11 to 3.13 return the line" and "GEOS 3.11.1, 3.12.2 and 3.13.1 return the line" are measured on arm64 only. `image_probe.txt` is the only log with those versions, and the amd64 log has only GEOS 3.9.0.
  - Round 3's finding 5 named `fwa_downstream_walk.md:130` for this qualifier, and it was not applied. Round 3's fix rewrote the test comment's range and left the architecture out.
  - Low stakes: GEOS 3.9.0's EMPTY was the same on both architectures, so the architecture is unlikely to matter here, and the test keeps its slant either way. The gap is unmeasured, not contradicted.
  - It is the last member of set B still above its source on a scope axis.
  - Fix: add "(arm64)" after each version list.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" (its "Compression runs both ways" paragraph: a sample restated without its condition).

Minor, below the reporting line and listed so the enumeration is complete:
- B10: the probe's comment says `probe-<n>`, but the containers are named `probe-<n>-<pid>`.
- B49: `fwapg_channel_width.md`'s header date (2026-11-24) and its bullet (2026-11-24 and 2026-11-26) disagree.
- B51: "(#304's probe)" would be exact as "(`image_probe_amd64.txt`)".
- B55: "amd64" was measured under emulation.

## Do both sets now sit at or below their sources?

No, not quite.

Set A: every member is safe for the shell it is documented for, except A23. That is the probe's usage line, which overwrites `image_probe.txt` with a subset (finding 1).

Set B: every member is at or below its source except three:
- B7, the same usage line claiming to produce `image_probe.txt` (finding 1);
- B42 and B53, which leave out the architecture on "3.11 to 3.13 return the line" (finding 2).

Every finding from round 3 is resolved in the tree. The two findings above are one new member that round 3's enumeration did not cover, and one qualifier that round 3 asked for and that did not land.
