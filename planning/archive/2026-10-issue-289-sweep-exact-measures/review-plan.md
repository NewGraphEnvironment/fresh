# Plan review — #289 (Plan agent, 2026-10-31, after Phase 1 commit)

Findings as returned (condensed), with disposition.

- **B1** read-back guard is on `measures_all`, base connection only; the values sent are
  re-read per state from `tie266_measures` / `tie266_heads`, and heads have no R source.
  -> Fix: per state, send the formatted text back and count `stored <> sent::float8` in SQL.
- **G1** guarded top is not fwa_locatealong()'s population (it scans every segment); an
  unguarded segment above the guarded max makes it not a head case. -> Fix: send the
  unguarded top for all 400; flag where it is also the guarded top; report both.
- **G2** `print(head(moved, 60))` shows 7 digits. -> Already fixed in 8cb4d57.
- **G3** `exact_m()` makes `m` character and write.csv quotes it, churning every row.
  -> Fix: quote only the columns that were character before.
- **A1** `base_md5` must reproduce `f0a5e96f60dd7a7af0eddc1e165faf48`. -> Acceptance check.
- **A2** head columns in `summary` re-wrap the printed table. -> Heads get their own table.
- **A3** head flips crowd the moved list's head(60) and the headline count. -> Heads get
  their own per-blue-line CSV and table; `moved` keeps its old frames.
- **A4** only the CSV VALUES literals change the measurement; md5 sampling, write.csv,
  print, base_md5 are SQL-side or report-only. Old rounding also depended on chunk-mates.
- **O1** the smoke run cannot check the base_md5 match. -> Full run checks it.
- **S1** restatements: NEWS.md:86 ("four of 23,540"), gate test :7-13, research note
  :3, :9, :41-45, :55-62, :82. -> Phase 4.
- **S2** 14 of 345 guarded tops still miss after the migration; confirm `head_blk`
  360447231 remains a head case. -> Phase 4.
