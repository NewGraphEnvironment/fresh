# Review round 1: branch 319 (1d23c8d vs merge-base f3e331d)

## Checklist read

- code-check-infra.md: in full.
- code-check.md: the prose of every H3 under `## Mechanisms` (table rows skipped), and the
  index of "Rules that stand alone", Security and Spreadsheets/PDFs (none of those touch this
  diff beyond the YAML boolean rule, which I checked: no bare y/n/yes/no values are involved).
- code-check-r.md, sections read in full: "R's `yaml` returns a mixed int/float sequence as a
  list, not a numeric vector"; "An `information_schema` lookup by the literal table name misses
  what Postgres resolves"; "A database driver's value is not a base R type — and it fails twice";
  "`sprintf("%g", x)` writes `Inf` and `NA` into SQL as bare words". About 165 headings not read
  in full, judged against the index as not matching any tool or shape in the diff (testthat
  headings were checked against the index lines only).
- code-check-shell.md: no heading read in full (the diff has no shell code), about 115 not read.
- code-check-spatial.md: no heading read in full (no sf/terra/GDAL code in the diff; the
  FWA-specific headings concern route measures and edge types, which the diff does not touch),
  about 110 not read.

## What I checked

- **Tests on the branch tree, run from the review worktree against the live DB
  (NOT_CRAN=true, test_file per file):** frs_col_join 22 passed, frs_params 245 passed (2
  skipped), frs_habitat_predicates 122, near_river_inherit 263, frs_channel_width 101,
  frs_cluster 29, frs_habitat_classify 77, frs_order_child 72, frs_break 87, frs_habitat 94,
  test_table_names 30, habitat_partition_293 106, frs_near_river 55. No failures, no errors.
- **Restored the #267 defect** (put `yaml::read_yaml(path)` back in `.frs_load_rules`): both
  #267 tests go red (3 and 1 failures), so they are real guards.
- **link's rules are unchanged by the loader.** I loaded all 24 rules YAMLs on link
  origin/main (inst/extdata configs, the rules_build_0667 test fixtures, data-raw bundles) plus
  fresh's bundled file through main's and the branch's `.frs_load_rules`: every result
  `identical()`, and none is refused by the new empty-key, range or finiteness checks.
- **#251 does not reach link.** In every one of those files, each species whose spawn rule has
  `requires_connected` (SK, KO) has a first L/W rear rule with `lake_ha_min: 200`, so
  `.frs_run_connectivity()` passes 200 as before. link's runtime rules come from the committed
  rules.yaml files (the configs without one `extends: default`).
- **frs_col_join types for link's two calls are unchanged.** Live comparison of the old
  `information_schema.data_type` lookup with the new `.frs_query_col_types()`:
  channel_width double precision / double precision, channel_width_source text / text,
  stream_order_parent integer / integer. Only USER-DEFINED becomes `ltree` / `geometry`.
  link mocks `frs_col_join` whole in its unit tests and mocks none of the new internals
  (`.frs_query_col_types`, `.frs_col_types_of`, `.frs_habitat_target`).
- Reader behaviour: a UTF-8 BOM file and a CRLF file parse the same through the old and new
  YAML readers.
- `.frs_habitat_target()` uses a named INSERT column list in classify (line 484), so a flag
  column appended at the end of an older table lands in the right place. Its ALTERs are
  autocommitted, ahead of the overwrite transaction, and issued only for missing flags.
- `.frs_connected_waterbody()` no longer references `lhm` anywhere; its only caller is
  `.frs_run_connectivity()`.
- The `lake_rear` bucket and the `rear` predicate both go through `.frs_waterbody_tables()`,
  and `.frs_bucket_connected()` works on waterbody keys, so it covers reservoir lines without
  changes. link's `.lnk_sql_lake_polys()` already expects reservoirs in `lake_rearing`.

## Clean

No issues found.
