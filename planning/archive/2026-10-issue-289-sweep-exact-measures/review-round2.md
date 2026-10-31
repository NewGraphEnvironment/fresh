# Code-check round 2: branch 289 (git diff 7bfd156...HEAD, HEAD ae6d5b7)

## Checklist read

- code-check.md: I read the prose of all 14 H3s under `## Mechanisms` and skipped the table rows. The other 23 headings (the 14 "Rules that stand alone", 6 under Security, 3 under Spreadsheets and PDFs) I read in the index only.
- code-check-r.md: I read 5 sections in full: "`sprintf("%g", x)` writes `Inf` and `NA`…", "A database driver's value is not a base R type…", "A value compared as `::text` in SQL has PostgreSQL's spelling…", "Postgres row order is never fixed…" and, from the index, the `on.exit()`, `data-raw/` load_all, `vapply(USE.NAMES)` and Rscript-mid-edit rules. The other ~110 I read in the index only.
- code-check-spatial.md: I read 1 section in full, "FWA `upstream_route_measure` misses the next segment's start". The other ~93 I read in the index only.
- code-check-shell.md: index only, 70 not read. There is no shell in the diff.
- code-check-infra.md: index only, 38 not read. The only database access is read-only SELECTs against the local docker fwapg.

## Findings

- **[severity: fragile]** research/fwa_point_snap.md:11 (and the #289 issue body, "sent them at 14 to 16 significant digits"). "11 decimals for the CSV measures, so they went out at 14 to 16 significant digits" does not hold for every measure. This wording came from round 1's review and was adopted without being run.
  - I rebuilt the old text the same way the old code did: `format(m, scientific = FALSE)` over the 23,540-row frame, with the same md5 crossings sample and the same order. Script: `/private/tmp/claude-501/-Users-airvine-Projects-repo-fresh/1131ec99-e8dc-43f4-be62-8dad0c8e2dd8/scratchpad/round2/fmt.R`.
  - Every value gets 11 decimals, which is confirmed. 12,262 of the 23,540 values changed (52%), which supports "most" in the chunked() comment.
  - The significant digits sent run from 0 to 18, because measures run from 0 to 1,842,412:
    - 21,321 values have 14 to 16.
    - 2,099 have 13 or fewer (63 of them are 0).
    - 120 have 17 or 18.
  - The fix is to drop the significant-digit range, or write "mostly 14 to 16". "11 decimals, rounded at about 1e-11 m" is the accurate statement on its own (measured max shift 1.5e-11 m).
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** data-raw/point_snap_tie_sweep.R:385. The new chunked() comment says the measure goes through `.frs_sql_exact()` "as every fresh code path sends one since #274". That is false.
  - NEWS 0.50.0 (the #274 release) says "`frs_wsg_drainage()` still writes outlet measures at 15 digits".
  - R/frs_wsg_drainage.R:101 still sends `DBI::dbQuoteLiteral(conn, as.numeric(outlets$downstream_route_measure))`.
  - The same universal appears in planning/active/task_plan.md:11 and in the #289 issue body ("Since #274, fresh sends every route measure at 17 significant digits").
  - The script's header at :41-42 ("as on fresh's own code paths since #274") and research:9 (which names the functions) are worded narrowly enough to be true.
  - **Rule:** code-check.md "A guard's scope, escape hatches, and remedies"

- **[severity: fragile]** planning/active/task_plan.md. This file is not append-only, and two parts of it would mislead whoever resumes the work.
  - The frame at :4 and :11 still states round 1's corrected premise. It says `format()` "defaults to 7 significant digits… so the sweep does not send the measures it reads", and that every fresh route measure goes at 17 digits. The issue body was corrected; this copy was not.
  - Phase 2's checked boxes (:42-47) describe a design that was not built: `working.tie266_heads`, the guarded top "as in blk_top()", `head_hit`/`head_miss`/`head_error` columns in `summary`, and a frame in `moved`. What landed is `tie266_tops`, the top over every segment (G1), and a separate `tops_summary` table plus `sweep_tops.csv` (A2/A3). findings.md records the change; the plan does not.
  - The "Decided at the gate" bullet still names the guarded top.
  - **Rule:** code-check.md "Written data outlives the fix"

## Round-1 fixes checked, and the rest of the diff

- The 11-decimal premise reproduces. The old text for 957.70485427024903 was `957.70485427025`.
- The 957 facts check out against psql:
  - Segment 702605415 has us 957.7048542702494, which is 957.70485427024937 at %.17g.
  - It lies 3.41e-13 below the top (3 ULPs). The old text was 6.29e-13 above it in decimal (6.82e-13 once parsed).
  - The next segment, 702605459, starts at 957.705341846863, 0.49 mm higher.
  - The CSV's `957.704854270249` is the top at 15 significant digits.
- `sent_exact()` now receives chunked()'s own `sent` text, row-aligned with `d`. Its SQL is sound: a VALUES numeric literal is cast to float8 with correct rounding, every row must join, and none may differ. It runs inside the trial transaction, and a stop() there unwinds through the deferred rollback.
- The read-back guard, the whole-metre guard on positions, `write_exact()` quoting (indices taken before the conversion; the tops CSV has no character columns, so its header is unquoted, which is harmless), NA handling in `exact_m()`, and the row order of every fetch (each ends on a unique key) all check out.
- These log figures match the code and the database:
  - 400 / 345 / 341 tops; 0 → 383 and 0 → 327; 17 and 14 misses.
  - CSV misses 36 / 31 / 31, against 42 / 38 / 38 at 11 decimals (net 6 and 7).
  - 5 CSV movers; base md5 unchanged; sweep_errors.csv unchanged.
  - head_blk 360447231 has guarded and unguarded tops equal at 1528.8506958829107, and it is in the sample.
- No code defect found in data-raw/point_snap_tie_sweep.R or in tests/testthat/test-frs_fwapg_gate.R.
