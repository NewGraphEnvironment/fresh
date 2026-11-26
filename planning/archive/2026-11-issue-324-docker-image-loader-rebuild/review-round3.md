# Code-check round 3: #324 branch

## Checklist read

- code-check-infra.md: in full.
- code-check-r.md: read "Postgres row order is never fixed unless the query fixes it…" (for `load.sh`'s `ORDER BY applied_at DESC LIMIT 1`). 1 read, 131 not. Rounds 1 and 2 covered the R script headings (`on.exit()`, `data-raw/` loading, testthat `error`, `aggregate()`).
- code-check-shell.md: read "A failed `cd` lets every later command run in the directory you were already in", "An amd64-only image needs `--platform`…", "Empty arrays under `set -u` on bash 3.2", "Put cleanup on the EXIT trap, not RETURN…". 4 read, 71 not.
- code-check-spatial.md: none read (0 read, 98 not). The diff's spatial content is SQL and prose claims about GEOS, which mechanism B below covers.
- code-check.md: the prose of all 14 H3s under `## Mechanisms` (table rows and `<!-- evidence -->` blocks skipped), plus "Documentation Staleness".
- Rounds 1 and 2 reports and their fixes diff read. Logs read: `image_probe.txt`, `image_probe_amd64.txt`, `postconditions.txt`, `simplify_repeat_5432.txt`, `simplify_repeat_5433.txt`, `suite_summary.txt`, `suite_543{2,3}.csv` (compared test by test), `answer_pairs_*.tsv`, `planning/active/findings.md`. Read-only SELECTs run: on `fresh-db` (lut coverage and midpoint relation for the four cited segments), and on `fresh-db-rebuild` (`fwapg.db_version`). Index, diff and changed files read from file.

## Mechanism and enumerations

**Mechanism A, confirmed and refined.** A documented command reaches whichever instance its selectors pick. Those selectors are the compose project, the compose files (including an implicit `docker-compose.override.yml`), `docker/.env`, shell exports, the working directory, and literal container names and paths. The docs control some of these channels and leave the rest to the context the command is pasted into. Rounds 1 and 2 found the compose side: a second-instance command that named fewer files, or no image, than it needed, so it picked up the first instance's override or `.env`. This round's instance runs the other way. In the shell the second-instance recipe sets up, `docker compose` follows the exported project, but sibling commands in the same README name the first instance by literal (`docker exec fresh-db`, `rm -rf postgres-data`). So one recipe splits its target across two instances. The rule both directions break: every command that one documented workflow runs must select its target through the same channel.

**Mechanism B, confirmed.** A measurement taken on a sample is restated about the whole class. The sample can be three named points, one polygon at one tolerance, GEOS 3.11.1 to 3.13.1, arm64, or an exactly vertical line. The restatement drops the qualifier: "the same point", "every call", "or later", "a line". The architecture qualifier goes missing most often, because architecture became a variable only mid-investigation (the amd64 probe came after most of the GEOS claims were written).

### A: every `docker compose` / `docker run` / `docker exec` invocation in the committed files

Key: N = names it, I = inherits it, D = the compose file's default (the first instance's), – = not applicable.

