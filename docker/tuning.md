# PostgreSQL Tuning

Tuning notes for the local Docker fwapg instance. Settings in `docker-compose.yml` are tuned for the development machine — adjust for your hardware.

## Current machine

- Apple M4 Max Pro
- 128 GB RAM
- 16 cores

## Settings rationale

| Setting | Value | Rule of thumb |
|---------|-------|---------------|
| `shared_buffers` | 32GB | ~25% of RAM |
| `effective_cache_size` | 96GB | ~75% of RAM (tells planner about OS cache) |
| `work_mem` | 2GB | Per-operation sort/hash budget. High because fresh queries do large joins and ltree comparisons |
| `maintenance_work_mem` | 4GB | Faster index builds, VACUUM ANALYZE |
| `wal_buffers` | 64MB | Scales with shared_buffers |
| `max_parallel_workers_per_gather` | 8 | Cores per query — aggressive for single-user dev |
| `max_parallel_workers` | 14 | Leave 2 cores for OS/Docker |
| `max_worker_processes` | 16 | Match core count |
| `shm_size` | 36gb | Must exceed shared_buffers (Docker constraint) |
| `random_page_cost` | 1.1 | SSD: random reads ≈ sequential. Default 4.0 (spinning rust) over-prices index scans, biases planner toward seq scans |
| `effective_io_concurrency` | 200 | SSD/NVMe: hundreds of concurrent requests. Default 1 under-issues prefetch on bitmap heap scans |
| `temp_buffers` | 64MB | Per-session temp-table memory. Default 8MB spills working tables (per-WSG segments, breaks, scratch) to disk gratuitously on a 128 GB box |

## SSD assumption

All NewGraph hosts run on SSD (M4 NVMe, M1 Colima virtiofs over APFS,
cypher DO block storage). The `random_page_cost`,
`effective_io_concurrency`, and `temp_buffers` defaults above bias the
planner toward index scans for segment-keyed lookups (the
`WHERE blue_line_key = … AND drm <= …` against `streams_breaks` hot
path in link's pipeline). Out-of-the-box PostgreSQL defaults (4.0 / 1
/ 8MB) are calibrated for spinning rust and are wrong for any modern
host. Don't lower these without a spinning-disk reason.

**M1/cypher hosts use a docker-compose override file.** Compose merges
override `command:` lists by **replacing** the base, not by appending —
so any `-c` flags added here must also be added to the M1/cypher
override (tracked in the rtj repo). Forgetting this silently leaves
the 32 GB hosts on PostgreSQL defaults.

## Scaling for other machines

**General formula:**

```
shared_buffers = RAM * 0.25
effective_cache_size = RAM * 0.75
work_mem = 1-2GB (fresh workload is join-heavy)
maintenance_work_mem = 2-4GB
max_parallel_workers = cores - 2
max_parallel_workers_per_gather = cores / 2
max_worker_processes = cores
shm_size = shared_buffers + 4GB
```

**Smaller machine (32GB RAM, 8 cores):**

```yaml
shm_size: 12gb
shared_buffers: 8GB
effective_cache_size: 24GB
work_mem: 1GB
maintenance_work_mem: 2GB
max_parallel_workers_per_gather: 4
max_parallel_workers: 6
max_worker_processes: 8
```

## Verifying settings

```bash
docker compose exec db psql -U postgres -d fwapg -c "SHOW shared_buffers; SHOW work_mem; SHOW effective_cache_size;"
```

## Applying changes

Settings live in `docker-compose.yml` command args. Restart to apply:

```bash
docker compose down
docker compose up -d db
```

Data persists in `postgres-data/` — no reload needed.
