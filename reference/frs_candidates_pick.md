# Score, Filter, and Dedup Candidates per Key

Third primitive in fresh's point-handling family (alongside
[`frs_point_snap()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_snap.md)
and
[`frs_point_match()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_match.md)).
Given a candidates table where multiple rows can share the same key
value, optionally compute a per-row score from a caller-supplied SQL
expression, optionally filter disqualifiers via a caller-supplied WHERE
clause, then keep one row per key by
`DISTINCT ON (col_key) ORDER BY ...`.

## Usage

``` r
frs_candidates_pick(
  conn,
  table_in,
  table_to,
  col_key,
  exp_score = NULL,
  exp_filter = NULL,
  order_by
)
```

## Arguments

- conn:

  A
  [DBI::DBIConnection](https://dbi.r-dbi.org/reference/DBIConnection-class.html)
  object.

- table_in:

  Character. Schema-qualified candidates table. Multiple rows per
  `col_key` value are expected (the whole point — pick one). Typically
  the output of `frs_point_snap(num_features = N)` optionally enriched
  with JOINs to pull in score-bearing columns.

- table_to:

  Character. Schema-qualified destination. Dropped + recreated by this
  function via DDL.

- col_key:

  Character. Column on `table_in` that groups competing rows. After this
  function runs, `table_to` has at most one row per distinct `col_key`
  value.

- exp_score:

  Character or `NULL`. Optional SQL fragment yielding a `score` column —
  evaluated per row. The caller writes the SQL. Example:
  `"CASE WHEN LOWER(a.stream_name) = LOWER(b.gnis_name) THEN 100 ELSE 0 END"`.
  When supplied, the output table gains a `score` column; when `NULL`,
  no score column is added.

- exp_filter:

  Character or `NULL`. Optional SQL `WHERE` clause for disqualifiers,
  evaluated against `table_in` (or the scored intermediate when
  `exp_score` is set). Example: `"score >= 0"` to drop rows with score
  \< 0. The caller writes the SQL.

- order_by:

  Character vector. Sequence of `"<expr> ASC|DESC"` strings (e.g.
  `c("score DESC", "distance_to_stream ASC")`) used for the
  `DISTINCT ON (col_key) ORDER BY ...` dedup tiebreak. `col_key` is
  prepended automatically (PostgreSQL requires the leading `ORDER BY`
  columns to match `DISTINCT ON`).

## Value

`conn` invisibly, for piping. Side effect: drops + recreates `table_to`
with all `table_in` columns plus (when `exp_score` is supplied) a
`score` column, deduped to one row per `col_key`.

## Details

Designed for the "score + filter + dedup per key" pattern that shows up
wherever column-to-column comparisons disambiguate matches beyond pure
geometry: stream-name matching, watershed-group agreement, species-code
overlap, assessment-date proximity, channel- width × stream-order
compatibility, etc. Composes with
[`frs_point_snap()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_snap.md)
(upstream — produces multi-candidate per key) and
[`frs_point_match()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_match.md)
(downstream — operates on single-candidate-per-key input).

Reproduces bcfp's `04_pscis.sql` PSCIS-to-stream selection pattern
(`smnorris/bcfishpass@v0.7.14-125-g6e9cf1c`) when the caller supplies
the bcfp `name_score` and `weighted_distance` ORDER BY clauses.

SQL composition:


    WITH scored AS (
      SELECT *, (<exp_score>) AS score
      FROM <table_in>
    )
    SELECT DISTINCT ON (<col_key>) *
    FROM scored
    WHERE <exp_filter>
    ORDER BY <col_key>, <order_by[1]>, <order_by[2]>, ...

The `WITH scored AS` CTE is omitted when `exp_score = NULL` (and the
caller's `order_by` cannot reference a `score` column). The `WHERE`
clause is omitted when `exp_filter = NULL`.

**Caller's responsibilities** (NOT this primitive's):

- Producing the candidates table (multi-row-per-key).

- Enriching it with JOINs to pull in score-bearing columns.

- Writing `exp_score` / `exp_filter` SQL.

- Writing `order_by` clauses.

**What this primitive does**:

- Sanitizes `col_key`, `table_in`, `table_to` identifiers.

- Composes the CTE + SELECT.

- Executes via
  [`DBI::dbExecute()`](https://dbi.r-dbi.org/reference/dbExecute.html).

## See also

Other network:
[`frs_network_features()`](https://newgraphenvironment.github.io/fresh/reference/frs_network_features.md),
[`frs_point_match()`](https://newgraphenvironment.github.io/fresh/reference/frs_point_match.md)

## Examples

``` r
if (FALSE) { # \dontrun{
conn <- frs_db_conn()

# bcfp PSCIS-to-stream selection (reproduces 04_pscis.sql logic):
# caller has staged candidates with stream_name (from PSCIS) and
# gnis_name (from FWA) columns joined in.
frs_candidates_pick(
  conn,
  table_in   = "working_bulk.pscis_stream_candidates",
  table_to   = "working_bulk.pscis",
  col_key    = "stream_crossing_id",
  exp_score  = "CASE
                 WHEN LOWER(stream_name) = LOWER(gnis_name) THEN 100
                 WHEN stream_name IS NULL OR gnis_name IS NULL THEN 0
                 ELSE -100
               END",
  exp_filter = "score >= 0",
  order_by   = c("score DESC", "distance_to_stream ASC")
)

# Generic field-assessed vs user-added crossings dedup:
frs_candidates_pick(
  conn,
  table_in   = "wsg_adms.crossings_candidates",
  table_to   = "wsg_adms.crossings",
  col_key    = "site_id",
  order_by   = c("assessment_date DESC", "distance_to_stream ASC")
)

DBI::dbDisconnect(conn)
} # }
```
