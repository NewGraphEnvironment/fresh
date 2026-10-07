# Code check, round 3: R CMD check fixes (diff_checkfix.patch)

Verdict: **the diff is clean.** It introduces nothing that fails or loses data. Every sweep
of the mechanism below came back empty except one place, F1. F1 is pre-existing, but it
sits in the paragraph of `R/frs_habitat_predicates.R` that this diff edits.

## The mechanism

**An exported function's contract changes, or its docs are written against a contract it
never had, and the only callers left behind are ones nothing executes.**

No fresh function takes `...` (checked: 0 of 122 functions in the namespace). So a stale
named argument errors the moment it runs. These defects survive only where code never
runs:

- `\dontrun{}` examples
- non-evaluated vignette chunks
- `data-raw/` scripts
- roxygen prose and inherited `@param` text
- unit tests whose mock takes `...`. Such a mock accepts whatever the caller sends, so
  the one test that does reach the call cannot see a dropped argument.

R CMD check's `checkUsage` covers function bodies in `R/` only. It does not see examples,
vignettes, `data-raw/` or prose.

Mapping the earlier findings onto this:

| earlier finding | changed contract | stale caller |
|---|---|---|
| `frs_break()` and `frs_habitat_access()` passing point-mode args | `frs_break_find()` lost point mode in #95 | body args hidden behind `...` mocks (`frs_break_find` stub) |
| vignette chunk, `data-raw/pipeline_wsg.R`, `data-raw/vignette_habitat_pipeline.R` | same | non-evaluated chunk, unexecuted scripts |
| `frs_col_join` example and unit test passing `"(...) sub"` | `from` gets wrapped as `(<from>) _src` | `\dontrun` example; a test that mocks the DB, so the SQL never meets Postgres |
| `gate` doc saying "downstream" | the doc was never checked against the SQL | prose, newly inherited into `frs_habitat` |

## Enumeration: everywhere the mechanism reaches