| # | file:line | invocation | project | files | image | container | port | data dir | inheriting safe? |
|---|---|---|---|---|---|---|---|---|---|
| 1 | README:17 | `docker compose up -d db` | I | I (+override) | I (.env / D) | D | D | D | Yes: first instance by design (accepted). |
| 2 | README:21,24 | `docker compose run --rm loader [--bcfishobs]` | I | I | I | D (`run` names it) | D | D | Yes: first instance (accepted). |
| 3 | README:33 | `docker compose up -d db` (restart) | I | I | I | D | D | D | Yes for the first. In a shell holding the second-instance exports it addresses the second, which the README states. |
| 4 | README:36-37 | `docker exec fresh-db pg_isready` / `psql` | – | – | – | **N literal: first** | – | – | **No** in a second-instance shell: line 33 starts the second and these lines verify the first (finding 1). |
| 5 | README:72 | `FWAPG_DIR=… docker compose run --rm loader` | I | I | I | D | D | D | Yes: first instance (accepted). |
| 6 | README:98-101 | `export COMPOSE_PROJECT_NAME COMPOSE_FILE FRESH_DB_IMAGE FRESH_DB_CONTAINER FRESH_DB_PORT FRESH_DB_DATA FWAPG_DIR`, then `docker compose up -d --wait db` | N | N (both, no override) | N (export outranks .env) | N | N | N (`./postgres-data-2`, relative to `docker/`) | Yes. Loader `BCFISHOBS_DIR` is inherited, a read-only mount. `COMPOSE_FILE=docker-compose.yml` is relative to the cwd, so after a `cd` elsewhere it errors loudly. |
| 7 | README:102 | `docker compose run --rm --name fresh-loader-2 loader` | N (export) | N (same as `up`, no recreate) | N | N (`--name`) | N | N | Yes. The loader reaches `db` over the project network, i.e. the second. |
| 8 | README:126 | `docker compose down` | I | I | – | I | – | – | Consistent: follows the exports. |
| 9 | README:129-130 | `docker compose down -v`, then `rm -rf postgres-data` | I | I | – | I | – | **N literal: first** | **No**: in a second-instance shell `down -v` stops the second, leaves its bind-mounted data, and `rm -rf` deletes the first's data directory, possibly with the first running (finding 1). |
| 10 | README:133 | `docker compose build loader` | I | I | – | – | – | – | Harmless: builds an image. |
| 11 | compose:5-9 | Usage block: `up -d db`, `run --rm loader [--bcfishobs]`, `down`, `down -v` | I | I | I | D | D | D | First instance (accepted). |
| 12 | compose:18-21 | one-shot prefix `COMPOSE_PROJECT_NAME=fresh-2 COMPOSE_FILE=docker-compose.yml FRESH_DB_IMAGE=… FRESH_DB_CONTAINER=… FRESH_DB_PORT=5433 FRESH_DB_DATA=… docker compose up -d db` | N | N (base only) | N | N | N | N | Safe for that one command. The prefix is not exported, so the next command (the Usage block's `run --rm loader` four lines up) addresses the first. A recreate there is blocked only by the `fresh-db` name collision, or not at all. Base-file memory beside the first fails at start on a smaller host (infra "Tuning vs host RAM"), loudly. Noted, not a finding: it points to the README. |
| 13 | tuning.md:71 | `docker compose exec db psql …` | I | I | – | I | – | – | Consistent: follows the shell. |
| 14 | tuning.md:79-80 | `docker compose down`, `docker compose up -d db` | I | I | I | D | D | D | First instance (accepted; the `.env` pin is an owed step). |
| 15 | load.sh:10-11 | usage `docker compose run --rm loader [--bcfishobs]` | I | I | I | D | D | D | First instance (accepted). `load.sh` itself makes no docker call; it reaches `db` through `DATABASE_URL`, i.e. its project's network. |
| 16 | probe:42 | `docker exec "$SRC" psql … COPY … TO STDOUT` | – | – | – | N (arg) | – | – | Yes: read, plus temp objects in its session. |
| 17 | probe:107 | `docker run -d --rm --name probe-$i-$$ [--platform …] -e POSTGRES_PASSWORD=probe "$img"` | – | – | N | N (unique per pid) | none published | anonymous, removed with `--rm` | Yes. (The comment at :26 says `probe-<n>`; the name is `probe-<n>-<pid>`. Cosmetic.) |
| 18 | probe:113-114, 92 | `docker exec "$c" pg_isready -h 127.0.0.1` / `psql`; `run_probe` `docker exec -i` | – | – | – | N | – | – | Yes. |
| 19 | probe:97, 119, 37 | `docker inspect "$SRC"`, `docker image inspect "$img"`, EXIT-trap `docker stop` of `STARTED` only | – | – | N | N | – | – | Yes: stops only what it started. |
| 20 | postconditions.sh:12 | `docker exec "$c" psql -d fwapg` over `CONTAINERS` (default `fresh-db fresh-db-rebuild`) | – | – | – | N | – | – | Yes: read-only SELECTs. |
| 21 | run.sh:23 | `"${DC[@]}" config --images db` | N (`-p`) | N (`-f` both) | N (export) | – | – | – | Yes. |
| 22 | run.sh:28 | `"${DC[@]}" up -d --wait db` | N | N | N | N | N | N (checked empty first, :26) | Yes. `.env` and override are both bypassed. |
| 23 | run.sh:29 | `docker exec fresh-db-rebuild psql` | – | – | – | N | – | – | Yes. |
| 24 | run.sh:38 | watchdog `docker stop fresh-loader-rebuild` | – | – | – | N | – | – | Yes: same name as :48's `--name`. |
| 25 | run.sh:48 | `"${DC[@]}" run --rm --name fresh-loader-rebuild loader` | N | N (same `DC` as `up`) | N | N | N | N | Yes. |

### B: every quantified or scoped sentence the diff adds or changes

Verdicts: OK = matches its source; WIDER = written wider than the measurement; minor = wider in a way that does not change a reader's action.

| # | file:line | claim | source | verdict |
|---|---|---|---|---|
| 1 | lake/wetland_fetch.R:13-14, watershed_at_measure.R:28 (and man/) | "3.11 and 3.12 **or later** give different vertices" | `image_probe.txt`: 3.11.1 = 556, 3.12.2 and 3.13.1 = 514; arm64, one lake, 100 m | **WIDER**: nothing after 3.13.1 measured (finding 4) |
| 2 | lake/wetland_fetch.R:15-16 | "GEOS 3.9.0 on arm64 **can** also give different rings on two calls" | `image_probe*.txt` source runs, `simplify_repeat_5432.txt` | OK |
| 3 | lake/wetland_fetch.R:16 | "3.11 to 3.13 repeat" | arm64 only; one lake at 100 m, 20 calls | minor WIDER: no architecture or population (finding 5) |
| 4 | watershed_at_measure.R:24-25 | "the same database returns the same polygon on **every call** (**measured** on GEOS 3.11 to 3.13 …)" | One lake via `ST_SimplifyPreserveTopology` and `frs_lake_fetch()`; this function, its subbasin `ST_Difference` path, never repeated; arm64 only | **WIDER** (finding 5) |
| 5 | probe:7-8 | midpoint "which ST_Relate puts on its watershed's boundary" | `F0FFFF212` on every stack | OK |
| 6 | probe:23-24 | without a platform "an image without it fails unless an other-platform copy is already cached" | round 1's warning line | OK |
| 7 | postconditions.sh:65 | "BULK + ADMS expected 40,504" | `postconditions.txt` 40,504 both | OK |
| 8 | run.sh:7 | "Changed after attempt 3 ran (code review, 2026-11-26)" | commit 4550d36 = 2026-11-26T03:12Z | OK |
| 9 | second.yml:1-5 | "tuning.md's 32 GB preset"; "12gb is under what two concurrent parallel hash joins at work_mem=1GB can need"; "loader alone, one session" | tuning.md preset values identical; infra "Tuning vs host RAM"; round 2 checked fwapg's `load.sh` for concurrency | OK |
| 10 | simplify_repeat.R:4-5 | OFFSET 0 keeps the simplify from running twice | findings.md:124 | OK |
| 11 | suite_run.R:44-45; suite_summary.txt:24-26 | frame counts blocks, a file-level skip adds no row; "897 … 0 whose … differ"; reporter totals equal | Re-compared the two CSVs: 897 unique (file, test) keys each, 0 rows differing; both reporter lines `FAIL 0 WARN 18 SKIP 7 PASS 2938` | OK |
| 12 | suite_summary.txt:16 | "first of four tags; latest 202611131236" | `postconditions.txt` tags 0 plus three; `max()` of the text tags is the latest | OK |
| 13 | answer_pairs.R:4-6, :17 | "22 of 40,495 … 22 of 40,769"; "connects as the live tests do (FRESH_PG*)" | `answer_pairs_*.tsv`; test uses `local_fwapg()` | OK |
| 14 | README:90 | "listens on 5432 unless FRESH_DB_PORT says otherwise" | compose `ports:` | OK (host port) |
| 15 | README:94 | `.env` "is read by **every** project in this directory, and **only** an exported variable outranks it" | round 1 measured; any project whose first file is in `docker/` | OK |
| 16 | README:94 | no files named means the override is merged; "fewer files than the up recreates the db" | rounds 1 and 2 measured | OK |
| 17 | README:103 | "`docker compose run` ignores `container_name`" | Compose `run` naming | OK |
| 18 | README:109; compose:24-25 | old GEOS "returns an empty intersection for **a line** lying (wholly) inside a box" | Both probes and `research/fwa_downstream_walk.md`: an **exactly vertical** line only; slanted lines are fine | **WIDER** (finding 3) |
| 19 | README:109; compose:25-26 | "on arm64, simplifies **a** polygon differently from one call to the next" | arm64 3.9.0, one polygon | OK (existence) |
| 20 | README:109 | "Upstream fwapg's own db image is **still** PostGIS 3.5.2 / GEOS 3.9.0 (`postgis/postgis:16-3.5`, amd64)" | fwapg `docker/db/Dockerfile` `FROM postgis/postgis:16-3.5` (both local checkouts); versions from a cached copy created 2026-08-31 | minor: GEOS 3.9.0 holds while the tag is bullseye; the PostGIS patch level of a rebuilt tag is unchecked |
| 21 | README:111; compose:27-29 | new glibc collation version; PostGIS "one minor version ahead" | `postconditions.txt` 2.31 to 2.41; 3.5.2 to 3.6.1 | OK |
| 22 | README:111; compose:29-36 | "**Every** machine holding a data directory built on the old image keeps it there…"; `image:` in an override cannot be outranked by an export | instruction (accepted owed step); round 2 measured the outranking | OK |
| 23 | README:117 | Stage 1: "**every** migration in db/migrations/ … recorded in fwapg.db_version"; "3,294 barrier falls" | `migrate.sh` (round 1); `postconditions.txt` 4 tags, `working.falls` 3294 | OK |
| 24 | compose:66-74 | socket healthcheck calls the init server healthy, loader got "Connection refused" | attempt 1 logs; infra "Postgis init time" (15 min floor matches `start_period: 15m`) | OK |
| 25 | tuning.md:3 | "tuned for a 128 GB, 16-core machine" | settings table | OK |
| 26 | tuning.md:33-38 | "any -c flag … must also be added to **every** host's override"; "silently leaves that host on PostgreSQL defaults" | Compose `command:` replace semantics | OK |
| 27 | load.sh:58-75 | `schema.sql` carries no db settings; migrations hold the exbc and tie fixes; `migrate.sh` "applies **every** migration in order and stops on the first error" | round 1; `postconditions.txt` (exbc f on rebuild, tags present); rebuild `applied_at` distinct per tag, so the echo's `ORDER BY applied_at DESC LIMIT 1` is determinate | OK |
| 28 | fwa_downstream_walk.md:3, :46 | "re-verified 2026-11-24"; "22 of 40,495 in SKGT (re-derived 2026-11-24)" | `image_probe.txt`, `answer_pairs_5432.tsv` dated 2026-11-24 | OK |
| 29 | fwa_downstream_walk.md:130 | 3.9.0 EMPTY for an exactly vertical line; "sees it at both" x values | both probes, both architectures | OK |
| 30 | fwa_downstream_walk.md:130 | "GEOS 3.11.1, 3.12.2 and 3.13.1 return the line"; "docker/ now pins a GEOS 3.13.1 image" | arm64 only; trixie tag | minor WIDER on architecture (finding 5) |
| 31 | fwa_fetch_determinism.md:35-40 | table rows | `image_probe*.txt` | OK. Row 1 is one run of three (556 ×3/×4); the bullet gives the other. |
| 32 | fwa_fetch_determinism.md:42-45 | fetch layers 14/6 and 20/20; SQL 556 ×4, 557 ×16 | `simplify_repeat_543{2,3}.txt` | OK |
| 33 | fwa_fetch_determinism.md:46-48 | "**Only** GEOS 3.9.0 on arm64 varied"; "3.11, 3.12 and 3.13 **each** repeat"; "so on docker/'s image … **one database returns one polygon**" | the table's rows (arm64; one lake; 100 m) | first two OK in the table's context; the conclusion is **WIDER** in population (finding 5) |
| 34 | fwa_fetch_determinism.md:49-50 | output changed between 3.11 and 3.12 (556 to 514) | `image_probe.txt` | OK |
| 35 | fwapg_channel_width.md:3 | "re-measured 2026-11-24" | the bullet says "2026-11-24 and 2026-11-26" | minor inconsistency |
| 36 | fwapg_channel_width.md:43 | 17060680's midpoint is on an edge, `ST_Intersects` false on an arm64 build | live: intersects 0 polygons, `ST_DWithin(…,0)` 2, no lut row (read-only query, this round) | OK |
| 37 | fwapg_channel_width.md:43 | "**amd64 answers true on the same point**" | `image_probe_amd64.txt` probes 17046241, 700244339, 700277597 only; 17060680 is in no log, script or findings entry | **WIDER**: unmeasured (finding 2) |
| 38 | fwapg_channel_width.md:43 | "an arm64 build leaves 2,840 …"; fwapg#60 "recovered 2,835 … (one measurement)"; "on amd64 it answers true on the three points probed" | `postconditions.txt` 2,840 on both arm64 builds; findings.md:118; `image_probe_amd64.txt` | OK |
| 39 | test-frs_near_river.R:187-189 | "GEOS 3.11 **and later** return the line" | 3.11.1, 3.12.2, 3.13.1 on arm64 | **WIDER** (finding 4) |
| 40 | test-frs_network_features-local.R:17-19 | "22 of 50,417 and 22 of 51,698"; "Counted on the full province … 2026-11-24" | `answer_pairs_5432.tsv` (4,907,441 segments, 246 groups) | OK |

## Findings

- **[severity: bug]** docker/README.md:36-37 and :129-130 ("Restart after stop", "Managing data"). In a second instance, `docker compose` follows the exported project, but these lines name the first instance by literal. The README's own recipe (:98-102) exports `COMPOSE_PROJECT_NAME`, `COMPOSE_FILE` and `FRESH_DB_DATA=./postgres-data-2`, "so every later `docker compose` in that shell" reaches the second. In that shell, "Stop and delete all data" (`docker compose down -v; rm -rf postgres-data`) has three effects. `down -v` stops the second and leaves its data, because a bind mount is not a volume. `rm -rf postgres-data` deletes the **first** instance's data directory, the default `FRESH_DB_DATA`, and the first may be running at the time. The second's `postgres-data-2` survives. The README never says how to delete a second instance, so this is the recipe a reader reaches for. The same split affects "Restart after stop": line 33 starts the second, while lines 36-37 (`docker exec fresh-db …`) check the first and report it healthy. The section says the second instance is meant to run "beside the one you use" in the same `docker/` directory, so the first's `postgres-data/` is right there. These lines predate the branch, but the branch made the data directory and container name variables and added a shell context in which the literals and the compose commands point at different instances. Fix: write the paths and names through the same variables (`rm -rf "${FRESH_DB_DATA:-./postgres-data}"`, `docker exec "${FRESH_DB_CONTAINER:-fresh-db}" …`), or say in "A second instance" how to remove it (`docker compose down; rm -rf postgres-data-2`) and to leave the shell (a new shell, not a partial `unset`: a leftover exported `FRESH_DB_IMAGE` outranks the first instance's `docker/.env` pin).
  - **Rule:** none (candidate: "every command one documented workflow runs selects its target through the same channel")

- **[severity: fragile]** research/fwapg_channel_width.md:43. "The one without (`linear_feature_id` 17060680) … `ST_Intersects` answers false on a database built on arm64; amd64 answers true on the same point (re-measured 2026-11-24 and 2026-11-26…)". The amd64 half was never measured for this point. `docker_image_probe.sh` copies and probes streams 17046241, 700244339 and 700277597 only, and `image_probe_amd64.txt` is the only amd64 run. 17060680 appears nowhere in the logs, the probe script, `findings.md` or `progress.md`; the commit that added the amd64 result (b4dc92c) speaks of "#304's points". On live I checked that 17060680 has the same shape as the three: its midpoint intersects 0 watershed polygons, is within 0 of 2, and has no lut row. So the inference is plausible, but the sentence reports a re-measurement that did not happen. It attributes three points' amd64 answer to a fourth, and the same sentence later correctly limits itself to "the three points probed". Fix: "amd64 answers true on three other points of the same shape (`image_probe_amd64.txt`)", or add 17060680 to the probe and re-run on amd64. Separately, the file's header line 3 gives one date and this bullet gives two.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** docker/README.md:109 and docker/docker-compose.yml:24-25. The old image's GEOS "returns an empty intersection for a line lying wholly inside a box" (the compose header has the same sentence without "wholly"). The defect measured is narrower: an **exactly vertical** line. `research/fwa_downstream_walk.md:130`, which these lines compress, says "an exactly vertical line" and "slanted lines are fine". `test-frs_near_river.R` keeps its row slanted (x = 990) precisely because a slanted line works on 3.9.0. As written, the README tells a reader on a 3.9.0 database (fwapg upstream's image, per the same paragraph) that every contained-line intersection is wrong. That over-reports the defect and loses the workaround the test relies on. Fix: "for an exactly vertical line lying inside a box".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** tests/testthat/test-frs_near_river.R:187-189 ("GEOS 3.11 and later return the line"), and R/frs_lake_fetch.R:13-14, R/frs_wetland_fetch.R:13-14, R/frs_watershed_at_measure.R:28 with their man pages ("3.11 and 3.12 or later give different vertices" / "3.11 and 3.12 or later do"). Round 1 removed "later versions repeat" from the roxygen because only 3.11.1, 3.12.2 and 3.13.1 were measured. These are the same unbounded "later" over the same three versions (arm64, `image_probe.txt`), and round 1's fix did not reach them. The test comment is the one that round 1's remedy names exactly. The roxygen one is shipped documentation and asserts that every GEOS after 3.13 gives 3.12's vertices rather than 3.11's. Fix: "3.11.1, 3.12.2 and 3.13.1 return the line (arm64)" in the test, and "3.11 and 3.12 to 3.13 give different vertices" in the roxygen.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** R/frs_watershed_at_measure.R:24-25 (and man/frs_watershed_at_measure.Rd:35-36), and research/fwa_fetch_determinism.md:48. The roxygen says the function "returns the same polygon on every call (measured on GEOS 3.11 to 3.13 …)". The research file concludes that "on `docker/`'s image since #324 … one database returns one polygon". The measurement behind both is one lake (Tahtsa Reach) at `simplify_m = 100`, 20 calls, through bare `ST_SimplifyPreserveTopology` and `frs_lake_fetch()`, on arm64 only (`image_probe.txt`, `simplify_repeat_5433.txt`). `frs_watershed_at_measure()` was never repeated, and neither was its subbasin path (`ST_Difference`, then simplify). "Measured" next to this function's parameter reads as if it had been. "Every call" and "one polygon" generalise one polygon and one tolerance to every input. The 3.9.0 variation was found on that same single polygon, so one polygon was enough to show variation, not enough to show its absence. The lake and wetland roxygen ("3.11 to 3.13 repeat") and research row 30 ("3.11.1 … return the line") leave out the architecture. Architecture changes a GEOS-stack answer at a fixed version (`ST_Intersects` on the #304 points), so the qualifier matters. Fix: in the roxygen, "repeated on one lake polygon at 100 m on GEOS 3.11 to 3.13 (arm64)"; in the research file, "the Tahtsa Reach probe repeats on `docker/`'s image".
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies" ; code-check.md "A fixture that cannot reach the failure mode"

## Round 2 fixes checked

- The README now has every second-instance command name its files through `COMPOSE_FILE`, and "set `COMPOSE_FILE=docker-compose.yml`, never leave it unset" replaces "drop". The compose header's example names `COMPOSE_FILE=docker-compose.yml` and exports `FRESH_DB_IMAGE` in the prefix. Both are correct for the commands they show (A table rows 6, 7 and 12). The defect above is in the README's other sections, not in the recipe.
- The `frs_watershed_at_measure` parenthetical is narrowed to 3.11 to 3.13 and arm64 3.9.0. Finding 5 is about the population and the word "measured", not the version range.
- fwapg#60's 2,835 is now "on the arm64 build (one measurement)" and the amd64 clause is limited to the three probed points. Correct. Finding 2 is an earlier clause of the same sentence, which round 2's fix did not touch.
- No host names, tunnels, home paths or private repo names in the added lines.
