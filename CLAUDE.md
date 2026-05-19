# fresh

Freshwater Referenced Spatial Hydrology. A composable stream network
modelling engine. Query and extract stream networks, classify habitat by
gradient and channel width, segment networks at barriers and break
points, aggregate features upstream or downstream, and run multi-species
habitat modelling with parallel workers.

## Repository Context

**Repository:** NewGraphEnvironment/fresh **Primary Language:** R
(package) **Version:** 0.31.0 **License:** MIT

## Ecosystem

| Package | Role |
|----|----|
| **fresh** | Stream network modelling engine (this package) — segment networks, classify habitat, cluster, aggregate |
| [link](https://github.com/NewGraphEnvironment/link) | Feature-to-network interpretation — load and validate override CSVs, score and prioritize crossings, build per-species barrier skip lists, orchestrate bcfishpass-reproducing six-phase pipelines via `lnk_pipeline_*()` + `lnk_config()` |
| [flooded](https://github.com/NewGraphEnvironment/flooded) | Delineate floodplain extents from DEMs and stream networks |
| [drift](https://github.com/NewGraphEnvironment/drift) | Track land cover change within floodplains over time |
| [fly](https://github.com/NewGraphEnvironment/fly) | Estimate airphoto footprints and select optimal coverage for a study area |
| [diggs](https://github.com/NewGraphEnvironment/diggs) | Interactive explorer for fly airphoto selections (Shiny app) |

**Pipelines:**

- Fish habitat / connectivity: **link → fresh**. link’s
  `lnk_pipeline_*()` helpers interpret features (crossings,
  observations, falls, user-definite barriers, habitat confirmations)
  and produce the `break_sources` and `barrier_overrides` table that
  feed
  [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md).
  Without link, fresh still runs on any break sources you construct
  yourself.
- Land cover change: fresh (network) → flooded (floodplains) → drift
  (land cover change).

## Architecture

Legend: `[link]` = building block used directly by `link` (called by
`lnk_pipeline_*()` rather than via
[`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)).

    R/
      fresh-package.R            — package-level doc, imports
      frs_db_conn.R              — DB connection via PG_*_SHARE env vars
      frs_db_query.R             — execute SQL, return sf
      frs_habitat.R              — orchestrator: multi-WSG/AOI habitat pipeline
      frs_habitat_classify.R     — long-format habitat classification per species [link]
      frs_network_segment.R      — domain-agnostic network segmentation
      frs_feature_find.R         — locate point features on network
      frs_feature_index.R        — upstream/downstream relationship indexing
      frs_break.R                — gradient break detection (island method);
                                   exports frs_break_find/frs_break_apply/
                                   frs_break_validate [link]
      frs_barriers_minimal.R     — per-flowpath minimal barrier reduction [link]
      frs_classify.R             — segment classification by attributes/breaks
      frs_categorize.R           — bin continuous attributes to categorical classes
      frs_cluster.R              — connectivity clustering (rearing/spawning linkage) [link]
      frs_extract.R              — extract streams to working table
      frs_clip.R                 — clip a table to an AOI
      frs_aggregate.R            — upstream/downstream feature aggregation [link]
      frs_col_join.R             — join attributes (channel width, discharge) [link]
      frs_col_generate.R         — recompute gradient from geometry [link]
      frs_network.R              — unified multi-table network traversal
      frs_network_upstream.R     — upstream network query (ltree)
      frs_network_downstream.R   — downstream network query (ltree)
      frs_network_prune.R        — prune network to connected-waterbody constraints
      frs_waterbody_network.R    — build the waterbody-only network subset
      frs_watershed_at_measure.R — watershed polygon at a blue-line position
      frs_watershed_split.R      — split a watershed polygon at a position
      frs_point_snap.R           — snap points to nearest stream
      frs_point_locate.R         — locate point on stream network
      frs_stream_fetch.R         — fetch stream segments
      frs_lake_fetch.R           — fetch lakes
      frs_wetland_fetch.R        — fetch wetlands
      frs_order_filter.R         — filter on stream order / order_parent
      frs_params.R               — load species habitat parameters
      frs_wsg_species.R          — species presence per watershed group
      frs_edge_types.R           — FWA edge type lookup
      utils.R                    — internal helpers
    tests/testthat/              — unit tests
    inst/extdata/                — bundled CSVs (falls, crossings, params, species)
    data-raw/                    — data refresh scripts
    docker/                      — local fwapg Docker setup
    vignettes/                   — .Rmd.orig source, .Rmd pre-knitted output

## Key Patterns

- All exported functions prefixed `frs_`, named noun-first:
  [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md),
  [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md),
  [`frs_feature_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_feature_find.md)
- **Two layers:**
  - **Generic primitives (domain-neutral):**
    [`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md),
    [`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md),
    [`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md),
    [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md),
    [`frs_barriers_minimal()`](https://newgraphenvironment.github.io/fresh/reference/frs_barriers_minimal.md),
    [`frs_col_generate()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_generate.md),
    [`frs_col_join()`](https://newgraphenvironment.github.io/fresh/reference/frs_col_join.md),
    [`frs_aggregate()`](https://newgraphenvironment.github.io/fresh/reference/frs_aggregate.md),
    [`frs_cluster()`](https://newgraphenvironment.github.io/fresh/reference/frs_cluster.md).
    Classify on any attribute into any label column, break at any
    position, cluster by any rule. No assumptions about what’s being
    modelled.
  - **Fish-habitat wrappers (domain-coupled):**
    [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md),
    [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md),
    [`frs_params()`](https://newgraphenvironment.github.io/fresh/reference/frs_params.md).
    Output schema is fixed:
    `accessible / spawning / rearing / lake_rearing` booleans per
    `species_code`. Parameters YAML is species-keyed with
    `spawn / rear / spawn_connected` rule sections. For non-fish
    domains, compose the primitives on your own output schema rather
    than shoehorning through these wrappers.
- [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
  is the fish-workflow orchestrator — wraps
  [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md) +
  [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  with mirai parallel workers
- [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)
  is domain-agnostic — segments any network at any break points
- [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  produces long-format output: one row per segment × species, joined to
  geometry via `id_segment`
- `break_sources` with `label`, `label_col`, `label_map` for flexible
  network-referenced classification
- `label_block` controls which labels restrict access (default
  `"blocked"`, configurable — pass your own domain labels)
- `gate = FALSE` skips accessibility for raw habitat potential
- Direct SQL via DBI/RPostgres against fwapg PostgreSQL
- Returns sf objects for spatial results
- Requires PostgreSQL with fwapg (bcfishpass/bcfishobs optional,
  per-function)
- Vignette data cached in `inst/extdata/` with `update_gis` YAML param
  (FALSE = cached, TRUE = live DB)

## Dependencies

- **Runtime:** DBI, RPostgres, sf

- **Suggests:** mirai, tmap (\>= 4.0), gq, bookdown, knitr, rmarkdown

- **Database:** PostgreSQL with fwapg (local Docker or remote tunnel)

- **Connection:** Local Docker on port 5432 or SSH tunnel on 63333; see
  db-newgraph skill

- **R version:** targets R \>= 4.1. Do NOT use `%||%` (R 4.4+ only)
  without importing from `rlang`; current `Imports:` doesn’t include
  `rlang`. Use `if (is.null(x)) default else x` instead.

- **FWA User Guide ragnar store:** `data/rag/fwa_user_guide.duckdb`
  (gitignored, built locally). 171 chunks of GeoBC (2010) Freshwater
  Atlas User Guide — edge types, feature codes, watershed codes, stream
  network structure. Query:

  ``` r

  store <- ragnar::ragnar_store_connect("data/rag/fwa_user_guide.duckdb")
  results <- ragnar::ragnar_retrieve(store, "query", top_k = 5)
  DBI::dbDisconnect(store@con)
  ```

  Zotero source: parent key `S2EMGWR5`, attachment key `NC5QSXCI`.

## Testing on alternate hosts

Integration tests use
[`frs_db_conn()`](https://newgraphenvironment.github.io/fresh/reference/frs_db_conn.md)
which reads `PG_*_SHARE` env vars (`PG_HOST_SHARE`, `PG_PORT_SHARE`,
`PG_USER_SHARE`, `PG_PASS_SHARE`, `PG_DB_SHARE`). On dev machines those
are commonly wired in `~/.Renviron` to point at the SSH tunnel
(`localhost:63333`) for the bcfishpass-shared DB. R’s user `~/.Renviron`
overrides shell env, so a shell-level `export PG_PORT_SHARE=5432` does
NOT change what R sees.

To run fresh tests against a host’s **local** Docker fwapg (port 5432)
instead — useful when the tunnel is down, when the local box has a
byte-identical fwapg, or when offloading test runs from a busy machine
to a parallel host (e.g. m4 ↔︎ m1 on Tailscale):

``` r

# Inside R, before any frs_db_conn() call:
Sys.setenv(PG_HOST_SHARE = "localhost",
           PG_PORT_SHARE = "5432",
           PG_USER_SHARE = "postgres",
           PG_PASS_SHARE = "postgres",
           PG_DB_SHARE   = "fwapg")
testthat::set_max_fails(Inf)
devtools::test()
```

Or via `Rscript --no-environ` to skip user `~/.Renviron` entirely (then
shell-level `export` works).

**Note:** the local Docker fwapg typically has only the `fwapg` database
/ `whse_basemapping` schema. Tests that read the `bcfishpass` schema
(`bcfishpass.parameters_habitat_thresholds`, etc.) will fail without the
tunnel — those need the shared DB. Most habitat-pipeline tests use only
`whse_basemapping` and run fine off-tunnel.

Cross-host run pattern (m4 → m1 over Tailscale, e.g. when m4 is busy):

``` bash
# 1. Push the branch from m4 (the dev box)
git push -u origin <branch>

# 2. On m1: fetch + checkout + reinstall
ssh m1 'cd /Users/airvine/Projects/repo/fresh && \
        git fetch origin && git checkout <branch> && \
        Rscript -e "pak::pak(\"NewGraphEnvironment/fresh@<branch>\", upgrade = FALSE, ask = FALSE)"'

# 3. On m1: run tests with local-fwapg env override
ssh m1 'cd /Users/airvine/Projects/repo/fresh && Rscript -e "
  Sys.setenv(PG_PORT_SHARE = \"5432\", PG_USER_SHARE = \"postgres\",
             PG_PASS_SHARE = \"postgres\", PG_DB_SHARE = \"fwapg\",
             PG_HOST_SHARE = \"localhost\")
  testthat::set_max_fails(Inf); devtools::test()
" > /tmp/m1_fresh_test.log 2>&1 &'
```

## Naming Conventions

### Generated column names

- `id_*` prefix for fresh-generated identifiers: `id_segment`
  (sub-segment after breaking)
- FWA columns kept as-is: `linear_feature_id`, `blue_line_key`,
  `downstream_route_measure`, `wscode_ltree`, `localcode_ltree`
- Habitat classification columns are generic (not species-prefixed):
  `accessible`, `spawning`, `rearing`, `lake_rearing`. Species is a row
  value (`species_code`), not a column name.

### Parameter names

- `to`, `from` — complete DB table names (schema-qualified)
- `to_prefix` — table name prefix, suffixed by the function
  (e.g. `"fresh.streams"` → `fresh.streams_co`)
- `to_streams`, `to_habitat` — explicit output table names in
  [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
- `col_*` — column name mappings for flexible table schemas: `col_blk`,
  `col_measure`
- `break_sources` — list of break source specs with `table`, `where`,
  `label`, `label_col`, `label_map`, `col_blk`, `col_measure`

### Column-name vectors (`cols_` prefix)

Vectors of column names in internal code use `cols_` prefix so they
cluster in the RStudio environment pane and autocomplete:

- `cols_all` — all columns in a table
- `cols_carry` — columns to carry forward from parent
- `cols_split` — columns from the split/new geometry
- `cols_writable` — non-generated columns (can `INSERT INTO`)
- `cols_insert` — final column list for INSERT statement

### Function names

- `frs_noun_verb` pattern: `frs_network_segment`, `frs_point_snap`,
  `frs_stream_fetch`
- Pipeline orchestrators wrap exported building blocks:
  - [`frs_habitat()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat.md)
    wraps
    [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md) +
    [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
  - [`frs_network_segment()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_segment.md)
    wraps
    [`frs_extract()`](https://newgraphenvironment.github.io/fresh/reference/frs_extract.md) +
    [`frs_break_find()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_find.md) +
    [`frs_break_apply()`](https://newgraphenvironment.github.io/fresh/reference/frs_break_apply.md)
  - [`frs_habitat_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_habitat_classify.md)
    wraps
    [`frs_classify()`](https://newgraphenvironment.github.io/fresh/reference/frs_classify.md)
    per species

### Output table structure

- `{to_streams}` — one row per segment, geometry + base attributes +
  `id_segment`
- `{to_habitat}` — long format, one row per segment × species. Columns:
  `id_segment`, `species_code`, `accessible`, `spawning`, `rearing`,
  `lake_rearing`. No geometry.
- Views per species: `{to_streams}_co_vw` = join streams + habitat WHERE
  species_code = ‘CO’

## Technical notes

Small durable technical reference for internal behavior worth
remembering.

### Stream guards (`.frs_stream_guards()`, `.frs_snap_guards()`)

- `.frs_stream_guards()` = placeholder (999 wscode) + unmapped (NULL
  localcode) only
- `.frs_snap_guards()` excludes **only** edge type 1425 (subsurface
  flow). 1410 (network connector) is real wetland connectivity — NOT
  excluded (#52)
- `frs_point_snap(exclude_edge_types = ...)` exposes this as a parameter
  (default 1425, NULL = snap to everything)
- Placeholder / unmapped segments are never returned by `fwa_upstream` /
  `fwa_downstream` anyway (ltree traversal excludes them)

### Watershed family

- [`frs_watershed_at_measure()`](https://newgraphenvironment.github.io/fresh/reference/frs_watershed_at_measure.md)
  and
  [`frs_watershed_split()`](https://newgraphenvironment.github.io/fresh/reference/frs_watershed_split.md)
  share `@family watershed`
- [`frs_watershed_split()`](https://newgraphenvironment.github.io/fresh/reference/frs_watershed_split.md)
  preserves extra columns from input (e.g. `name_basin`)
- Stable IDs via `blk` / `drm` — never change regardless of point count

## Working Conventions

### Design principles — build functions, not workarounds

Four rules for fresh feature development:

1.  **Functions not hacks** — if the vignette needs a workaround, that’s
    a signal to update the function, add a param, or add a helper. The
    vignette IS the intended use case; optimize the API for it.
2.  **Network-agnostic** — fresh operates on networks, not just the
    Freshwater Atlas. Column names, table names, traversal functions
    should be configurable (via `.frs_opt()`). Don’t hardcode
    FWA-specific names. Think spyda compatibility.
3.  **Leverage PostgreSQL** — use generated columns, GiST indexes, CTEs,
    lateral joins. Understand what’s indexed and what’s not. Traversal
    on indexed tables only. Know when a view will hang vs a table will
    fly.
4.  **No painted corners** — before implementing, ask “does this work
    with a different network?” If not, abstract it.

**Why:** fresh is the operations layer for any spyda-built network. FWA
is just the first network. The API decisions made now set the pattern
for all future networks.

**How to apply:** when writing SQL or function signatures, use
`.frs_opt()` for table/column names. When traversing, always use the
indexed network table. When adding params, think “would this name/type
make sense for a LiDAR-derived channel network?”

### Test output — combine, don’t double-run

When running tests, pipe stderr to grep in the same command to avoid
running twice:

``` bash
Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5
```

For full error context:

``` bash
Rscript -e 'devtools::test()' 2>&1 | grep -E "(ERROR:|FAIL )" -A 10 | head -25
```

**Why:** integration tests against remote DB can take 30-60s. Running
once + grepping is much faster than running, seeing failures, running
again.

**How to apply:** use the combined pattern on every `devtools::test()`
call.

### Version tagging — bump freely, tag sparsely

Bump `DESCRIPTION` version with each feature merge, but don’t create git
tags on every bump. Tags are for milestones someone would pin to:
release announcements, dependency pins, SRED claim boundaries. Pre-1.0,
the semver contract hasn’t started — version numbers are cheap; tags are
noise.

**Why:** rapid tagging (v0.8.0 → v0.9.0 → v0.10.0 in days) creates
clutter with no consumers. PRs and commits document everything for SRED
— tags don’t add to that.

**How to apply:** `git tag` only when batching a coherent set of
features worth announcing. Version bumps in `DESCRIPTION` and `NEWS.md`
still happen per feature merge.

### Data generation — scripts in `data-raw/`, never ad-hoc

All cached test/vignette data must be regenerable via a script in
`data-raw/`. Never use ad-hoc `Rscript -e` commands for data
regeneration.

**Why:** reproducibility. The next person (or next-you on a new machine)
needs to be able to rebuild the data from source.

**How to apply:** before committing a cached `.rds` / `.gpkg` / `.tif`,
ensure a `data-raw/<name>.R` script that produces it exists. Example:
`data-raw/example_byman_ailport.R` generates all byman-ailport cached
data.

### Vignette `.Rmd.orig` pattern

- `.Rmd.orig` = source with live DB queries; `.Rmd` = pre-knitted cached
  version
- `params$update_gis` controls live vs cached: `TRUE` = hit DB, `FALSE`
  = use RDS
- Knit with:
  `params <- list(update_gis = TRUE); knitr::knit("vignettes/name.Rmd.orig", output = "vignettes/name.Rmd")`
- Copy figures: `cp figure/*.png vignettes/figure/`
- `subbasin-query` figure (`plot-subbasin-1.png`) gets accidentally
  deleted when wiping `vignettes/figure/` — always restore
- Bookdown cross-refs (`\@ref`) don’t work with pre-knit pattern — don’t
  use them in vignettes

# CI Monitoring

When this repo has GitHub Actions workflows, scan recent runs on session
start. Catches failed pkgdown deploys, broken vignette builds, and stale
citation regenerations that would otherwise linger until the user
manually checks.

## On Session Start

``` bash
gh run list --limit 5 --json status,conclusion,name,createdAt,databaseId \
  --jq '.[] | select(.conclusion == "failure")'
```

If any failures since the last visit, surface to the user before
starting other work:

> Workflow `<name>` failed `<time>` ago (run `<id>`). Investigate with
> `gh run view <id> --log-failed`. Fix or proceed with current task?

User decides; do not auto-fix.

## Particular Failures Worth Naming

- **pkgdown** — docs site on GitHub Pages broken
- **R-CMD-check** — package may not install
- **Vignette / build-vignettes** — vignette docs incomplete
- **update-citation-cff** — CITATION.cff stale

## Why This Matters

Without this scan, post-merge workflow failures linger until someone
(often the user) notices a stale docs site or a missing vignette. The
session-start sweep catches them on the first re-entry into the repo.

## Pairs with `/gh-pr-merge`

The skill watches workflows triggered by a fresh merge in real time —
that’s the targeted catch. This convention is the backstop for failures
that landed when no one was watching (merges via web UI, scheduled
triggers, manually-triggered workflows).

# Code Check Conventions

Structured checklist for reviewing diffs before commit. Used by
`/code-check`. Add new checks here when a bug class is discovered — they
compound over time.

## Shell Scripts

### Quoting

- Variables in double-quoted strings containing single quotes break if
  value has `'`
- `"echo '${VAR}'"` — if VAR contains `'`, shell syntax breaks
- Use `printf '%s\n' "$VAR" | command` to pipe values safely
- Heredocs: unquoted `<<EOF` expands variables locally, `<<'EOF'` does
  not — know which you need
- Pass-through-ssh args: `printf '%q'` escapes per-arg so workload paths
  with spaces / quotes / metacharacters survive the local-shell →
  ssh-argv → remote-shell round-trip. Without it,
  `ssh host 'cmd' "$path"` joins args with spaces on remote and
  re-parses, losing argument boundaries.

### Heredoc precedence in pipelines

- `cmd1 | cmd2 <<EOF` — the heredoc binds to `cmd2` (the rightmost
  simple command). If you intended `cmd1` to receive it, put `<<EOF` on
  cmd1 explicitly: `cmd1 <<EOF | cmd2`.
- Symptom when wrong: ssh body silently echoed by tee/cat/etc, ssh side
  gets empty stdin, exits 0 (or near-0) without doing anything. Caught
  the hard way 2026-05-01 in cypher_restore-fwapg.sh.

### pipefail with ssh+tee

- `set -eu` does NOT propagate exit codes through pipelines.
  `ssh ... | tee log` returns tee’s exit (always 0 for healthy tee),
  masking ssh failure.
- Use `set -euo pipefail` for any script that pipes a meaningful command
  into tee/cat/grep/etc. Or check `${PIPESTATUS[0]}` explicitly.
- Symptom when wrong: task notifications report “exit 0 / completed”
  while remote work was actually skipped or errored.

### Paths

- Hardcoded absolute paths (`/Users/airvine/...`) break for other users
- Use `REPO_ROOT="$(cd "$(dirname "$0")/<relative>" && pwd)"`
- After moving scripts, verify `../` depth still resolves correctly
- Usage comments should match actual script location

### Silent Failures

- `|| true` hides real errors — is the failure actually safe to ignore?
- Empty variable before destructive operation (rm, destroy) — add guard:
  `[ -n "$VAR" ] || exit 1`
- `grep` returning empty silently — downstream commands get empty input

### Process Visibility

- Secrets passed as command-line args are visible in `ps aux`
- Use env files, stdin pipes, or temp files with `chmod 600` instead

## Cloud-Init (YAML)

### ASCII

- Must be pure ASCII — em dashes, curly quotes, arrows cause silent
  parse failure
- Check with: `perl -ne 'print "$.: $_" if /[^\x00-\x7F]/' file.yaml`

### YAML flow-mapping in runcmd

- Any runcmd item containing both `{` and `:` is at risk of being parsed
  as a YAML flow-mapping (dict), not a literal string. Cloud-init’s
  shellify hits a non-string and throws TypeError, **aborting all
  subsequent runcmd steps silently** while `final_message` still fires.

- Don’t write: `- test -s /file || { echo "FATAL: ..." }` — the `:`
  inside braces makes YAML see a dict.

- Do write: use `- |` block scalar with explicit `if/then/fi`:

  ``` yaml
  - |
    if [ ! -s /file ]; then
      echo "FATAL: ..." >&2
      exit 1
    fi
  ```

- Validate post-edit:
  `python3 -c "import yaml; runcmd=yaml.safe_load(open('cloud-init.yaml').read().split(chr(10),1)[1])['runcmd']; print([type(x).__name__ for x in runcmd if not isinstance(x,str)] or 'all strings')"`.
  If the output is anything other than `all strings`, the runcmd will
  fail.

### State

- `cloud-init clean` causes full re-provisioning on next boot — almost
  never what you want before snapshot
- Use `tailscale logout` not `tailscale down` before snapshot
  (deregister vs disconnect)
- Wipe `/var/lib/tailscale/*` before snapshot too — `tailscale logout`
  deauthorizes server-side but local node identity blob persists in
  tailscaled.state. Snapshot restored elsewhere inherits prior key
  material until `tailscale up` runs again.
- Wipe `/etc/ssh/ssh_host_*` before snapshot — otherwise droplets
  spawned from the same image share host identity.

### Template Variables

- Secrets rendered via `templatefile()` are readable at
  `169.254.169.254` metadata endpoint
- Acceptable for ephemeral machines, document the tradeoff
- Heredocs in runcmd that write secrets: `<<'EOF'` (quoted) prevents
  bash from re-expanding `$X` sequences in already-substituted
  credential strings. AWS keys rarely contain `$` but base64-padded
  secrets might.

### Repo + key install ordering

- `apt-key adv --keyserver` is deprecated on Ubuntu 24.04 noble —
  silently fails AND APT ignores resulting keyring. Use
  `gpg --dearmor` + `signed-by=` keyring file pattern.
- Repo .list files in `write_files:` trigger the implicit
  `package_update` BEFORE runcmd installs the keyring → first apt-get
  update fails with NO_PUBKEY. Put the repo line in runcmd alongside the
  key install, not in write_files.

### Cloud-init users vs DO SSH key injection

- DO injects `ssh_key_ids` only into `/root/.ssh/authorized_keys`
  (cloud-init’s `cc_ssh` module). Cloud-init `users:` block with
  `ssh_authorized_keys: []` does NOT pick those up.

- Non-root users that need SSH access must copy from root’s keys in
  runcmd:

  ``` yaml
  - mkdir -p /home/<user>/.ssh
  - cp /root/.ssh/authorized_keys /home/<user>/.ssh/authorized_keys
  - chown -R <user>:<user> /home/<user>/.ssh
  ```

- Guard with `test -s /root/.ssh/authorized_keys` to fail loudly if
  `cc_ssh` hasn’t run before runcmd (rare race).

## OpenTofu / Terraform

### State

- Parsing `tofu state show` text output is fragile — use `tofu output`
  instead
- Missing outputs that scripts need — add them to main.tf
- Snapshot/image IDs in tfvars after deleting the snapshot — stale
  reference

### Destructive Operations

- Validate resource IDs before destroy: `[ -n "$ID" ] || exit 1`
- `tofu destroy` without `-target` destroys everything including
  reserved IPs
- Snapshot ID extraction by name: use
  `awk -v n="$NAME" '$2 == n {print $1}'` (exact match on column 2).
  `grep -F "$NAME"` is substring-match and can grab a stale snapshot
  whose name contains the new name as a substring.

## DigitalOcean

### Snapshot disk-size constraint

- DO snapshots include the source droplet’s disk size. New droplets from
  a snapshot must have disk **\>=** snapshot disk. Resize **up** is
  fine; resize **down** below the snapshot disk is impossible without
  rebuilding.
- Build the snapshot at the smallest droplet size you’d ever want to
  spin from it. Sizes vs disks at writing: `g-4vcpu-16gb` = 50 GB,
  `g-8vcpu-32gb` / `m-4vcpu-32gb` = 100 GB, `m-8vcpu-64gb` = 200 GB.
- If your workload requires X GB RAM minimum, your snapshot floor is
  whatever droplet has X GB AND the smallest disk class.

### Reserved IP detach behavior

- Targeted destroy
  (`tofu destroy -target=module.droplet -target=...assignment...`)
  preserves the reserved IP at \$4/mo. Full `tofu destroy` releases it
  (next apply gets a NEW IP).

### Reserved IP assignment race (rtj#55, rtj#85)

- DO returns 422 “Droplet already has a pending event” when reserved IP
  assignment fires immediately after droplet+firewall creation. The
  droplet’s internal event queue takes time to drain.
- **Every DO droplet module that uses a reserved IP MUST have:**
  1.  `time_sleep` resource between droplet creation and IP assignment,
      with `create_duration ≥ 60s` (10s and 30s have both been observed
      to race; 60s has more headroom)
  2.  `depends_on = [time_sleep.<name>]` on the
      `digitalocean_reserved_ip_assignment` resource
  3.  A retry fallback in the wrapping shell script (`up.sh` style) that
      detects the 422 in tofu output and uses
      `doctl compute reserved-ip-action assign <ip> <droplet-id>` to
      recover. Tofu doesn’t retry; it leaves state half-applied
      (assignment recorded but DO didn’t actually attach).
- **Snapshot-based spins are MORE prone to the race** than first-boot
  from blank Ubuntu (more startup events compete for the droplet’s event
  queue).
- **Audit existing modules:**
  `grep -L 'time_sleep' env/do/*/<host>/main.tf` finds modules missing
  the gate. As of 2026-05-02, openclaw and geoserv have no `time_sleep`
  — they will race eventually.

## Docker / Postgres

### Postgis init time

- `imresamu/postgis` (and similar postgis images) on first cold start
  (empty data volume) take **5-12 min** to install all extensions —
  varies with disk IO and noisy-neighbor lottery on cloud hosts.
  Health-wait scripts must allow 15 min minimum, ideally with
  hard-fail + log dump on timeout.

### Tuning vs host RAM

- fresh’s `docker/docker-compose.yml` defaults are tuned for a 128 GB
  host (`shared_buffers=32GB`, `shm_size=36gb`). On smaller hosts,
  postgres OOMs at startup with “could not map anonymous shared memory”.
- 32 GB host floor: use the M1/cypher 32 GB-host preset
  (`scripts/fwapg/compose.override.m1.yml`) which sets
  `shared_buffers=8GB, shm_size=12gb`.
- Below 32 GB: postgres can technically start with smaller
  `shared_buffers` but fwapg work becomes painful. Don’t run fwapg
  pipelines on \<32 GB hosts.

### `search_path` is data, not config

- `ALTER DATABASE <db> SET search_path TO ...` is a database-level
  setting **stored in the postgres data dir**. Wiped with
  `docker compose down -v`. Must be re-applied on every restore.
- Codify in your restore script, not in cloud-init or compose env (those
  don’t apply to db-level settings).

## Tailscale

### ACL “users” semantics

- Tailscale SSH ACL `"users": ["autogroup:nonroot"]` for `tag:compute`
  blocks `ssh root@<node>` over the tailnet. Use `ssh <user>@<node>` +
  sudo for root operations.
- For SSH-as-root from off-tailnet (regular OpenSSH on the public IP),
  the ACL doesn’t apply — but you need the SSH key registered on the
  node.

### Reusable + ephemeral auth keys

- Cypher-style ephemeral compute droplets need both flags on the auth
  key: **Reusable** (same key works across destroy/recreate) +
  **Ephemeral** (tailnet entries auto-clean when offline \>5 min).
- Tag the key (e.g. `tag:compute`) at creation time. Nodes joining with
  that key inherit the tag automatically — no `--advertise-tags` needed
  at `tailscale up` time.

## Security

### Secrets in Committed Files

- `.tfvars` must be gitignored (contains tokens, passwords)
- `.tfvars.example` should have all variables with empty/placeholder
  values
- Sensitive variables need `sensitive = true` in variables.tf

### Firewall Defaults

- `0.0.0.0/0` for SSH is world-open — document if intentional
- If access is gated by Tailscale, say so explicitly

### Credentials

- Passwords with special chars (`'`, `"`, `$`, `!`) break naive shell
  quoting
- `printf '%q'` escapes values for shell safety
- Temp files for secrets: create with `chmod 600`, delete after use

## R / Package Installation

### pak Behavior

- pak stops on first unresolvable package — all subsequent packages are
  skipped
- Removed CRAN packages (like `leaflet.extras`) must move to GitHub
  source
- PPPM binaries may lag a few hours behind new CRAN releases

### Reproducibility

- Branch pins (`pkg@branch`) are not reproducible — document why used
- Pinned download URLs (RStudio .deb) go stale — document where to
  update

## General

### Adopting Existing Config

When importing config from one location into a canonical one (legacy
`~/.bash_profile` → dotfiles repo, old script’s env → repo, another
project’s `settings.json` → soul):

- **Verify every referenced path/binary exists.** Dead PATH exports,
  missing interpreters, stale env vars should be cut, not codified.
  Shell paths:
  `for p in $(echo "$PATH" | tr ':' ' '); do [ -d "$p" ] || echo "DEAD: $p"; done`
- **Ask before dropping a reference** — it may be something the user
  forgot to reinstall on this machine, not something to delete.
- **Curated subset, not verbatim copy.** The diff should reflect what
  you verified, not the whole source.

### Documentation Staleness

- Moving/renaming scripts: update CLAUDE.md, READMEs, usage comments
- New variables: update .tfvars.example
- New workflows: update relevant README

# Comms Conventions

This repo has a `comms/` directory — you’re in the cross-repo
Claude-to-Claude messaging system. Full protocol in `comms/README.md`.
Peer list (who to scan) in `soul/conventions/comms_peers.md`
(internal-only). Load-bearing behaviors below.

## On Session Start

1.  **Inbound scan.** `<this-repo>/comms/*/` — files with `status: open`
    and mtime newer than your last `comms/` commit are mail for you.
2.  **Outbound scan.** For each peer in `comms_peers.md`, check
    `<peer>/comms/<this-repo>/*.md` — files with
    `from: <this-repo>, status: open` are your un-answered sent mail.

If either surfaces open threads, raise to the user before starting other
work.

## Commit Prefix

- `comms(→peer):` — you committed a file in peer’s repo (outbound)
- `comms(←peer):` — you committed a file in your own repo (inbound
  reply)
- `comms:` — meta (close, reopen, rename, README update)

Arrow points to the repo whose `comms/` contains the file you committed.

## Non-negotiables

- One commit per appended message.
- **Push immediately.** Un-pushed comms is invisible to the other
  Claude.
- Code + comms = separate commits.
- Status flips bundle with the triggering message.
- **Use `git commit --only <file>`** for any commit in a peer’s repo
  (thread files). Immune to index races from parallel sessions.

## Propagation: soul publishes, peers pull

Soul is the source of truth for `comms/README.md`. Peers sync by running
`/comms-init` in their own repo, from their own Claude session. **Do not
push README updates into a peer’s repo from another session** —
cross-session index races can bundle unrelated staged files into
misleading commits.

Within your own session, the only things you commit into a peer’s repo
are **thread files** (hosted in the receiver’s repo per the
receiver-hosts rule). Everything else — README syncs, infra — the
peer-Claude pulls itself.

### Cross-repo thread commits: which branch?

Commit on peer’s **current branch** — whatever they’ve got checked out.
Don’t stash, switch, or force main.

If peer isn’t on main, surface to the user: *“thread landing on
`<peer>`:`<branch>`, won’t hit main until PR merges. Continue or hold?”*
If peer has complicated local state (mid-rebase, partial merge), defer
to the user.

# NGE Feature Workflow

For non-trivial issue-driven work, follow this checklist. Each step
exists for a reason — skipping leads to rework, broken builds, and
avoidable bugs that we’ve hit repeatedly.

## The Sequence

1.  **Start with `/planning-init <N>`** — given an issue number, enters
    plan mode for codebase exploration, presents a phase breakdown for
    user approval, then scaffolds branch + PWF baseline with the
    approved phases. One command replaces the manual issue → explore →
    plan → branch → scaffold dance.
2.  **Write robust tests first** — failing tests that reproduce the
    issue or document the new behavior. Tests are the contract; they
    fail until the work makes them pass.
3.  **Name with intent** — functions, parameters, internal helpers carry
    the naming style of the package they live in. Look at existing
    exports as the guide; consistency over cleverness. (Per-package
    naming convention TBD — see soul issue tracking.)
4.  **Examples that run** — every exported function gets a runnable
    `@examples` block. Pkgdown renders them; CI executes them. An
    example that doesn’t run is documentation rot.
5.  **Code-check before each commit** — `/code-check` on staged diff.
    Catches what tests miss: edge cases, hard-coded paths, unguarded
    variables, security issues.
6.  **Atomic commits** — each commit bundles code change + checkbox flip
    in `task_plan.md`. The diff and the progress live in the same
    commit; `git log -- planning/` tells the full story.
7.  **`/planning-archive` when complete** — moves PWF to
    `archive/YYYY-MM-issue-N-slug/`, creates a fresh `active/`. Then
    `/gh-pr-push` opens the PR; `/gh-pr-merge` handles the release
    bookkeeping.

## When to Skip

For one-line typo fixes, version-bump-only PRs, or trivial documentation
edits, the full workflow is overhead. Use judgment. The threshold is
roughly: **multi-step issue, multi-file change, or anything that
requires scoping** → use the workflow.

## Skills That Slot In

- `/planning-init <N>` — start
- `/planning-update` — sync checkboxes mid-session
- `/code-check` — before every commit
- `/planning-archive` — when issue closes
- `/gh-pr-push` — open the PR
- `/gh-pr-merge` — merge with release bookkeeping

## Why This Exists

We’ve hit snags repeatedly when half-doing this — branches that mix
concerns, tests bolted on after, code-check skipped (and then a bug
ships in the diff), examples that fail in pkgdown. Each step is small;
the cumulative reliability gain is real. The convention is here so it
becomes the default expectation, not a thing the user has to remind
every session about.

# LLM Behavioral Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. Merge with
project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For
trivial tasks, use judgment.

## 1. Think Before Coding

**Don’t assume. Don’t hide confusion. Surface tradeoffs.**

Before implementing: - State your assumptions explicitly. If uncertain,
ask. - If multiple interpretations exist, present them - don’t pick
silently. - If a simpler approach exists, say so. Push back when
warranted. - If something is unclear, stop. Name what’s confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No “flexibility” or “configurability” that wasn’t requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: “Would a senior engineer say this is overcomplicated?” If
yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code: - Don’t “improve” adjacent code, comments,
or formatting. - Don’t refactor things that aren’t broken. - Match
existing style, even if you’d do it differently. - If you notice
unrelated dead code, mention it - don’t delete it.

When your changes create orphans: - Remove imports/variables/functions
that YOUR changes made unused. - Don’t remove pre-existing dead code
unless asked.

The test: Every changed line should trace directly to the user’s
request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals: - “Add validation” → “Write tests
for invalid inputs, then make them pass” - “Fix the bug” → “Write a test
that reproduces it, then make it pass” - “Refactor X” → “Ensure tests
pass before and after”

For multi-step tasks, state a brief plan:

    1. [Step] → verify: [check]
    2. [Step] → verify: [check]
    3. [Step] → verify: [check]

Strong success criteria let you loop independently. Weak criteria (“make
it work”) require constant clarification.

**These guidelines are working if:** fewer unnecessary changes in diffs,
fewer rewrites due to overcomplication, and clarifying questions come
before implementation rather than after mistakes.

# Planning Conventions

How Claude manages structured planning for complex tasks using
planning-with-files (PWF).

## When to Plan

Use PWF when a task has multiple phases, requires research, or involves
more than ~5 tool calls. Triggers: - User says “let’s plan this”, “plan
mode”, “use planning”, or invokes `/planning-init` - Complex issue work
begins (multi-step, uncertain approach) - Claude judges the task
warrants structured tracking

Skip planning for single-file edits, quick fixes, or tasks with obvious
next steps.

## The Workflow

1.  **Explore first** — Enter plan mode (read-only). Read code, trace
    paths, understand the problem before proposing anything.
2.  **Plan to files** — Write the plan into 3 files in
    `planning/active/`:
    - `task_plan.md` — Phases with checkbox tasks
    - `findings.md` — Research, discoveries, technical analysis
    - `progress.md` — Session log with timestamps and commit refs
3.  **Plan-review with the Plan agent before committing the plan** —
    After scaffolding `task_plan.md` but BEFORE the baseline commit,
    spawn the Plan subagent
    (`Agent({subagent_type: "Plan", prompt: "..."}`) and ask it to
    critically review the task_plan against the issue body + actual
    codebase. Categorize findings as Blocker / Gap / Ordering /
    Assumption / Scope / Acceptance. Address each before committing. The
    agent reads files fresh — it catches what you miss when you’ve been
    thinking about the design too long. Real example: caught 21 issues
    including hardcoded literals across 4 files not listed in the plan,
    untested DB column mismatches, unfixable test-literal-string
    assertions, and a baseline-cache-shadow that would have produced a
    6-second no-op run. Cost: ~5 min agent. Saves: hours of
    mid-implementation rework.
4.  **Commit the plan** — After Plan-agent review + fixes. This is the
    baseline.
5.  **Work in atomic commits** — Each commit bundles code changes WITH
    checkbox updates in the planning files. The diff shows both what was
    done and the checkbox marking it done.
6.  **Code check before commit** — Run `/code-check` on staged diffs
    before committing. Don’t mark a task done until the diff passes
    review.
7.  **Archive when complete** — Move `planning/active/` to
    `planning/archive/` via `/planning-archive`. Write a README.md in
    the archive directory with a one-paragraph outcome summary and
    closing commit/PR ref — future sessions scan these to catch up fast.

## Atomic Commits (Critical)

Every commit that completes a planned task MUST include: - The
code/script changes - The checkbox update in `task_plan.md` (`- [ ]` -\>
`- [x]`) - A progress entry in `progress.md` if meaningful

This creates a git audit trail where `git log -- planning/` tells the
full story. Each commit is self-documenting — you can backtrack with git
and understand everything that happened.

## File Formats

### task_plan.md

Phases with checkboxes. This is the core tracking file.

``` markdown
# Task Plan

## Phase 1: [Name]
- [ ] Task description
- [ ] Another task

## Phase 2: [Name]
- [ ] Task description
```

Mark tasks done as they’re completed: `- [x] Task description`

### findings.md

Append-only research log. Discoveries, technical analysis, things
learned.

``` markdown
# Findings

## [Topic]
[What was found, with source/date]
```

### progress.md

Session entries with commit references.

``` markdown
# Progress

## Session YYYY-MM-DD
- Completed: [items]
- Commits: [refs]
- Next: [items]
```

## Directory Structure

    planning/
      active/          <- Current work (3 PWF files)
      archive/         <- Completed issues
        YYYY-MM-issue-N-slug/

If `planning/` doesn’t exist in the repo, run `/planning-init` first.

## Skills

| Skill               | When to use                                        |
|---------------------|----------------------------------------------------|
| `/planning-init`    | First time in a repo — creates directory structure |
| `/planning-update`  | Mid-session — sync checkboxes and progress         |
| `/planning-archive` | Issue complete — archive and create fresh active/  |

# R Package Development Conventions

Standards for R package development across New Graph Environment
repositories. Based on [R Packages (2e)](https://r-pkgs.org/) by Hadley
Wickham and Jenny Bryan.

**Reference packages:** When starting a new package, study these
existing packages for patterns: `flooded`, `gq`. They demonstrate the
conventions below in practice (DESCRIPTION fields, README layout,
NEWS.md style, pkgdown setup, test structure, hex sticker, etc.).

## Style

- tidyverse style guide: snake_case, pipe operators (`|>` or `%>%`)

- Match existing patterns in each codebase

- Use `pak` for package installation (not `install.packages`)

- Prefix column name vectors with `cols_` for discoverability in the
  environment pane: `cols_all`, `cols_carry`, `cols_split`,
  `cols_writable`. Same principle for other grouped vectors (`params_`,
  `tbl_`, etc.)

- For SQL DDL+INSERT pairs that share a schema, use a single named
  vector as the source of truth. Both `CREATE TABLE` and
  `INSERT (cols) SELECT cols` derive their column lists from the same
  `cols_*` vector. Avoids drift between table shape and write projection
  — when columns change, you edit one place. Example:

  ``` r

  cols_streams <- c(
    id_segment           = "integer NOT NULL",
    watershed_group_code = "varchar(4) NOT NULL",
    geom                 = "geometry(MultiLineStringZM, 3005)"
    # …
  )
  # CREATE TABLE consumes both names + types
  ddl_body <- paste(names(cols_streams), unname(cols_streams), sep = " ",
                    collapse = ", ")
  # INSERT consumes names only
  proj <- paste(names(cols_streams), collapse = ", ")
  ```

## Package Structure

Follow R Packages (2e) conventions: - `R/` for functions,
`tests/testthat/` for tests, `man/` for docs - `DESCRIPTION` with proper
fields (Title, Description, <Authors@R>) - `DESCRIPTION` URL field:
include both the GitHub repo and the pkgdown site so pkgdown links
correctly (e.g.,
`URL: https://github.com/OWNER/PKG, https://owner.github.io/PKG/`) -
`NAMESPACE` managed by roxygen2 (`#' @export`, `#' @import`,
`#' @importFrom`) - Never edit `NAMESPACE` or `man/` by hand

## One Function, One File

Each exported function gets its own R file and its own test file: -
`R/fl_mask.R` → `tests/testthat/test-fl_mask.R` - Commit the function
and its tests together - Use `Fixes #N` in the commit message to close
the corresponding issue

## GitHub Issues and SRED Tracking

### Issue-per-function workflow

File a GitHub issue for each function before building it. This creates a
traceable record of what was planned, built, and verified.

### Branching for SRED

For new packages or major features, work on a branch and merge via PR:

    main ← scaffold-branch (PR closes with "Relates to NewGraphEnvironment/sred-2025-2026#N")

This gives one PR that contains all commits — a single SRED
cross-reference covers the entire body of work. Individual commits
within the branch close their respective function issues with
`Fixes #N`.

### Closing issues

Close function issues via commit messages — see Closing Issues in
newgraph conventions.

## Testing

- Use testthat 3e (`Config/testthat/edition: 3` in DESCRIPTION)

- Run `devtools::test()` before committing

- Test files mirror source: `R/utils.R` -\>
  `tests/testthat/test-utils.R`

- Test for edge cases and potential failures, not just happy paths

- Tests must pass before closing the function’s issue

- Always grep for errors in the same command as the test run to avoid
  running twice:

  ``` bash
  Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5
  ```

  For error context: `grep -E "(ERROR:|FAIL )" -A 10 | head -25`

## Examples and Vignettes

### Runnable examples on every exported function

Examples are how users discover what a function does. They must: -
**Actually run** — no `\dontrun{}` unless external resources are
required - **Use bundled test data** via
[`system.file()`](https://rdrr.io/r/base/system.file.html) so they work
for anyone - **Show why the function is useful** — not just that it
runs, but what it produces and why you’d use it - **Use qualified
names** for non-exported dependencies
([`terra::rast()`](https://rspatial.github.io/terra/reference/rast.html),
[`sf::st_read()`](https://r-spatial.github.io/sf/reference/st_read.html))
since examples run in the user’s environment

### Vignettes

At least one vignette showing the full pipeline on real data: -
Demonstrates the package solving an actual problem end-to-end - Uses
bundled test data (committed to `inst/testdata/`) - Hosted on pkgdown so
users can read it without installing

**Output format:** Use
[`bookdown::html_vignette2`](https://pkgs.rstudio.com/bookdown/reference/html_document2.html)
(not
[`rmarkdown::html_vignette`](https://pkgs.rstudio.com/rmarkdown/reference/html_vignette.html))
for figure numbering and cross-references. Requires `bookdown` in
Suggests and chunks must have `fig.cap` for numbered figures.
Cross-reference with `Figure \@ref(fig:chunk-name)`.

**Vignettes that need external resources (DB, API, STAC):** Do NOT use
the `.Rmd.orig` pre-knit pattern — it breaks `bookdown` figure numbering
because knitr evaluates chunks during pre-knit and emits `![](path)`
markdown that bookdown can’t number.

Instead, separate data generation from presentation: 1.
`data-raw/vignette_data.R` — runs the queries, saves results as `.rds`
to `inst/testdata/` (or `inst/vignette-data/`) 2. Vignette loads `.rds`
files, all chunks run live during pkgdown build 3. Note at top of
vignette: “Data generated by `data-raw/script.R`” 4. bookdown controls
all chunks — figure numbers, cross-refs work

This is the same pattern as test data: `data-raw/` documents how the
data was produced, committed artifacts make vignettes reproducible
without the external resource.

### Test data

- Created via a script in `data-raw/` that documents exactly how the
  data was produced (database queries, spatial crops, etc.)
- Committed to `inst/testdata/` — small enough to ship with the package
- Used by tests, examples, and vignettes — one dataset, three purposes

## Documentation

- roxygen2 for all exported functions
- `@import` or `@importFrom` in the package-level doc
  (`R/<pkg>-package.R`) to populate NAMESPACE — don’t rely on `::`
  everywhere in function bodies
- pkgdown site for public packages with `_pkgdown.yml` (bootstrap 5)
- GitHub Action for pkgdown (`usethis::use_github_action("pkgdown")`)

## lintr

Run `lintr::lint_package()` before committing R package code. Fix all
warnings — every lint should be worth fixing.

### Recommended .lintr config

``` r

linters: linters_with_defaults(
    line_length_linter(120),
    object_name_linter(styles = c("snake_case", "dotted.case")),
    commented_code_linter = NULL
  )
exclusions: list(
    "renv" = list(linters = "all")
  )
```

- 120 char line length (default 80 is too strict for data pipelines)
- Allow dotted.case (common in base R and legacy code)
- Suppress commented code lints (exploratory R scripts often have
  commented alternatives)
- Exclude renv directory entirely

## Dependencies

- Minimize Imports — use `Suggests` for packages only needed in
  tests/vignettes
- Pin versions only when breaking changes are known
- Prefer packages already in the tidyverse ecosystem

## Releasing

1.  Update `NEWS.md` — keep it concise:
    - First release: one line (e.g., “Initial release. Brief
      description.”)
    - Later releases: describe what changed and why, not
      function-by-function. Link to the pkgdown reference page for
      details — don’t duplicate it.
    - Don’t list every function; the pkgdown reference page is the
      single source of truth for what’s in the package.
2.  Bump version in `DESCRIPTION` (e.g., `0.0.0.9000` → `0.1.0`) — as
    the **final** commit of the branch, after verification numbers/tests
    are final. Mid-branch bumps are premature and churn: additional code
    changes end up bundled inside a “release” that already claimed the
    version.
3.  Commit as “Release vX.Y.Z”
4.  Tag: `git tag vX.Y.Z && git push && git push --tags`

## Repository Setup

### Branch protection

Protect main from deletion and force pushes:

``` bash
gh api repos/OWNER/REPO/rulesets --method POST --input - <<'EOF'
{
  "name": "Protect main",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" }
  ],
  "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
  "rules": [ { "type": "deletion" }, { "type": "non_fast_forward" } ]
}
EOF
```

### Scaffold checklist

- `usethis::create_package(".")`
- `usethis::use_mit_license("New Graph Environment Ltd.")`
- `usethis::use_testthat(edition = 3)`
- `usethis::use_pkgdown()`
- `usethis::use_github_action("pkgdown")`
- `usethis::use_directory("dev")` — reproducible setup script
- `usethis::use_directory("data-raw")` — data generation scripts
- Hex sticker via `hexSticker` (see `data-raw/make_hexsticker.R`)
- Set GitHub Pages to serve from `gh-pages` branch

### dev/dev.R

Keep a `dev/dev.R` file that documents every setup step. Not idempotent
— run interactively. This is the reproducible recipe for the package
scaffold.

## README

Keep the README lean: - Hex sticker, one-line description, install,
example showing *why* it’s useful - Link to pkgdown vignette and
function reference — don’t duplicate them - Don’t maintain a function
table — it’s just another thing to keep updated and pkgdown’s reference
page is the single source of truth

## LLM Workflow

When an LLM assistant modifies R package code: 1. Run
`lintr::lint_package()` — fix issues before committing 2. Run
`devtools::test()` with error grep — ensure tests pass in one call:
`bash Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5`
3. Run `devtools::document()` and grep for results:
`bash Rscript -e 'devtools::document()' 2>&1 | grep -E "(Writing|Updating|warning)" | tail -10`
4. Check `devtools::check()` passes for releases — capture results in
one call:
`bash Rscript -e 'devtools::check()' 2>&1 | grep -E "(ERROR|WARNING|NOTE|errors|warnings|notes)" | tail -10`

# Reference Management Conventions

How references flow between Claude Code, Zotero, and technical writing
at New Graph Environment.

## Tool Routing

Three tools, different purposes. Use the right one.

| Need | Tool | Why |
|----|----|----|
| Search by keyword, read metadata/fulltext, semantic search | **MCP `zotero_*` tools** | pyzotero, works with Zotero item keys |
| Look up by citation key (e.g., `irvine2020ParsnipRiver`) | **`/zotero-lookup` skill** | Citation keys are a BBT feature — pyzotero can’t resolve them |
| Create items, attach PDFs, deduplicate | **`/zotero-api` skill** | Connector API for writes, JS console for attachments |

**Citation keys vs item keys:** Citation keys (like
`irvine2020ParsnipRiver`) come from Better BibTeX. Item keys (like
`K7WALMSY`) are native Zotero. The MCP works with item keys.
`/zotero-lookup` bridges citation keys to item data.

**BBT citation key storage:** As of Feb 2025+, BBT stores citation keys
as a `citationKey` field directly in `zotero.sqlite` (via Zotero’s item
data system), not in a separate BBT database. The old
`better-bibtex.sqlite` and `better-bibtex.migrated` files are stale and
no longer updated. Query citation keys with:
`SELECT idv.value FROM items i JOIN itemData id ON i.itemID = id.itemID JOIN itemDataValues idv ON id.valueID = idv.valueID JOIN fields f ON id.fieldID = f.fieldID WHERE f.fieldName = 'citationKey'`.

## Adding References Workflow

### 1. Search and flag

When research turns up a reference: - **DOI available:** Tell the user —
Zotero’s magic wand (DOI lookup) is the fastest path - **ResearchGate
link:** Flag to user for manual check — programmatic fetch is blocked
(403), but full text is often there - **BC gov report:** Search
[ACAT](https://a100.gov.bc.ca/pub/acat/), for.gov.bc.ca library, EIRS
viewer - **Paywalled:** Note it, move on. Don’t waste time trying to
bypass.

### 2. Add to Zotero

**Preferred order:** 1. DOI magic wand in Zotero UI (fastest, most
complete metadata) 2. Web API POST with `collections` array (grey
literature, local PDFs — targets collection directly, no UI interaction
needed) 3. `saveItems` via `/zotero-api` (batch creation from structured
data — requires UI collection selection) 4. JS console script for group
library (when connector can’t target the right collection)

**Collection targeting:** `saveItems` drops items into whatever
collection is selected in Zotero’s UI. Always confirm with the user
before calling it. **Web API bypasses this** — include
`"collections": ["KEY"]` in the POST body. Find collection keys with
`?q=name` search on the collections endpoint.

### 3. Attach PDFs

`saveItems` attachments silently fail. Don’t use them. Instead:

1.  **Web API S3 upload (preferred):** Create attachment item → get
    upload auth → build S3 body (Python: prefix + file bytes + suffix) →
    POST to S3 → register with uploadKey. Works without Zotero running.
    See `/zotero-api` skill section 4.
2.  **JS console fallback:** Download with `curl`, attach via
    `item_attach_pdf.js` in Zotero JS console.
3.  Verify attachment exists via MCP: `zotero_get_item_children`

### 4. Verify

After manual adds, confirm via MCP: - `zotero_search_items` — find by
title - `zotero_get_item_metadata` — check fields are complete -
`zotero_get_item_children` — confirm PDF attached

### 5. Clean up

If duplicates were created (common with `saveItems` retries): - Run
`collection_dedup.js` via Zotero JS console - It keeps the copy with the
most attachments, trashes the rest

## In Reports (bookdown)

### Bibliography generation

``` yaml
# index.Rmd — dynamic bib from Zotero via Better BibTeX
bibliography: "`r rbbt::bbt_write_bib('references.bib', overwrite = TRUE)`"
```

`rbbt` pulls from BBT, which syncs with Zotero. Edit references in
Zotero → rebuild report → bibliography updates.

**Library targeting:** rbbt must know which Zotero library to search.
This is set globally in `~/.Rprofile`:

``` r

# default library — NewGraphEnvironment group (libraryID 9, group 4733734)
options(rbbt.default.library_id = 9)
```

Without this option, rbbt searches only the personal library
(libraryID 1) and won’t find group library references. The library IDs
map to Zotero’s internal numbering — use `/zotero-lookup` with
`SELECT DISTINCT libraryID FROM citationkey` against the BBT database to
discover available libraries.

### Citation syntax

- `[@key2020]` — parenthetical: (Author 2020)
- `@key2020` — narrative: Author (2020)
- `[@key1; @key2]` — multiple
- `nocite:` in YAML — include uncited references

### Cite primary sources

When a review paper references an older study, trace back to the
original and cite it. Don’t attribute findings to the review when the
original exists. (See LLM Agent Conventions in `newgraph.md`.)

**When the original is unavailable** (paywalled, out of print, can’t
locate): use secondary citation format in the prose and include bib
entries for both sources:

> Smith et al. (2003; as cited in Doctor 2022) found that…

Both `@smith2003` and `@doctor2022` go in the `.bib` file. The reader
can then track down the original themselves. Flag incomplete metadata on
the primary entry — it’s better to have a partial reference than none at
all.

## PDF Fallback Chain

When you need a PDF and the obvious URL doesn’t work:

1.  DOI resolver → publisher site (often has OA link)
2.  Europe PMC
    (`europepmc.org/backend/ptpmcrender.fcgi?accid=PMC{ID}&blobtype=pdf`)
    — ncbi blocks curl
3.  SciELO — needs `User-Agent: Mozilla/5.0` header
4.  ResearchGate — flag to user for manual download
5.  Semantic Scholar — sometimes has OA links
6.  Ask user for institutional access

Always verify downloads: `file paper.pdf` should say “PDF document”, not
HTML.

## Searching Paper Content (ragnar)

### Setup (per project)

- `scripts/rag_build.R` — maps citation keys to Zotero PDF attachment
  keys, builds DuckDB
- `data/rag/` gitignored — store is local, not committed
- Dependencies: ragnar, Ollama with nomic-embed-text model
- See `/lit-search` skill for full recipe

### Query

`ragnar_store_connect()` then `ragnar_retrieve()` — returns chunks with
source file attribution.

### Anti-patterns

- NEVER write abstracts manually — if CrossRef has no abstract, leave
  blank
- NEVER cite specific numbers without verifying from the source PDF via
  ragnar search
- NEVER paraphrase equations — copy exact notation and cite page/section
