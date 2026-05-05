# Findings — pg tuning: SSD planner-cost defaults (#199)

## Issue context

### Problem

`fresh/docker/docker-compose.yml` doesn't set `random_page_cost` or
`effective_io_concurrency`, so postgres falls through to PostgreSQL
defaults of `4.0` and `1` — both calibrated for spinning rust. All
NewGraph hosts run on SSD (M4 NVMe, M1 Colima virtiofs over APFS,
cypher DO block storage). With `random_page_cost=4`, the planner
systematically biases away from index scans for segment-keyed lookups
in link's pipeline (`WHERE blue_line_key = … AND drm <= …` against
`streams_breaks` is the hot path).

Verified on M4 + M1 + cypher today (2026-05-04) — all three show
`random_page_cost=4`, `effective_io_concurrency=1`, `temp_buffers=8MB`.

### Proposed

Add to the `db.command` block in base `docker-compose.yml`:

```yaml
-c random_page_cost=1.1
-c effective_io_concurrency=200
-c temp_buffers=64MB
```

Document in `fresh/docker/tuning.md` alongside the existing memory
rationale: SSD cost values, why they matter for link's segment-heavy
SQL.

### Verification

Post-merge, M4 reruns one of link's provincial-style runs. Compare
per-WSG wall times in `data-raw/logs/<TS>_per_wsg_times.csv` against
today's baseline (2026-05-04 `default_extrabreaks` run,
`data-raw/logs/provincial_default_extrabreaks/<TS>_per_wsg_times.csv`).
Acceptance: median per-WSG wall reduced by ≥ 10 % at unchanged segment
count.

### Cross-ref

Companion rtj issue for the M1/cypher override file — the override's
`command:` list REPLACES the base under docker-compose's merge
semantics, so settings added here don't propagate to the 32 GB hosts.
Same change must land in both.

## Setting-by-setting rationale

### `random_page_cost = 1.1`

PostgreSQL default is `4.0` — the cost ratio for a random vs
sequential page read on spinning rust (~4× slower for random I/O).
On SSD, random reads are nearly as cheap as sequential. PostgreSQL
docs and tuning consensus recommend `1.1` to `1.5` for SSD. With the
default, the planner systematically over-prices index scans and
prefers seq scans even when an index would be faster — exactly the
wrong bias for segment-keyed lookups.

### `effective_io_concurrency = 200`

PostgreSQL default is `1`. This setting tells the planner how many
concurrent I/O requests the storage can usefully serve, used to drive
prefetch on bitmap heap scans. SSDs (especially NVMe) handle hundreds
of concurrent requests trivially — `200` is the standard recommendation
for SSD. Value of `1` causes the planner to under-issue prefetches and
underestimate bitmap-scan throughput.

### `temp_buffers = 64MB`

PostgreSQL default is `8MB` — per-session memory for temporary tables.
Bumping to `64MB` lets short-lived temp/working tables live in RAM
instead of spilling to disk. fresh/link pipelines build per-WSG temp
tables (segments, breaks, working scratch) that are read repeatedly
within a session; spilling these to disk is gratuitous on a dev box
with 128 GB RAM.

## Repo state

- `docker/docker-compose.yml:21-35` — current `db.command` block has
  memory + parallelism flags but no I/O cost flags
- `docker/tuning.md` — has "Settings rationale" table and a "Scaling
  for other machines" recipe; new flags are global (not RAM-scaled),
  no scaling change needed
