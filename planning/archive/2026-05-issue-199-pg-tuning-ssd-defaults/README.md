## Outcome

Added SSD-friendly planner-cost defaults to `docker/docker-compose.yml`: `random_page_cost=1.1`, `effective_io_concurrency=200`, `temp_buffers=64MB`. PostgreSQL ships with values calibrated for spinning rust (4.0 / 1 / 8MB), which biased the planner away from index scans on segment-keyed lookups (the `WHERE blue_line_key = … AND drm <= …` hot path in link's pipeline). Documented in `docker/tuning.md` with per-setting rationale and a note that the M1/cypher docker-compose override file (tracked separately in rtj) needs the same flags — compose merges override `command:` lists by replacing the base, not appending.

## Closed By

PR #200, released as v0.27.6.

## Verification

Live `SHOW` confirms 1.1 / 200 / 64MB after restart. Post-merge benchmark verification (≥ 10 % median per-WSG wall reduction at unchanged segment count) is a separate step the owner runs against the 2026-05-04 baseline (`data-raw/logs/provincial_default_extrabreaks/<TS>_per_wsg_times.csv`).
