# Task: point_snap_tie_sweep.R sends measures at 7 significant digits, so its counts are of rounded measures (#289)


`data-raw/point_snap_tie_sweep.R` builds its `VALUES` list with `format(d$m, scientific = FALSE)` (lines 334-336). `format()` defaults to 7 significant digits and uses one number of decimals for the whole vector, so the sweep does not send the measures it reads:

```r
format(c(1528.8506958829107, 4494.61997946051), scientific = FALSE)
#> "1528.851" "4494.620"
```

The counts in `research/fwa_point_snap.md` from that sweep therefore describe measures rounded this way. That covers the CSV misses, the "4 CSV measures now resolve" list (which includes `crossings.csv` 356355973 @ 4494.61997946051) and the per-state tables. Since #274, fresh sends every route measure at 17 significant digits (`.frs_sql_exact()`), so these counts are not about what fresh sends.

The snapped positions are clamped to whole metres, which `format()` writes exactly when the chunk holds only whole numbers, so they are unaffected. The CSV measures and the 400-stream head-case sample are the ones in question.

## Decided at the gate

Approved by the user at the plan gate, 2026-10-31.


- **Head-case sample goes into the sweep (recommended).** It uses the gate test's
  `blk_top()` definition: the guarded `max(upstream_route_measure)` over 400 blue lines
  by `ORDER BY md5(blue_line_key::text)`. Each top is sent at `%.17g` to
  `fwa_locatealong()` in all three states. This replaces the unrecorded "2 / 218"
  with a scripted, exact count. The alternative is to leave it attributed as
  unrecorded, which the issue body calls into question.
- **Logs are overwritten in place** under `data-raw/logs/indexpoint_266/`. The old
  run stays in git history, and the research note names which counts moved.

## Phase 1: Send exact measures

- [ ] `chunked()`: keys via `sprintf("%d", as.integer(blk))`, measures via
      `vapply(m, .frs_sql_exact, character(1))`
- [ ] Guard: read `m` back from `working.tie266_measures_all`, join it on `id`, and
      `stopifnot(identical(...))` against the R doubles, so a lossy write cannot
      pass silently
- [ ] Write `m` to `sweep_changed.csv` and `sweep_errors.csv` as `%.17g` text, so
      the CSVs carry exactly what was sent
- [ ] Update the header comment (usage, outputs) to match

## Phase 2: Script the head-case sample

- [ ] Base side: create `working.tie266_heads` (400 blue lines by md5, guarded top as
      in `tests/testthat/test-frs_fwapg_gate.R:blk_top()`), and add it to `tbls` so
      it is dropped at start and end
- [ ] Per state: `fwa_locatealong()` over the tops through `chunked()`, counted in
      `summary` (`head_hit`, `head_miss`, `head_error`) and added as a frame in
      `moved`
- [ ] Body line stating the sample rule and the n with a guarded top
- [ ] Smoke run with small `FRESH_SWEEP_*` caps; check that the round-trip guard
      passes and the outputs parse

## Phase 3: Re-run the full sweep

- [ ] Commit first. Run a frozen copy from the repo root
      (`cp` to scratch, `Rscript <copy> b088b43 <both migrations>`), in the
      background with a completion waiter, and not alongside the gated tests
- [ ] Check the header: md5s match, "after the trials: unchanged". Commit the logs

## Phase 4: Revise the record

- [ ] `research/fwa_point_snap.md`: new CSV miss counts per state, the revised
      "now resolve" list, the head-case counts from the script, and which numbers
      moved and which held. Also update the Verified line, drop the 7-digit caveat
      paragraph, and correct "carries them exactly"
- [ ] `tests/testthat/test-frs_fwapg_gate.R:65-69` comment: replace the
      unrecorded 2 / 218 with the scripted count
- [ ] NEWS.md line under the next version's heading (data-raw / research only)
- [ ] Grep `research/`, `CLAUDE.md` and `planning/` (not archive) for "218",
      "42", "38" and "4 CSV" to find other restatements

## Owed at the end (reported, done after merge)

- [ ] None expected. If the head-case count changes the gate test's premise
      (`head_blk` 360447231 no longer a head case), file it rather than fold it in

## Validation

- [ ] Tests pass (`devtools::test()`, not run during the sweep)
- [ ] `/code-check` clean (once over the branch with `/code-check branch`)
- [ ] PWF checkboxes match landed work
- [ ] `/planning-archive` on completion

Verification: the round-trip guard proves that what is sent is what was read.
`git diff data-raw/logs/indexpoint_266/` shows exactly which counts moved: the
snapped-position counts (whole metres) must not move, and if they do, that is a
finding, not noise. Spot-check one moved CSV measure by hand with
`fwa_locatealong(blk, <%.17g>)` on the base state.


## Context from exploration

What exploration found:
- The local docker fwapg (`fresh-db`, up) is still un-migrated (old `fwa_indexpoint`
  signature, 4,907,441 segments), so the script's "no rework yet" guard passes.
- The migration files in `~/Projects/repo/fwapg/db/migrations/` have the md5s in the
  last run's header (`a048f8e2…`, `98d84a33…`). The same inputs can be re-run.
- The CSV measures go into `working.tie266_measures_all` through `dbWriteTable()`.
  Whether RPostgres writes doubles exactly has not been checked, and a guard settles it.
- `write.csv()` writes `m` at 15 significant digits, so the research note's claim that
  "`sweep_changed.csv` carries them exactly" is not true of a 17-digit measure.
- Keys from `format()` are already exact (integers print in full). They change to `%d`
  anyway, as the issue asks.
- The last run took about 50 minutes: base 1082 s, tiebreak 959 s, both 913 s.

