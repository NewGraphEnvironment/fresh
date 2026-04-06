# Findings

## frs_habitat current flow (to replace)

1. Load params from CSV
2. Build species spec per WSG via frs_wsg_species
3. Phase 1: frs_habitat_partition per WSG (extract + enrich + gradient breaks + habitat breaks)
4. Phase 2: frs_habitat_species per (WSG, species) (copy table + break_apply + classify)
5. Phase 3: persist via to_prefix
6. Phase 4: cleanup

## New flow

1. Load params from CSV
2. Build species spec per WSG
3. Per WSG (parallel via mirai):
   a. Generate gradient barriers at unique access thresholds
   b. frs_network_segment (extract + enrich + break at barriers + user sources)
   c. frs_habitat_classify (long-format, species-specific accessibility)
   d. Append to to_streams (if provided)
   e. Cleanup working tables
4. Done — no separate Phase 2/3

## Key simplification

Old: per-species tables with duplicated geometry, separate access + habitat breaks
New: one streams table per WSG, one habitat table (long format), classify by attribute

## Worker isolation

Each mirai worker:
- Opens own DB connection (password param)
- Creates working.streams_{wsg} + working.streams_{wsg}_breaks
- Writes to to_habitat (shared table — needs row-level isolation via species_code + id_segment)
- Appends to to_streams (shared table — needs WSG isolation via watershed_group_code)

Potential conflict: two workers writing to to_habitat simultaneously.
PG handles concurrent INSERTs fine — no locking issue for appends.
The DELETE (idempotent cleanup) could conflict if two workers process same WSG — but we dedupe WSGs before dispatching so this won't happen.
