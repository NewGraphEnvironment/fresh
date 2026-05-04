# Task: pg tuning — SSD planner-cost defaults in docker-compose.yml (#199)

`docker/docker-compose.yml` doesn't set `random_page_cost` or
`effective_io_concurrency`, so postgres falls through to PostgreSQL
defaults of `4.0` and `1` — both calibrated for spinning rust. All
NewGraph hosts run on SSD (M4 NVMe, M1 Colima virtiofs over APFS,
cypher DO block storage). With `random_page_cost=4`, the planner
systematically biases away from index scans for segment-keyed lookups
in link's pipeline (`WHERE blue_line_key = … AND drm <= …` against
`streams_breaks` is the hot path).

Verified on M4 + M1 + cypher (2026-05-04) — all three show
`random_page_cost=4`, `effective_io_concurrency=1`, `temp_buffers=8MB`.

## Phase 1: Add SSD planner-cost flags to docker-compose.yml
- [x] Append to `db.command` block in `docker/docker-compose.yml`:
  - `-c random_page_cost=1.1`
  - `-c effective_io_concurrency=200`
  - `-c temp_buffers=64MB`
- [x] Restart local Docker DB (`docker compose down && docker compose up -d db`)
- [x] Verify via `SHOW random_page_cost; SHOW effective_io_concurrency; SHOW temp_buffers;`
  (verified live: `random_page_cost=1.1`, `effective_io_concurrency=200`, `temp_buffers=64MB`)

## Phase 2: Document in tuning.md
- [x] Add three rows to the "Settings rationale" table
  (`random_page_cost`, `effective_io_concurrency`, `temp_buffers`) with
  SSD justification per setting
- [x] Add a short "SSD assumption" note: all NewGraph hosts run on SSD
  (M4 NVMe, M1 Colima virtiofs over APFS, cypher DO block storage),
  these defaults bias the planner toward index scans for segment-keyed
  lookups in link's pipeline
- [x] Cross-reference the companion rtj issue for the M1/cypher override
  file — override `command:` REPLACES base under docker-compose merge
  semantics; same change must land in both

## Phase 3: Verify and PR
- [ ] `/code-check` on the diff
- [ ] Push branch, open PR with `Closes #199`
- [ ] Note benchmark verification is a post-merge step (≥10% median
  per-WSG wall reduction at unchanged segment count) — owner runs from
  M4 against `data-raw/logs/provincial_default_extrabreaks/<TS>_per_wsg_times.csv`
  baseline (2026-05-04)

## Validation
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion
