## Outcome

`docker/load.sh` stage 1 ran fwapg's `db/create.sh`, which smnorris/fwapg#193 replaced with `db/schema.sql` (a `pg_dump --schema-only`). Stage 1 now checks that `schema.sql` exists (naming the layout change if not), runs it, and sets the database `search_path` to `public,whse_basemapping,usgs,hydrosheds`. The issue did not name that last step: `create.sh` used to set it, a pg_dump does not carry database settings, upstream moved it into its own db image, and fwapg's function bodies call each other unqualified (so does fresh, e.g. `fwa_upstream()`). The #68 workaround is gone because `schema.sql` defines both interval functions, so #68 closes too. The plan review found two things along the way. The local fwapg checkout was 22 commits stale, so attempt 1 was stopped and re-run on a worktree at `origin/newgraph`. And stage 4 (`--bcfishobs`) is broken separately: it runs `make all`, and bcfishobs has had no Makefile since `ba52e62`. A follow-up issue is drafted.

## Measurement

- Full loader run into a scratch DB (`fwapg_253`, template1, in the running fresh-db) from fwapg `b010209`: exit 0 in 5 h 52 min, network-bound at roughly 0.4 MB/s from the BC object store. Disk 70 → 28 GB free at peak (DB 40 GB), back to 68 GB after the drop.
- Against the live `fwapg`:
  - identical `search_path`;
  - 14 key tables row-for-row equal, except channel width (+12 of 4.9 M) and order parent (−1 of 1.5 M);
  - the fwapg#9 tables equal (48,716; 40,524,444);
  - `fwa_downstreamtrace` 1,567 rows / 590,498 m on both;
  - fresh's unqualified `fwa_upstream()` 8,876 on both.
- **`whse_basemapping.fwa_watershedatmeasure()` errors on every non-lake point** (`relation "exbc" does not exist`). This is fwapg's own regression from `3c43bdd` (Xborder, 2026-01-15), carried verbatim into `schema.sql`; the live DB predates it. The `postgisftw` copy and the lake path work. fresh's `frs_watershed_at_measure()` calls the broken copy, so a DB rebuilt with this loader from current fwapg has it broken until upstream fixes it. Tracked in NewGraphEnvironment/fwapg#1, whose body was corrected from "cross-border points" to "every non-lake call".
- Tests: 1487 pass, 0 fail, 3 skip. `/code-check branch`: rounds 1–3 Clean. Round 4, on the post-run edits, found one fragile probe path inside its own fix; the loop ended by testing all four of `probe()`'s output paths.

## Evidence

`data-raw/logs/docker_load_253/` (attempt 1 under `attempt1_*`)

Closed by: PR (see branch `253-docker-load-sh-calls-fwapg-s-db-create-s`)
