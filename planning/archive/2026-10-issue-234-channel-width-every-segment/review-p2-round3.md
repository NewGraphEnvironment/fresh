# Code check: Phase 2, round 3 (value literals, count query, message)

Scope: `R/frs_channel_width.R` (the `value` pass and the `verbose` count), `tests/testthat/test-frs_channel_width.R`, `R/frs_col_join.R`. Live tests were not run. The only DB use was read-only `SELECT` probes.

## Verdict

One low-severity finding. Everything else in this angle checks out.

## Finding

### 1. A `bit64::integer64` `value` passes validation and writes about 1e-323 m (low)

`R/frs_channel_width.R:150-153` validates `value`, and `:235` renders it with `.frs_sql_num(value)`, which is `sprintf("%.10g", unlist(x))`.

- `integer64` passes every check: `is.numeric()` is TRUE, `is.finite()` is TRUE, and `<= 0` is FALSE.
- `sprintf("%.10g")` does not dispatch, so it formats the raw double bits instead of the number.
- Measured: `value = bit64::as.integer64(2)` renders as `"9.881312917e-324"`.
- Postgres accepts that literal into a double precision column. It is a valid positive number, so nothing errors. Every NULL row would get a width of about 1e-323 m, labelled `ASSIGNED`.

The trigger is realistic: `value` read from a bigint column through RPostgres, whose default `bigint` type is `integer64` (confirmed on this connection). This is the checklist rule "A database driver's value is not a base R type".

Fix: after validation, coerce with `value <- as.double(value)`. bit64's `as.double` method returns 2. Alternatively, refuse objects with `if (is.object(value)) stop(...)`. A unit case for `bit64::as.integer64(2)` would pin it, but only if `bit64` is available in Suggests.

The same hole exists for custom-model coefficients (`model$k` etc.), which also go through `.frs_sql_num()`. That is pre-existing and outside this diff.

## Checked and clean

**`value` literals through `.frs_sql_num`.** Rendered in R, then parsed by Postgres with read-only `SELECT`s:

| value | rendered literal | Postgres result |
|---|---|---|
| `1L` | `1` | integer literal, assigns to double precision cleanly |
| `1e-12` | `1e-12` | numeric literal, cast to double precision gives `1e-12` |
| `1e6` | `1000000` | integer literal, gives `1e+06` |
| `1e15` | `1e+15` | parses |
| `1e300` | `1e+300` | parses |
| `4.94e-324` (subnormal) | `4.940656458e-324` | parses |

- `%.10g` keeps 10 significant digits, which is far beyond any meaningful width.
- `Inf`, `NA`, `0`, negatives, character, logical and length-2 values are all refused before any SQL is built. The `||` chain short-circuits ahead of `is.finite()` on length > 1.
- The only lossy cases depend on the user's column type, and that type check is an accepted tradeoff. A `numeric(10,2)` column stores `1e-12` as `0.00` and raises an overflow error at `1e15`. A `real` column also raises an overflow error at `1e300`. Mentioned for completeness, not flagged.

**Message under overwrite × value × col_source.** `n_null` is counted after the regression and before the value pass, so the arithmetic holds in every combination:

| overwrite | value | modelled | assigned | still NULL |
|---|---|---|---|---|
| FALSE | NULL | rows the guarded UPDATE wrote | 0 | `n_null` |
| FALSE | set | rows the guarded UPDATE wrote | `n_null`, from the value UPDATE's row count | 0 |
| TRUE | NULL | all rows − `n_null` | 0 | `n_null` |
| TRUE | set | all rows − `n_null` | `n_null` | 0 |

- `col_source` changes only the SET list, never a WHERE clause or a count, so it cannot move any number in the message.
- **Overwrite modelled count.** For overwrite, `all rows − n_null` equals the number of rows actually modelled. That holds only if the CASE expression is non-NULL whenever the guard is TRUE. It is: the guard requires both inputs to be non-NULL with positive bases, so `expr` is finite. Overflow and underflow raise errors rather than returning NULL.

**Pre-existing NULLs in rows the regression cannot reach.**
- With `overwrite = FALSE`, those rows fail `to IS NULL AND guard` in the regression UPDATE. They are therefore absent from `n_written` and present in `n_null`, so the message reports them as "still NULL" (or as assigned when `value` is set). Correct.
- With `overwrite = TRUE`, the CASE writes NULL to them. They count in `n_written` and in `n_null`, so they cancel out of "modelled". Correct.
- Rows where the guard fails but `to` was already non-NULL are untouched under FALSE and set to NULL under TRUE, as documented. Under FALSE they appear in no count, and the message does not claim a total.

**Tests.**
- **Mock harness.** The mock indexes `n_rows` only on `^UPDATE` statements, so the `ALTER`s cannot consume a slot. Each test supplies exactly as many `n_rows` as the UPDATEs it triggers.
- **Single message.** `expect_message()` sees the only message the function emits, so the "first condition only" trap does not apply.
- **Overwrite mutation.** The overwrite case (`15 − 4 = 11`) would go red if the overwrite formula were dropped.
- **Live test.** `id_no_input` comes back as `integer64`. Checked: `sprintf("%s")` and `paste()` dispatch on it correctly. `frs_extract()` leaves `linear_feature_id` unique, so the stand-in UPDATE touches one row.
- **Other callers.** No other package code calls `frs_channel_width()`, so the new `verbose = TRUE` default cannot break a silent caller.

/Users/airvine/Projects/repo/fresh/planning/active/review-p2-round3.md
