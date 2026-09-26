# Progress — frs_db_conn(): default to standard libpq env vars instead of PG_*_SHARE (#213)

## Session 2026-09-26

- Plan-mode exploration — phases approved by user
- Created branch `213-frs-db-conn-default-to-standard-libpq-en` off main
- Scaffolded PWF baseline from issue #213 with approved phases
- Next: start Phase 1
- Phase 1: resolver unit tests written in `test-frs_db_conn.R` (one-function-one-file, not test-utils.R); old stop-on-missing block removed from test-utils.R. Red: `.frs_state` / `.frs_conn_resolve` not found.
- Phase 2: `.frs_conn_resolve()` + `.frs_state` in R/frs_db_conn.R (co-located, not utils.R); frs_db_conn() NULL defaults. Live: bare conn → localhost:5432/fwapg silently; SHARE-only env → message once, connects.
