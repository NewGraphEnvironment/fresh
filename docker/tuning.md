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
