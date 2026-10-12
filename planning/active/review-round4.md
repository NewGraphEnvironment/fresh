# Code-check round 4 — docker/load.sh comment + postconditions.sh probe()

Reviewed: round4.diff (uncommitted), full `docker/load.sh` stage 1, full
`data-raw/logs/docker_load_253/postconditions.sh`, `postconditions.txt`,
fwapg `origin/newgraph` @ 9a64ce3 (`db/migrate.sh`, `db/schema.sql`, `db/README.md`).

## Findings

- **[severity: fragile]** data-raw/logs/docker_load_253/postconditions.sh:42 — `probe()` keeps
  only a line starting `ERROR` or containing a tab, and `|| true` swallows the rest. Two cases
  therefore print nothing at all and the probe silently vanishes from the evidence:
  1. a failure that is not a SQL error: `psql: error: connection to server ... FATAL: database
     "fwapg_253" does not exist`, or docker's `Error response from daemon: ...`. Before this diff
     `q` aborted the script loudly under `set -e`; now each probe drops out and the section is an
     empty header (exactly what a re-run would produce today, since fwapg_253 has been dropped);
  2. a set-returning probe that returns zero rows (`fwa_watershedatmeasure` for either point, or
     the postgisftw copy). The aggregate probes (`fwa_downstreamtrace`, `fwa_upstream`) always
     return a row, these three do not.

  The committed `postconditions.txt` is complete (5 lines per DB, all printed), so the evidence
  recorded is not affected; the defect bites on a re-run. Fix: make a miss print something, e.g.
  `probe() { local out; out=$(q "$1" "$2" 2>&1) || true; printf '%s\n' "$out" | grep -m1 -E '^ERROR|<TAB>' || printf 'NO ROW\t%s\n' "$(printf '%s' "$out" | head -1)"; }`
  (or widen the pattern to `^(ERROR|psql: error|Error)` and add a label to the fallback).

## Checked and fine

- Tab in the grep pattern is a literal tab inside single quotes (`cat -A` shows `^I`).
- `grep -m1` under `pipefail`: an early grep exit/SIGPIPE or psql's exit 1 makes the pipeline
  non-zero, absorbed by `|| true`; the ERROR line itself is still printed. Correct.
- psql `-c` errors arrive on stderr as `ERROR:  ...` and `2>&1` routes them to grep; the
  recorded `ERROR:  relation "exbc" does not exist` confirms the path works.
- load.sh comment, every factual claim verified against fwapg origin/newgraph @ 9a64ce3:
  - "fwapg ships no db/migrations yet": `ls-tree db` = README.md, create_migration.sh,
    migrate.sh, schema.sql. True.
  - "migrate.sh counts from fwapg.db_version": it bootstraps `fwapg.db_version` with tag `'0'`
    if absent and applies every `migrations/[0-9]*__*.sql` whose timestamp > the latest tag. True.
  - "which schema.sql does not create": schema.sql has `CREATE SCHEMA fwapg;` but no
    `db_version` anywhere. True.
  - "so it would re-apply what the dump already holds": follows, since on a fresh schema.sql
    install every migration file present is pending. (fwapg's db/README says schema.sql is
    regenerated after migrations accumulate and committed "alongside any remaining migration
    files", so whether folded migrations get deleted is fwapg's future practice; the comment's
    "check how it expects them applied" already hedges this.)

## Context, not a finding in this diff

The fwapg_253 `ERROR: relation "exbc" does not exist` is genuine and is an upstream defect in
fwapg's `db/schema.sql`, not a search_path problem: in `whse_basemapping.fwa_watershedatmeasure`
(schema.sql:3630) the non-lake branch's `agg` CTE selects `FROM exbc` (schema.sql:3928-3931)
but defines no `exbc` CTE; only the lake branch does (schema.sql:4051). The postgisftw copy
defines `exbc` in both branches (schema.sql:1454, 1635), which is why it and the lake probe
succeed. The live `fwapg` DB predates this dump, so it does not show the error.