| sweep | scope | result |
|---|---|---|
| Static call check: named args against the callee's real `formals()`, positional overflow, string literal passed as `conn` | 1,789 calls to fresh functions in 176 files: `R/`, `tests/`, `data-raw/`, `scripts/`, `dev/`, `inst/`, `vignettes/*.Rmd` and `*.Rmd.orig` (every chunk, including non-evaluated), `README.md`, `man/*.Rd` examples with `\dontrun` expanded, `planning/active/` | **0 unknown named args** outside `inst/issues/design-habitat-models.md` (40 hits; that file is an accepted design note). 0 positional overflows. **1 string passed as `conn`: `man/frs_habitat_predicates.Rd`, see F1.** The other string-as-`conn` hits are tests passing `"mock"` / `"mock_conn"` on purpose. |
| Positive control for the sweep above | HEAD versions of `R/frs_break.R`, `R/frs_habitat.R`, the vignette and both `data-raw` scripts | Flags all 5 calls the diff fixes, so the sweep can see the defect class |
| `codetools::checkUsageEnv(asNamespace("fresh"))` after `load_all()` | all of `R/` | 0 "possible error" or "unused argument" lines. Positive control (a call to `frs_break_find(points_table =, aoi =)`) is flagged. The 3 unused-local notes are pre-existing and not defects. |
| `tools::codoc()`, `checkDocFiles()`, `checkDocStyle()` | `man/` against usage | clean |
| `@inheritParams` (5 uses, 17 inherited params) | `frs_break` ← `frs_break_find`; `frs_habitat` ← `frs_habitat_classify`, `frs_network_segment`; 2 internal | every inherited param has the same default in the source and the inheritor. Each one is forwarded. |
| Removed `@param`s across git history (#43, #71, #81, #94, #95, #129, #162, #174, #177, #213, #214, #240) | grep for `blocking_labels`, `params_all`, `long_value_col`, `falls_where`, `observations`, `points_where` and others in code and docs | only local variable names (`params_all`) match, so no stale references |
| Downstream: `../link` | 278 files, 46 `fresh::` calls | 0 unknown args. No `frs_break(` callers. |

### Unit-test mocks that accept `...`, around fresh calls

There are 194 mock bindings in all. 89 take `...`; of those, 69 wrap a fresh function and
20 wrap DBI functions (not fresh API). For every fresh target, each call site in `R/` was
checked statically against the target's real formals, so a swallowed argument is visible
even where the mock hides it.

| test file (lines) | mock form | fresh target | callers in `R/` | statically clean |
|---|---|---|---|---|
| test-frs_break.R (262, 286, 308) | `stub(frs_break)` | `frs_break_find`, `frs_break_apply`, `frs_break_validate` | `frs_break` | yes. The new test also asserts names against formals. |
| test-frs_habitat.R (614) | `stub(frs_habitat_access)` via `capture()` | `frs_break_find`, `frs_feature_find` | `frs_habitat_access` | yes. The new test asserts names against formals. |
| test-frs_habitat.R (614) | stub | `.frs_enrich_breaks`, `.frs_index_working` | `frs_habitat`, `frs_habitat_access`, `frs_network_segment`, `frs_extract`, `frs_feature_index`, `frs_habitat_classify`, `frs_barriers_minimal` | yes |
| test-frs_habitat.R (550, 584) | `local_mocked_bindings` | `frs_cluster`, `.frs_connected_waterbody` | `.frs_run_connectivity` | yes |
| test-frs_barriers_minimal.R (29, 50, 70) | `local_mocked_bindings` | `.frs_db_execute` | 41 internal and exported callers | yes. Every call is `(conn, sql)`. |
| test-frs_network*.R, test-frs_stream_fetch.R, test-frs_watershed_at_measure.R, test-frs_waterbody_network.R, test-frs_point_snap.R, test-frs_network_prune.R, test-frs_order_child.R (about 60 sites) | `frs_db_query = function(conn, sql, ...)` | `frs_db_query(conn, query)` | 16 fetch and network functions | yes. All callers pass `query` by position. The mock calls it `sql`, which is harmless. |
| test-frs_watershed_split.R (19, 30, 50, 107, 132) | `stub(frs_watershed_split)` | `frs_point_snap`, `frs_watershed_at_measure` | `frs_watershed_split`, `.frs_feature_find_points` | yes |

Mocks with fixed signatures, such as `.frs_db_execute = function(conn, sql)`, fail loudly
on an extra argument, so they cannot hide this class of defect.

## Findings

### F1 (docs: an example and a parameter users will act on): `frs_habitat_predicates()` documents an input shape it rejects, and an example that errors

- **Where:** `R/frs_habitat_predicates.R`, which regenerates `man/frs_habitat_predicates.Rd`.
  - Lines 3-4: "takes one species' rules + ranges from [frs_habitat_species()]".
  - Lines 17-22: "when `sp_params$rules$<spawn|rear>` is non-NULL ...". This is the
    sentence the diff edits.
  - Lines 46-49 (`@param sp_params`): "produced by one element of [frs_habitat_species()].
    Must contain `species_code`, `spawn_gradient_min`, `spawn_gradient_max`, `ranges`,
    optionally `rules` ...".
  - Line 66 (example): `species_params <- frs_habitat_species("CO", params, params_fresh)`,
    then `frs_habitat_predicates(species_params[[1]])`.
- **What's wrong:**
  - `frs_habitat_species()` is the DB pipeline step
    `(conn, species_code, base_tbl, breaks, breaks_habitat, params_sp, fresh_sp, to)`. It
    returns `conn` invisibly and does not return params.
  - `frs_habitat_predicates()` reads `sp_params$params_sp$ranges` and
    `sp_params$params_sp$rules` (lines 87+). It stops if `params_sp` is missing. Top-level
    `ranges` and `rules` are never read.
  - The list it really takes is built inline in `frs_habitat_classify()`
    (`R/frs_habitat_classify.R:196-208`):
    `list(species_code, access_gradient, spawn_gradient_max, spawn_gradient_min, params_sp = frs_params()$<SP>)`.
    The unit-test fixture `tests/testthat/test-frs_habitat_predicates.R:7-33` builds the
    same shape.
- **Verified** with `load_all()`, no DB:
  - The example's first call errors: `is.character(species_code) is not TRUE`.
  - A list built the way the `@param` says
    (`list(species_code, spawn_gradient_min, spawn_gradient_max, ranges, rules)`) errors:
    "sp_params must contain `params_sp`".
  - `list(species_code = "CO", spawn_gradient_min = 0, spawn_gradient_max = p$CO$spawn_gradient_max, params_sp = p$CO)`
    returns the spawn predicate.
- **Why it matters:**
  - This is an exported pure-R function, and its page is the only public description of
    its input. Anyone following the page gets an error and has no way to build a valid
    input.
  - It is the same mechanism as every earlier round: the doc was written in 42427755
    against a contract `frs_habitat_species()` never had, and nothing executes a
    `\dontrun` block.
  - This diff edits line 18 of that paragraph and leaves its wrong path
    (`sp_params$rules`) in place.
- **Fix** (source, then `devtools::document()`):
  - Describe `sp_params` as
    `list(species_code, spawn_gradient_min, spawn_gradient_max, params_sp)`, where
    `params_sp` is one element of `frs_params()` (carrying `ranges`, `rules`,
    `spawn_edge_types`, `rear_edge_types`).
  - Change the description's paths to `sp_params$params_sp$rules$<spawn|rear>` and
    `sp_params$params_sp$ranges`.
  - Drop the `frs_habitat_species()` references.
  - Rewrite the example to build that list from
    `frs_params(csv = system.file("extdata", "parameters_habitat_thresholds.csv", package = "fresh"))`.
    It needs no DB, so it can come out of `\dontrun`.

## Not defects (noted for completeness)

- `tests/testthat/test-frs_habitat_classify.R:47` has a comment,
  `# ... via frs_break_find(label="gradient_15")`. `frs_break_find` no longer takes
  `label`; `frs_feature_find` does. It is a comment only and nothing runs it.
- `frs_break()` forwards no `measure_precision` to `frs_break_apply()`. That is not a
  dropped argument: `frs_break` never had one, and the callee's default (`0L`) applies.
- `data-raw/pipeline_wsg.R` now scopes falls by the working table's BLKs instead of
  `aoi = wsg`. A fall on a shared mainstem BLK downstream of the group now counts as a
  barrier. That matches `frs_network_segment()`, and it is the more correct access
  semantics, so it is not a regression.
