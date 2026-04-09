# fresh

Freshwater Referenced Spatial Hydrology. A composable stream network modelling engine. Query and extract stream networks, classify habitat by gradient and channel width, segment networks at barriers and break points, aggregate features upstream or downstream, and run multi-species habitat modelling with parallel workers.

## Repository Context

**Repository:** NewGraphEnvironment/fresh
**Primary Language:** R (package)
**Version:** 0.9.0
**License:** MIT

## Ecosystem

| Package | Role |
|---------|------|
| **fresh** | Stream network modelling engine (this package) |
| [link](https://github.com/NewGraphEnvironment/link) | Crossing connectivity interpretation — scoring, overrides, prioritization |
| [flooded](https://github.com/NewGraphEnvironment/flooded) | Delineate floodplain extents from DEMs and stream networks |
| [drift](https://github.com/NewGraphEnvironment/drift) | Track land cover change within floodplains over time |
| [fly](https://github.com/NewGraphEnvironment/fly) | Estimate airphoto footprints and select optimal coverage for a study area |
| [diggs](https://github.com/NewGraphEnvironment/diggs) | Interactive explorer for fly airphoto selections (Shiny app) |

Pipeline: fresh (network data) → flooded (floodplains) → drift (land cover change)

## Architecture

```
R/
  fresh-package.R            — package-level doc, imports
  frs_db_conn.R              — DB connection via PG_*_SHARE env vars
  frs_db_query.R             — execute SQL, return sf
  frs_habitat.R              — orchestrator: multi-WSG/AOI habitat pipeline
  frs_habitat_classify.R     — long-format habitat classification per species
  frs_network_segment.R      — domain-agnostic network segmentation
  frs_feature_find.R         — locate point features on network
  frs_feature_index.R        — upstream/downstream relationship indexing
  frs_break.R                — gradient break detection (island method)
  frs_classify.R             — segment classification by attributes/breaks
  frs_extract.R              — extract streams to working table
  frs_col_join.R             — join attributes (channel width, discharge)
  frs_col_generate.R         — recompute gradient from geometry
  frs_network.R              — unified multi-table network traversal
  frs_network_upstream.R     — upstream network query (ltree)
  frs_network_downstream.R   — downstream network query (ltree)
  frs_point_snap.R           — snap points to nearest stream
  frs_point_locate.R         — locate point on stream network
  frs_stream_fetch.R         — fetch stream segments
  frs_lake_fetch.R           — fetch lakes
  frs_wetland_fetch.R        — fetch wetlands
  frs_params.R               — load species habitat parameters
  frs_wsg_species.R          — species presence per watershed group
  frs_edge_types.R           — FWA edge type lookup
  utils.R                    — internal helpers
tests/testthat/              — unit tests
inst/extdata/                — bundled CSVs (falls, crossings, params, species)
data-raw/                    — data refresh scripts
docker/                      — local fwapg Docker setup
vignettes/                   — .Rmd.orig source, .Rmd pre-knitted output
```

## Key Patterns

- All exported functions prefixed `frs_`, named noun-first: `frs_network_segment()`, `frs_habitat_classify()`, `frs_feature_find()`
- `frs_habitat()` is the main orchestrator — wraps `frs_network_segment()` + `frs_habitat_classify()` with mirai parallel workers
- `frs_network_segment()` is domain-agnostic — segments any network at any break points
- `frs_habitat_classify()` produces long-format output: one row per segment × species, joined to geometry via `id_segment`
- `break_sources` with `label`, `label_col`, `label_map` for flexible network-referenced classification
- `label_block` controls which labels restrict access (default `"blocked"`, configurable)
- `gate = FALSE` skips accessibility for raw habitat potential
- Direct SQL via DBI/RPostgres against fwapg PostgreSQL
- Returns sf objects for spatial results
- Requires PostgreSQL with fwapg only (bcfishpass/bcfishobs optional)
- Vignette data cached in `inst/extdata/` with `update_gis` YAML param (FALSE = cached, TRUE = live DB)

## Dependencies

- **Runtime:** DBI, RPostgres, sf
- **Suggests:** mirai, tmap (>= 4.0), gq, bookdown, knitr, rmarkdown
- **Database:** PostgreSQL with fwapg (local Docker or remote tunnel)
- **Connection:** Local Docker on port 5432 or SSH tunnel on 63333; see db-newgraph skill

## Naming Conventions

### Generated column names

- `id_*` prefix for fresh-generated identifiers: `id_segment` (sub-segment after breaking)
- FWA columns kept as-is: `linear_feature_id`, `blue_line_key`, `downstream_route_measure`, `wscode_ltree`, `localcode_ltree`
- Habitat classification columns are generic (not species-prefixed): `accessible`, `spawning`, `rearing`, `lake_rearing`. Species is a row value (`species_code`), not a column name.

### Parameter names

- `to`, `from` — complete DB table names (schema-qualified)
- `to_prefix` — table name prefix, suffixed by the function (e.g. `"fresh.streams"` → `fresh.streams_co`)
- `to_streams`, `to_habitat` — explicit output table names in `frs_habitat()`
- `col_*` — column name mappings for flexible table schemas: `col_blk`, `col_measure`
- `break_sources` — list of break source specs with `table`, `where`, `label`, `label_col`, `label_map`, `col_blk`, `col_measure`

### Function names

- `frs_noun_verb` pattern: `frs_network_segment`, `frs_point_snap`, `frs_stream_fetch`
- Pipeline orchestrators wrap exported building blocks:
  - `frs_habitat()` wraps `frs_network_segment()` + `frs_habitat_classify()`
  - `frs_network_segment()` wraps `frs_extract()` + `frs_break_find()` + `frs_break_apply()`
  - `frs_habitat_classify()` wraps `frs_classify()` per species

### Output table structure

- `{to_streams}` — one row per segment, geometry + base attributes + `id_segment`
- `{to_habitat}` — long format, one row per segment × species. Columns: `id_segment`, `species_code`, `accessible`, `spawning`, `rearing`, `lake_rearing`. No geometry.
- Views per species: `{to_streams}_co_vw` = join streams + habitat WHERE species_code = 'CO'

<!-- BEGIN SOUL CONVENTIONS — DO NOT EDIT BELOW THIS LINE -->

# Agent Teams

When to use Claude Code agent teams vs subagents, and key constraints.

**Source:** [code.claude.com/docs/en/agent-teams](https://code.claude.com/docs/en/agent-teams)

## When to Use Teams (vs. Subagents)

Use agent teams when teammates need to **talk to each other** — research debates, competing hypotheses, cross-layer coordination. Use subagents when you just need focused workers that report back results.

**Good fit:** parallel code review, investigating competing bug hypotheses, new modules that don't share files, research from multiple angles.

**Bad fit:** sequential tasks, edits to the same file, simple work where coordination overhead exceeds benefit.

## Key Rules

- **Give enough context in the spawn prompt** — teammates don't inherit the lead's conversation history
- **Ensure teammates own different files** — two teammates editing the same file leads to overwrites
- **Shut down all teammates before cleanup** — cleanup fails if teammates are still running
- **Always clean up via the lead** — teammates should never run cleanup
- **No session resumption** — after `/resume`, spawn new teammates

# Bookdown Conventions

Standards for bookdown report projects across New Graph Environment.

## Template Repos

These are the canonical references. Child repos inherit their structure and patterns.

- [mybookdown-template](https://github.com/NewGraphEnvironment/mybookdown-template) — General-purpose bookdown starter
- [fish_passage_template_reporting](https://github.com/NewGraphEnvironment/fish_passage_template_reporting) — Fish passage reporting template

When in doubt, match what the template does. When the template and production repos disagree, production wins — update the template.

## Project Structure

```
project/
├── index.Rmd                # Master config, YAML params, setup chunks
├── _bookdown.yml            # book_filename, output_dir: "docs"
├── _output.yml              # Gitbook, pagedown, pdf_book config
├── 0100-intro.Rmd           # Chapter numbering: 4-digit, 100s increment
├── 0200-background.Rmd
├── 0300-methods.Rmd
├── 0400-results.Rmd
├── 0500-*.Rmd               # Discussion/recommendations
├── 0800-appendix-*.Rmd      # Appendices (site-specific in fish passage)
├── 2000-references.Rmd      # Auto-generated from .bib
├── 2090-report-change-log.Rmd  # Auto-generated from NEWS.md
├── 2100-session-info.Rmd    # Reproducibility
├── NEWS.md                  # Changelog (semantic versioning)
├── scripts/
│   ├── packages.R           # Package loading (renv-managed)
│   ├── functions.R          # Project-specific functions
│   ├── staticimports.R      # Auto-generated from staticimports pkg
│   ├── setup_docs.R         # Build helper
│   └── run.R                # Local build (gitbook + PDF)
├── fig/                     # Figures (organized by chapter or type)
├── data/                    # Project data
├── docs/                    # Rendered output (GitHub Pages)
├── renv.lock                # Locked dependencies
└── .Rprofile                # Activates renv
```

## Setup Chunk Pattern

Every `index.Rmd` follows this setup sequence. Order matters.

```r
# 1. Gitbook vs PDF switch
gitbook_on <- TRUE

# 2. Knitr options
knitr::opts_chunk$set(
  echo = identical(gitbook_on, TRUE),  # Show code only in gitbook
  message = FALSE, warning = FALSE,
  dpi = 60, out.width = "100%"
)
options(scipen = 999)
options(knitr.kable.NA = '--')
options(knitr.kable.NAN = '--')

# 3. Source in order: packages → static imports → functions → data
source('scripts/packages.R')
source('scripts/staticimports.R')
source('scripts/functions.R')
```

Responsive settings by output format:

```r
# Gitbook
photo_width <- "100%"; font_set <- 11

# PDF (paged.js)
photo_width <- "80%"; font_set <- 9
```

## YAML Parameters

Parameters live in `index.Rmd` frontmatter (not a separate file). Child repos override by editing these values.

```yaml
params:
  repo_url: 'https://github.com/NewGraphEnvironment/repo_name'
  report_url: 'https://www.newgraphenvironment.com/repo_name/'
  update_packages: FALSE
  update_bib: TRUE
  gitbook_on: TRUE
```

Fish passage repos add project-specific params (`project_region`, `model_species`, `wsg_code`, update flags for forms). These are project-specific — don't add them to the general template.

## Chunk Naming

Embed context and purpose in chunk names. The principle is universal; the codes are project-specific.

**Pattern:** `{type}-{system}-{description}`

| Type | Examples |
|------|---------|
| Tables | `tab-kln-load-int-yr`, `tab-sites-sum`, `tab-wshd-196332` |
| Figures | `plot-wq-kln-quadratic`, `map-interactive`, `map-196332` |
| Photos | `photo-196332-01`, `photo-196332-d01` (dual layout) |

## Cross-References

Bookdown auto-prepends `fig:` or `tab:` to chunk names.

- **Tables:** `Table \@ref(tab:chunk-name)`
- **Figures:** `Figure \@ref(fig:chunk-name)`

No `fig:` or `tab:` prefix in the chunk label itself — bookdown adds it.

## Table Caption Workaround

Interactive tables (DT) can't use standard bookdown captions. Use the `my_tab_caption()` function from `staticimports.R`.

**Pattern:** Separate `-cap` chunk from table chunk.

```r
# Caption chunk — must use results="asis"
{r tab-sites-sum-cap, results="asis"}
my_caption <- "Summary of fish passage assessment procedures."
my_tab_caption()
```

```r
# Table chunk — renders the DT
{r tab-sites-sum}
data |> my_dt_table(page_length = 20, cols_freeze_left = 0)
```

`my_tab_caption()` auto-grabs the chunk label via `knitr::opts_current$get()$label` and wraps it in HTML caption tags that bookdown can cross-reference.

## Photo Layout

Separate prep chunk (find the file) from display chunk (render it).

```r
# Prep — find the photo
{r photo-196332-01-prep}
my_photo1 <- fpr::fpr_photo_pull_by_str(str_to_pull = 'ds_typical_1_')
my_caption1 <- paste0('Typical habitat downstream of PSCIS crossing ', my_site, '.')
```

```r
# Gitbook — full width
{r photo-196332-01, fig.cap=my_caption1, out.width=photo_width, eval=gitbook_on}
knitr::include_graphics(my_photo1)
```

```r
# PDF — side by side with 1% spacer
{r photo-196332-d01, fig.show="hold", out.width=c("49.5%","1%","49.5%"), eval=identical(gitbook_on, FALSE)}
knitr::include_graphics(my_photo1)
knitr::include_graphics("fig/pixel.png")
knitr::include_graphics(my_photo2)
```

## Bibliography

**`references.bib` is auto-generated — never edit it manually.** On each build, `rbbt::bbt_write_bib()` scans all `.Rmd` files for `@citekey` references, pulls the BibTeX from Zotero's Better BibTeX, and overwrites `references.bib`. Any manual additions will be lost on the next build.

To add a reference: add it to the shared Zotero group library, use its BBT citation key (`@key`) in the `.Rmd` text, and build. rbbt handles the rest.

```yaml
bibliography: "`r rbbt::bbt_write_bib('references.bib', overwrite = TRUE)`"
biblio-style: apalike
link-citations: no
```

When `update_bib: FALSE` in params, the build uses the existing `references.bib` without regenerating — useful for offline builds or CI where Zotero isn't running.

Auto-generate package citations:

```r
knitr::write_bib(c(.packages(), 'bookdown', 'knitr', 'rmarkdown'), 'packages.bib')
```

Use `nocite:` in YAML to include references not cited in text.

## Acknowledgement & AI Disclosure

`index.Rmd` contains two separate front-matter sections after the setup chunks:

### Acknowledgement {.front-matter .unnumbered}

Three parts, in order:

1. **Personal connection to land** (template-level, same across all reports):
   > At New Graph Environment, we understand our well-being as inseparable from the health of the land and waters we work within. When we care for ecosystems, we care for ourselves and for the communities connected to them. This relationship is not metaphorical — it is the foundation of our practice.

2. **Colonial acknowledgement** (template-level):
   > Modern civilization has a long journey ahead to acknowledge and address the historic and ongoing impacts of colonialism...

3. **Territorial acknowledgement** (project-specific, must be edited per report): Name the Nations, governance systems, watersheds, and species relevant to the project. Do not use a generic office-location acknowledgement — tie it to the territory where the work happens. See the Wedzin Kwa chinook example for the pattern.

4. **Funding and partners** (project-specific).

### AI Disclosure

Do not use a `#` heading for the disclosure — this creates a separate chapter page in gitbook. Instead, add it to the YAML `date:` field so it renders in the title block:

```yaml
date: |
 |
 | Version X.X.X DRAFT `r format(Sys.Date(), "%Y-%m-%d")`
 |
 | *Claude Sonnet 4.6 (Anthropic) assisted with literature synthesis, drafting, and technical writing. All scientific interpretation, data analysis, and conclusions are the responsibility of the authors.*
```

**Wording principle:** Be accurate about what the LLM did. It assisted with drafting and synthesis — it did not make scientific interpretations or conclusions. Do not say "independently verified by the authors" (redundant) or attribute "ecological assessments" to the LLM.

For regulatory/EGBC-stamped work, use the extended disclaimer from `soul/research/20260212_ai_disclosure_research.md`. See NewGraphEnvironment/mybookdown-template#89.

## Conditional Rendering (Gitbook vs PDF)

A single boolean `gitbook_on` controls output format throughout.

```r
# Show only in gitbook
{r map-interactive, eval=gitbook_on}

# Show only in PDF
{r fig-print-only, eval=identical(gitbook_on, FALSE)}

# Conditional inline content
`r if(identical(gitbook_on, FALSE)) knitr::asis_output("This report is available online...")`

# Page breaks for PDF only
`r if(gitbook_on){knitr::asis_output("")} else knitr::asis_output("\\pagebreak")`
```

## Versioning and Changelog

Reports use MAJOR.MINOR.PATCH versioning with a `NEWS.md` changelog.

**Version in `index.Rmd` YAML:**
```yaml
date: |
 |
 | Version 1.1.0 DRAFT `r format(Sys.Date(), "%Y-%m-%d")`
```

**NEWS.md format:**
```markdown
## 1.1.0 (2026-02-17)

- Add feature X
- Fix issue Y ([Issue #N](https://github.com/Org/repo/issues/N))
```

**Auto-append as appendix** via `my_news_to_appendix()` in `staticimports.R`:
```r
news_to_appendix(md_name = "NEWS.md", rmd_name = "2090-report-change-log.Rmd")
```

**Convention:**
- Bump version in `index.Rmd` and add NEWS entry for every commit to main that changes report content
- Tag releases: `git tag -a v1.1.0 -m "v1.1.0: Brief description"`
- MAJOR: structural changes, new chapters, methodology changes
- MINOR: new content, figures, tables, discussion sections
- PATCH: prose fixes, corrections, formatting

## COG Viewer Embedding

Always use `ngr::ngr_str_viewer_cog()` — never hardcode viewer iframes.

```r
knitr::asis_output(ngr::ngr_str_viewer_cog("https://bucket.s3.us-west-2.amazonaws.com/ortho.tif"))
```

The function includes a cache-busting `?v=` parameter. Bump `v` in the function default when `viewer.html` has breaking changes.

## Dependency Management

Use `renv` for reproducible package management:
- `.Rprofile` activates renv on startup
- `renv::restore()` installs from lockfile
- `renv::snapshot()` updates lockfile after adding packages
- Use `pak::pak("pkg")` to install (not `install.packages`)

## Known Drift

Production repos (2024-2025) have drifted from templates in these areas. When working in a child repo, match what that repo does, not the template:

- **Script naming in `02_reporting/`** — older repos use `tables.R`, `0165-read-sqlite.R`; newer repos use numbered `0130-tables.R`. Follow the repo you're in.
- **Removed packages** — `elevatr`, `rayshader`, `arrow` removed from production but still in template.
- **`staticimports::import()` call** — some repos skip it and source `staticimports.R` directly.
- **Hardcoded vs parameterized years** — older repos hardcode years in file paths; newer repos use `params$project_year`. Prefer parameterized.

# Cartography

## Style Registry

Use the `gq` package for all shared layer symbology. Never hardcode hex color values when a registry style exists.

```r
library(gq)
reg <- gq_reg_main()  # load once per script — 51+ layers
```

**Core pattern:** `reg$layers$lake`, `reg$layers$road`, `reg$layers$bec_zone`, etc.

### Translators

| Target | Simple layer | Classified layer |
|--------|-------------|-----------------|
| tmap | `gq_tmap_style(layer)` → `do.call(tm_polygons, ...)` | `gq_tmap_classes(layer)` → field, values, labels |
| mapgl | `gq_mapgl_style(layer)` → paint properties | `gq_mapgl_classes(layer)` → match expression |

### Custom styles

For project-specific layers not in the main registry, use a hand-curated CSV and merge:

```r
reg <- gq_reg_merge(gq_reg_main(), gq_reg_read_csv("path/to/custom.csv"))
```

Install: `pak::pak("NewGraphEnvironment/gq")`

## Map Targets

| Output | Tool | When |
|--------|------|------|
| PDF / print figures | `tmap` v4 | Bookdown PDF, static reports |
| Interactive HTML | `mapgl` (MapLibre GL) | Bookdown gitbook, memos, web pages |
| QGIS project | Native QML | Field work, Mergin Maps |

## Key Rules

- **`sf_use_s2(FALSE)`** at top of every mapping script
- **Compute area BEFORE simplify** in SQL
- **No map title** — title belongs in the report caption
- **Legend over least-important terrain** — swap legend and logo sides when it reduces AOI occlusion. No fixed convention for which side.
- **Four-corner rule** — legend, logo, scale bar, keymap each get their own corner. Never stack two in the same quadrant.
- **Bbox must match canvas aspect ratio** — compute the ratio from geographic extents and page dimensions. Mismatch causes white space bands.
- **Consistent element-to-frame spacing** — all inset elements should have visually equal margins from the frame edge
- **Map fills to frame** — basemap extends edge-to-edge, no dead bands. Use near-zero `inner.margins` and `outer.margins`.
- **Suppress auto-legends** — build manual ones from registry values
- **ALL CAPS labels appear larger** — use title case for legend labels (gq `gq_tmap_classes()` handles this automatically via `to_title()` fallback)

## Self-Review (after every render)

Read the PNG and check before showing anyone:

1. Correct polygon/study area shown? (verify source data, not just the bbox)
2. Map fills the page? (no white/black bands)
3. Keymap inside frame with spacing from edge?
4. No element overlap? (each in its own corner)
5. Legend over least-important terrain?
6. Consistent spacing across all elements?
7. Scale bar breaks appropriate for extent?

See the `cartography` skill for full reference: basemap blending, BC spatial data queries, label hierarchy, mapgl gotchas, and worked examples.

## Land Cover Change

Use [drift](https://github.com/NewGraphEnvironment/drift) and [flooded](https://github.com/NewGraphEnvironment/flooded) together for riparian land cover change analysis. flooded delineates floodplain extents from DEMs and stream networks; drift tracks what's changing inside them over time.

**Pipeline:**

```r
# 1. Delineate floodplain AOI (flooded)
valleys <- flooded::fl_valley_confine(dem, streams)

# 2. Fetch, classify, summarize (drift)
rasters   <- drift::dft_stac_fetch(aoi, source = "io-lulc", years = c(2017, 2020, 2023))
classified <- drift::dft_rast_classify(rasters, source = "io-lulc")
summary    <- drift::dft_rast_summarize(classified, unit = "ha")

# 3. Interactive map with layer toggle
drift::dft_map_interactive(classified, aoi = aoi)
```

- Class colors come from drift's shipped class tables (IO LULC, ESA WorldCover)
- For production COGs on S3, `dft_map_interactive()` serves tiles via titiler — set `options(drift.titiler_url = "...")`
- See the [drift vignette](https://www.newgraphenvironment.com/drift/articles/neexdzii-kwa.html) for a worked example (Neexdzii Kwa floodplain, 2017-2023)

# Code Check Conventions

Structured checklist for reviewing diffs before commit. Used by `/code-check`.
Add new checks here when a bug class is discovered — they compound over time.

## Shell Scripts

### Quoting
- Variables in double-quoted strings containing single quotes break if value has `'`
- `"echo '${VAR}'"` — if VAR contains `'`, shell syntax breaks
- Use `printf '%s\n' "$VAR" | command` to pipe values safely
- Heredocs: unquoted `<<EOF` expands variables locally, `<<'EOF'` does not — know which you need

### Paths
- Hardcoded absolute paths (`/Users/airvine/...`) break for other users
- Use `REPO_ROOT="$(cd "$(dirname "$0")/<relative>" && pwd)"`
- After moving scripts, verify `../` depth still resolves correctly
- Usage comments should match actual script location

### Silent Failures
- `|| true` hides real errors — is the failure actually safe to ignore?
- Empty variable before destructive operation (rm, destroy) — add guard: `[ -n "$VAR" ] || exit 1`
- `grep` returning empty silently — downstream commands get empty input

### Process Visibility
- Secrets passed as command-line args are visible in `ps aux`
- Use env files, stdin pipes, or temp files with `chmod 600` instead

## Cloud-Init (YAML)

### ASCII
- Must be pure ASCII — em dashes, curly quotes, arrows cause silent parse failure
- Check with: `perl -ne 'print "$.: $_" if /[^\x00-\x7F]/' file.yaml`

### State
- `cloud-init clean` causes full re-provisioning on next boot — almost never what you want before snapshot
- Use `tailscale logout` not `tailscale down` before snapshot (deregister vs disconnect)

### Template Variables
- Secrets rendered via `templatefile()` are readable at `169.254.169.254` metadata endpoint
- Acceptable for ephemeral machines, document the tradeoff

## OpenTofu / Terraform

### State
- Parsing `tofu state show` text output is fragile — use `tofu output` instead
- Missing outputs that scripts need — add them to main.tf
- Snapshot/image IDs in tfvars after deleting the snapshot — stale reference

### Destructive Operations
- Validate resource IDs before destroy: `[ -n "$ID" ] || exit 1`
- `tofu destroy` without `-target` destroys everything including reserved IPs
- Snapshot ID extraction: use `--resource droplet` and `grep -F` for exact match

## Security

### Secrets in Committed Files
- `.tfvars` must be gitignored (contains tokens, passwords)
- `.tfvars.example` should have all variables with empty/placeholder values
- Sensitive variables need `sensitive = true` in variables.tf

### Firewall Defaults
- `0.0.0.0/0` for SSH is world-open — document if intentional
- If access is gated by Tailscale, say so explicitly

### Credentials
- Passwords with special chars (`'`, `"`, `$`, `!`) break naive shell quoting
- `printf '%q'` escapes values for shell safety
- Temp files for secrets: create with `chmod 600`, delete after use

## R / Package Installation

### pak Behavior
- pak stops on first unresolvable package — all subsequent packages are skipped
- Removed CRAN packages (like `leaflet.extras`) must move to GitHub source
- PPPM binaries may lag a few hours behind new CRAN releases

### Reproducibility
- Branch pins (`pkg@branch`) are not reproducible — document why used
- Pinned download URLs (RStudio .deb) go stale — document where to update

## General

### Documentation Staleness
- Moving/renaming scripts: update CLAUDE.md, READMEs, usage comments
- New variables: update .tfvars.example
- New workflows: update relevant README

# Communications Conventions

Standards for external communications across New Graph Environment.

[compost](https://github.com/NewGraphEnvironment/compost) is the working repo for email drafts, scripts, contact management, and Gmail utilities. These conventions capture the universal principles; compost has the implementation details.

## Tone

Three levels. Default to casual unless context dictates otherwise.

| Level | When | Style |
|-------|------|-------|
| **Casual** | Established working relationships | Professional but warm. Direct, concise. No slang. |
| **Very casual** | Close collaborators with rapport | Colloquial OK. Light humor. Slang acceptable. |
| **Formal** | New contacts, senior officials, formal requests | Full sentences, no contractions, state purpose early. |

**Collaborative, not directive.** Acknowledge their constraints:

- **Avoid:** "Work these in as makes sense for your lab"
- **Better:** "If you're able to work these in when it fits your schedule that would be really helpful"

## Email Workflow

Draft in markdown, convert to HTML at send time via gmailr. See compost for script templates, OAuth setup, and `search_gmail.R`.

**File naming:** `YYYYMMDD_recipient_topic_draft.md` + `YYYYMMDD_recipient_topic.R`

**Key gotchas** (documented in detail in compost):
- Gmail strips `<style>` blocks — use inline styles for tables
- `gm_create_draft()` does NOT support `thread_id` — only `gm_send_message()` can reply into threads. Drafts land outside the conversation.
- Always use `test_mode` and `create_draft` variables for safe workflows

## Data in Emails

- **Never manually type data into tables** — generate programmatically from source files
- **Link to canonical sources** (GitHub repos, public reports) rather than embedding raw data
- **Provide both CSV and Excel** when sharing tabular data
- **Document ID codes** — when using compressed IDs (e.g., `id_lab`), include a reference sheet so recipients can decode

## What Not to Expose Externally

- Internal QA info (blanks, control samples, calibration data)
- Internal tracking codes or SRED references
- Draft status or revision history
- Internal project management details

Keep client-facing communications focused on deliverables and technical content.

## Signature

```
Al Irvine B.Sc., R.P.Bio.
New Graph Environment Ltd.

Cell: 250-777-1518
Email: al@newgraphenvironment.com
Website: www.newgraphenvironment.com
```

In HTML emails, use `<br>` tags between lines.

# LLM Behavioral Guidelines

<!-- Source: https://github.com/forrestchang/andrej-karpathy-skills/main/CLAUDE.md -->
<!-- Last synced: 2026-02-06 -->
<!-- These principles are hardcoded locally. We do not curl at deploy time. -->
<!-- Periodically check the source for meaningful updates. -->

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

# New Graph Environment Conventions

Core patterns for professional, efficient workflows across New Graph Environment repositories.

## Ecosystem Overview

Five repos form the governance and operations layer across all New Graph Environment work:

| Repo | Purpose | Analogy |
|------|---------|---------|
| [compass](https://github.com/NewGraphEnvironment/compass) | Ethics, values, guiding principles | The "why" |
| [soul](https://github.com/NewGraphEnvironment/soul) | Standards, skills, conventions for LLM agents | The "how" |
| [compost](https://github.com/NewGraphEnvironment/compost) | Communications templates, email workflows, contact management | The "who" |
| [rtj](https://github.com/NewGraphEnvironment/rtj) (formerly awshak) | Infrastructure as Code, deployment | The "where" |
| [gq](https://github.com/NewGraphEnvironment/gq) | Cartographic style management across QGIS, tmap, leaflet, web | The "look" |

**Adaptive management:** Conventions evolve from real project work, not theory. When a pattern is learned or refined during project work, propagate it back to soul so all projects benefit. The `/claude-md-init` skill builds each project's `CLAUDE.md` from soul conventions.

**Cross-references:** [sred-2025-2026](https://github.com/NewGraphEnvironment/sred-2025-2026) tracks R&D activities across repos. Compost cross-cuts all projects as the centralized communications workflow — email drafts, contact registry, and tone guidelines live there and are copied to individual project `communications/` folders as needed.

## Issue Workflow

### Before Creating an Issue (non-negotiable)

1. **Check for duplicates:** `gh issue list --state open --search "<keywords>"` -- search before creating
2. **Link to SRED:** If work involves infrastructure, R&D, tooling, or performance benchmarking, add `Relates to NewGraphEnvironment/sred-2025-2026#N` (match by repo name in SRED issue title)
3. **One issue, one concern.** Keep focused.

### Professional Issue Writing

Write issues with clear technical focus:

- **Use normal technical language** in titles and descriptions
- **Focus on the problem and solution** approach
- **Add tracking links at the end** (e.g., `Relates to Owner/repo#N`)

**Issue body structure:**
```markdown
## Problem
<what's wrong or missing>

## Proposed Solution
<approach>

Relates to #<local>
Relates to NewGraphEnvironment/sred-2025-2026#<N>
```

### GitHub Issue Creation - Always Use Files

The `gh issue create` command with heredoc syntax fails repeatedly with EOF errors. ALWAYS use `--body-file`:

```bash
cat > /tmp/issue_body.md << 'EOF'
## Problem
...

## Proposed Solution
...
EOF

gh issue create --title "Brief technical title" --body-file /tmp/issue_body.md
```

## Closing Issues

**DO:** Close issues via commit messages. The commit IS the closure and the documentation.

```
Fix broken DEM path in loading pipeline

Update hardcoded path to use config-driven resolution.

Fixes #20
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

**DON'T:** Close issues with `gh issue close`. This breaks the audit trail — there's no linked diff showing what changed.

- `Fixes #N` or `Closes #N` — auto-closes and links the commit to the issue
- `Relates to #N` — partial progress, does not close
- Always close issues when work is complete. Don't leave stale open issues.

## Commit Quality

Write clear, informative commit messages:

```
Brief description (50 chars or less)

Detailed explanation of changes and impact.

Fixes #<issue> (or Relates to #<issue>)
Relates to NewGraphEnvironment/sred-2025-2026#<N>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

**When to commit:**
- Logical, atomic units of work
- Working state (tests pass)
- Clear description of changes

**What to avoid:**
- "WIP" or "temp" commits in main branch
- Combining unrelated changes
- Vague messages like "fixes" or "updates"

## LLM Agent Conventions

Rules learned from real project sessions. These apply across all repos.

- **Install missing packages, don't workaround** — if a package is needed, ask the user to install it (e.g. `pak::pak("pkg")`). Don't write degraded fallback code to avoid the dependency.
- **Never hardcode extractable data** — if coordinates, station names, or metadata can be pulled from an API or database at runtime, do that. Don't hardcode values that have a programmatic source.
- **Close issues via commits, not `gh issue close`** — see Closing Issues above.
- **Cite primary sources** — see references conventions.

## Naming Conventions

**Pattern: `noun_verb-detail`** -- noun first, verb second across all naming:

| What | Example |
|------|---------|
| Skills | `claude-md-init`, `gh-issue-create`, `planning-update` |
| Scripts | `stac_register-baseline.sh`, `stac_register-pypgstac.sh` |
| Logs | `20260209_stac_register-baseline_stac-dem-bc.txt` |
| Log format | `yyyymmdd_noun_verb-detail_target.ext` |

Scripts and logs live together: `scripts/<module>/logs/`

## Projects vs Milestones

- **Projects** = daily cross-repo tracking (always add to relevant project)
- **Milestones** = iteration boundaries (only for release/claim prep)
- Don't double-track unless there's a reason

| Content | Project |
|---------|---------|
| R&D, experiments, SRED-related | **SRED R&D Tracking (#8)** |
| Data storage, sqlite, postgres, pipelines | **Data Architecture (#9)** |
| Fish passage field/reporting | **Fish Passage 2025 (#6)** |
| Restoration planning | **Aquatic Restoration Planning (#5)** |
| QGIS, Mergin, field forms | **Collaborative GIS (#3)** |

# R Package Development Conventions

Standards for R package development across New Graph Environment repositories.
Based on [R Packages (2e)](https://r-pkgs.org/) by Hadley Wickham and Jenny Bryan.

**Reference packages:** When starting a new package, study these existing
packages for patterns: `flooded`, `gq`. They demonstrate the conventions below
in practice (DESCRIPTION fields, README layout, NEWS.md style, pkgdown setup,
test structure, hex sticker, etc.).

## Style

- tidyverse style guide: snake_case, pipe operators (`|>` or `%>%`)
- Match existing patterns in each codebase
- Use `pak` for package installation (not `install.packages`)
- Prefix column name vectors with `cols_` for discoverability in the
  environment pane: `cols_all`, `cols_carry`, `cols_split`, `cols_writable`.
  Same principle for other grouped vectors (`params_`, `tbl_`, etc.)

## Package Structure

Follow R Packages (2e) conventions:
- `R/` for functions, `tests/testthat/` for tests, `man/` for docs
- `DESCRIPTION` with proper fields (Title, Description, Authors@R)
- `DESCRIPTION` URL field: include both the GitHub repo and the pkgdown site
  so pkgdown links correctly (e.g., `URL: https://github.com/OWNER/PKG,
  https://owner.github.io/PKG/`)
- `NAMESPACE` managed by roxygen2 (`#' @export`, `#' @import`, `#' @importFrom`)
- Never edit `NAMESPACE` or `man/` by hand

## One Function, One File

Each exported function gets its own R file and its own test file:
- `R/fl_mask.R` → `tests/testthat/test-fl_mask.R`
- Commit the function and its tests together
- Use `Fixes #N` in the commit message to close the corresponding issue

## GitHub Issues and SRED Tracking

### Issue-per-function workflow

File a GitHub issue for each function before building it. This creates a
traceable record of what was planned, built, and verified.

### Branching for SRED

For new packages or major features, work on a branch and merge via PR:

```
main ← scaffold-branch (PR closes with "Relates to NewGraphEnvironment/sred-2025-2026#N")
```

This gives one PR that contains all commits — a single SRED cross-reference
covers the entire body of work. Individual commits within the branch close
their respective function issues with `Fixes #N`.

### Closing issues

Close function issues via commit messages — see Closing Issues in newgraph conventions.

## Testing

- Use testthat 3e (`Config/testthat/edition: 3` in DESCRIPTION)
- Run `devtools::test()` before committing
- Test files mirror source: `R/utils.R` -> `tests/testthat/test-utils.R`
- Test for edge cases and potential failures, not just happy paths
- Tests must pass before closing the function's issue
- Always grep for errors in the same command as the test run to avoid
  running twice:
  ```bash
  Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5
  ```
  For error context: `grep -E "(ERROR:|FAIL )" -A 10 | head -25`

## Examples and Vignettes

### Runnable examples on every exported function

Examples are how users discover what a function does. They must:
- **Actually run** — no `\dontrun{}` unless external resources are required
- **Use bundled test data** via `system.file()` so they work for anyone
- **Show why the function is useful** — not just that it runs, but what it
  produces and why you'd use it
- **Use qualified names** for non-exported dependencies (`terra::rast()`,
  `sf::st_read()`) since examples run in the user's environment

### Vignettes

At least one vignette showing the full pipeline on real data:
- Demonstrates the package solving an actual problem end-to-end
- Uses bundled test data (committed to `inst/testdata/`)
- Hosted on pkgdown so users can read it without installing

**Output format:** Use `bookdown::html_vignette2` (not
`rmarkdown::html_vignette`) for figure numbering and cross-references.
Requires `bookdown` in Suggests and chunks must have `fig.cap` for
numbered figures. Cross-reference with `Figure \@ref(fig:chunk-name)`.

**Vignettes that need external resources (DB, API, STAC):** Do NOT use
the `.Rmd.orig` pre-knit pattern — it breaks `bookdown` figure numbering
because knitr evaluates chunks during pre-knit and emits `![](path)`
markdown that bookdown can't number.

Instead, separate data generation from presentation:
1. `data-raw/vignette_data.R` — runs the queries, saves results as `.rds`
   to `inst/testdata/` (or `inst/vignette-data/`)
2. Vignette loads `.rds` files, all chunks run live during pkgdown build
3. Note at top of vignette: "Data generated by `data-raw/script.R`"
4. bookdown controls all chunks — figure numbers, cross-refs work

This is the same pattern as test data: `data-raw/` documents how the data
was produced, committed artifacts make vignettes reproducible without the
external resource.

### Test data

- Created via a script in `data-raw/` that documents exactly how the data
  was produced (database queries, spatial crops, etc.)
- Committed to `inst/testdata/` — small enough to ship with the package
- Used by tests, examples, and vignettes — one dataset, three purposes

## Documentation

- roxygen2 for all exported functions
- `@import` or `@importFrom` in the package-level doc (`R/<pkg>-package.R`)
  to populate NAMESPACE — don't rely on `::` everywhere in function bodies
- pkgdown site for public packages with `_pkgdown.yml` (bootstrap 5)
- GitHub Action for pkgdown (`usethis::use_github_action("pkgdown")`)

## lintr

Run `lintr::lint_package()` before committing R package code. Fix all warnings — every lint should be worth fixing.

### Recommended .lintr config

```r
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
- Suppress commented code lints (exploratory R scripts often have commented alternatives)
- Exclude renv directory entirely

## Dependencies

- Minimize Imports — use `Suggests` for packages only needed in tests/vignettes
- Pin versions only when breaking changes are known
- Prefer packages already in the tidyverse ecosystem

## Releasing

1. Update `NEWS.md` — keep it concise:
   - First release: one line (e.g., "Initial release. Brief description.")
   - Later releases: describe what changed and why, not function-by-function.
     Link to the pkgdown reference page for details — don't duplicate it.
   - Don't list every function; the pkgdown reference page is the single
     source of truth for what's in the package.
2. Bump version in `DESCRIPTION` (e.g., `0.0.0.9000` → `0.1.0`)
3. Commit as "Release vX.Y.Z"
4. Tag: `git tag vX.Y.Z && git push && git push --tags`

## Repository Setup

### Branch protection

Protect main from deletion and force pushes:

```bash
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

Keep a `dev/dev.R` file that documents every setup step. Not idempotent —
run interactively. This is the reproducible recipe for the package scaffold.

## README

Keep the README lean:
- Hex sticker, one-line description, install, example showing *why* it's
  useful
- Link to pkgdown vignette and function reference — don't duplicate them
- Don't maintain a function table — it's just another thing to keep updated
  and pkgdown's reference page is the single source of truth

## LLM Workflow

When an LLM assistant modifies R package code:
1. Run `lintr::lint_package()` — fix issues before committing
2. Run `devtools::test()` with error grep — ensure tests pass in one call:
   ```bash
   Rscript -e 'devtools::test()' 2>&1 | grep -E "(FAIL|ERROR|PASS)" | tail -5
   ```
3. Run `devtools::document()` and grep for results:
   ```bash
   Rscript -e 'devtools::document()' 2>&1 | grep -E "(Writing|Updating|warning)" | tail -10
   ```
4. Check `devtools::check()` passes for releases — capture results in one call:
   ```bash
   Rscript -e 'devtools::check()' 2>&1 | grep -E "(ERROR|WARNING|NOTE|errors|warnings|notes)" | tail -10
   ```

# Reference Management Conventions

How references flow between Claude Code, Zotero, and technical writing at New Graph Environment.

## Tool Routing

Three tools, different purposes. Use the right one.

| Need | Tool | Why |
|------|------|-----|
| Search by keyword, read metadata/fulltext, semantic search | **MCP `zotero_*` tools** | pyzotero, works with Zotero item keys |
| Look up by citation key (e.g., `irvine2020ParsnipRiver`) | **`/zotero-lookup` skill** | Citation keys are a BBT feature — pyzotero can't resolve them |
| Create items, attach PDFs, deduplicate | **`/zotero-api` skill** | Connector API for writes, JS console for attachments |

**Citation keys vs item keys:** Citation keys (like `irvine2020ParsnipRiver`) come from Better BibTeX. Item keys (like `K7WALMSY`) are native Zotero. The MCP works with item keys. `/zotero-lookup` bridges citation keys to item data.

**BBT citation key storage:** As of Feb 2025+, BBT stores citation keys as a `citationKey` field directly in `zotero.sqlite` (via Zotero's item data system), not in a separate BBT database. The old `better-bibtex.sqlite` and `better-bibtex.migrated` files are stale and no longer updated. Query citation keys with: `SELECT idv.value FROM items i JOIN itemData id ON i.itemID = id.itemID JOIN itemDataValues idv ON id.valueID = idv.valueID JOIN fields f ON id.fieldID = f.fieldID WHERE f.fieldName = 'citationKey'`.

## Adding References Workflow

### 1. Search and flag

When research turns up a reference:
- **DOI available:** Tell the user — Zotero's magic wand (DOI lookup) is the fastest path
- **ResearchGate link:** Flag to user for manual check — programmatic fetch is blocked (403), but full text is often there
- **BC gov report:** Search [ACAT](https://a100.gov.bc.ca/pub/acat/), for.gov.bc.ca library, EIRS viewer
- **Paywalled:** Note it, move on. Don't waste time trying to bypass.

### 2. Add to Zotero

**Preferred order:**
1. DOI magic wand in Zotero UI (fastest, most complete metadata)
2. Web API POST with `collections` array (grey literature, local PDFs — targets collection directly, no UI interaction needed)
3. `saveItems` via `/zotero-api` (batch creation from structured data — requires UI collection selection)
4. JS console script for group library (when connector can't target the right collection)

**Collection targeting:** `saveItems` drops items into whatever collection is selected in Zotero's UI. Always confirm with the user before calling it. **Web API bypasses this** — include `"collections": ["KEY"]` in the POST body. Find collection keys with `?q=name` search on the collections endpoint.

### 3. Attach PDFs

`saveItems` attachments silently fail. Don't use them. Instead:

1. **Web API S3 upload (preferred):** Create attachment item → get upload auth → build S3 body (Python: prefix + file bytes + suffix) → POST to S3 → register with uploadKey. Works without Zotero running. See `/zotero-api` skill section 4.
2. **JS console fallback:** Download with `curl`, attach via `item_attach_pdf.js` in Zotero JS console.
3. Verify attachment exists via MCP: `zotero_get_item_children`

### 4. Verify

After manual adds, confirm via MCP:
- `zotero_search_items` — find by title
- `zotero_get_item_metadata` — check fields are complete
- `zotero_get_item_children` — confirm PDF attached

### 5. Clean up

If duplicates were created (common with `saveItems` retries):
- Run `collection_dedup.js` via Zotero JS console
- It keeps the copy with the most attachments, trashes the rest

## In Reports (bookdown)

### Bibliography generation

```yaml
# index.Rmd — dynamic bib from Zotero via Better BibTeX
bibliography: "`r rbbt::bbt_write_bib('references.bib', overwrite = TRUE)`"
```

`rbbt` pulls from BBT, which syncs with Zotero. Edit references in Zotero → rebuild report → bibliography updates.

**Library targeting:** rbbt must know which Zotero library to search. This is set globally in `~/.Rprofile`:

```r
# default library — NewGraphEnvironment group (libraryID 9, group 4733734)
options(rbbt.default.library_id = 9)
```

Without this option, rbbt searches only the personal library (libraryID 1) and won't find group library references. The library IDs map to Zotero's internal numbering — use `/zotero-lookup` with `SELECT DISTINCT libraryID FROM citationkey` against the BBT database to discover available libraries.

### Citation syntax

- `[@key2020]` — parenthetical: (Author 2020)
- `@key2020` — narrative: Author (2020)
- `[@key1; @key2]` — multiple
- `nocite:` in YAML — include uncited references

### Cite primary sources

When a review paper references an older study, trace back to the original and cite it. Don't attribute findings to the review when the original exists. (See LLM Agent Conventions in `newgraph.md`.)

**When the original is unavailable** (paywalled, out of print, can't locate): use secondary citation format in the prose and include bib entries for both sources:

> Smith et al. (2003; as cited in Doctor 2022) found that...

Both `@smith2003` and `@doctor2022` go in the `.bib` file. The reader can then track down the original themselves. Flag incomplete metadata on the primary entry — it's better to have a partial reference than none at all.

## PDF Fallback Chain

When you need a PDF and the obvious URL doesn't work:

1. DOI resolver → publisher site (often has OA link)
2. Europe PMC (`europepmc.org/backend/ptpmcrender.fcgi?accid=PMC{ID}&blobtype=pdf`) — ncbi blocks curl
3. SciELO — needs `User-Agent: Mozilla/5.0` header
4. ResearchGate — flag to user for manual download
5. Semantic Scholar — sometimes has OA links
6. Ask user for institutional access

Always verify downloads: `file paper.pdf` should say "PDF document", not HTML.

## Searching Paper Content (ragnar)

### Setup (per project)
- `scripts/rag_build.R` — maps citation keys to Zotero PDF attachment keys, builds DuckDB
- `data/rag/` gitignored — store is local, not committed
- Dependencies: ragnar, Ollama with nomic-embed-text model
- See `/lit-search` skill for full recipe

### Query
`ragnar_store_connect()` then `ragnar_retrieve()` — returns chunks with source file attribution.

### Anti-patterns
- NEVER write abstracts manually — if CrossRef has no abstract, leave blank
- NEVER cite specific numbers without verifying from the source PDF via ragnar search
- NEVER paraphrase equations — copy exact notation and cite page/section

# SRED Conventions

How SR&ED tracking integrates with New Graph Environment's development workflows.

## The Claim: One Project

All SRED-eligible work across NGE falls under a **single continuous project**:

> **Dynamic GIS-based Data Processing and Reporting Framework**

- **Field:** Software Engineering (2.02.09)
- **Start date:** May 2022
- **Fiscal year:** May 1 – April 30
- **Consultant:** Boast Capital (prepares final technical report)

**Do not fragment work into separate claims.** Each fiscal year's work is structured as iterations within this one project. Internal tracking (experiment numbers in `sred-2025-2026`) maps to iterations — Boast assembles the final narrative.

## Tagging Work for SRED

### Commits

Use `Relates to NewGraphEnvironment/sred-2025-2026#N` in commit messages when work is SRED-eligible.

### Time entries (rolex)

Tag hours with `sred_ref` field linking to the relevant `sred-2025-2026` issue number.

### GitHub issues

Link SRED-eligible issues to the tracking repo: `Relates to NewGraphEnvironment/sred-2025-2026#N`

## What Qualifies as SRED

**Eligible (systematic investigation to overcome technological uncertainty):**
- Building tools/functions that don't exist in standard practice
- Prototyping new integrations between systems (GIS ↔ reporting ↔ field collection)
- Testing whether an approach works and documenting why it did/didn't
- Iterating on failed approaches with new hypotheses

**Not eligible:**
- Standard configuration of known tools
- Routine bug fixes in working systems
- Writing reports using the framework (that's service delivery)

**The test:** "Did we try something we weren't sure would work, and did we learn something from the attempt?" If yes, it's likely eligible.
