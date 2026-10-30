#' Per-Segment Arrays of Features Relative to a Stream Network
#'
#' For each row in a segments table, return an array of feature IDs
#' from a features table that lie at the requested relative position
#' (downstream of, or upstream of) that segment in the FWA stream
#' network. The features can be any point dataset snapped to FWA --
#' barriers, crossings, observations, water-quality stations, fish
#' surveys, sediment-sample points, weather stations -- anything with
#' `(blue_line_key, downstream_route_measure, wscode_ltree,
#' localcode_ltree)` keys.
#'
#' Mirrors `bcfishpass.load_dnstr_chunked` in
#' `bcfishpass/db/migrations/archive/v0.7.6/load_dnstr_chunked.sql`
#' but generalises to either direction. The SQL pattern joins via
#' `whse_basemapping.fwa_<direction>()` for cross-mainstem ltree
#' comparison, then `array_agg`s feature IDs grouped by segment ID.
#'
#' With `result = "exists"` the same walk answers only whether each segment
#' has any such feature, returning the segments that do without building
#' their arrays (#281).
#'
#' @param conn A [DBI::DBIConnection-class] object pointing at fwapg.
#' @param segments Character. Schema-qualified segments table. Must
#'   have `<segment_id_col>`, `blue_line_key`,
#'   `downstream_route_measure`, `wscode_ltree`, `localcode_ltree`,
#'   and `watershed_group_code` columns (the last only when filtering
#'   via `aoi`).
#' @param features Character. Schema-qualified features table. Must
#'   have `<feature_id_col>`, `blue_line_key`,
#'   `downstream_route_measure`, `wscode_ltree`, `localcode_ltree`
#'   columns.
#' @param segment_id_col Character. Default `"id_segment"`. The
#'   per-segment unique key column on the segments table.
#' @param feature_id_col Character. The unique-key column on the
#'   features table (e.g. `"barriers_pscis_id"`,
#'   `"observation_key"`, `"station_id"`). **Required -- no default;
#'   caller passes the actual column name.**
#' @param direction Character. **Required -- no default.** One of
#'   `"downstream"` or `"upstream"`. `"downstream"` returns features
#'   that lie below each segment (toward the river mouth). `"upstream"`
#'   returns features above each segment.
#' @param aoi Character. Optional area-of-interest filter on segments.
#'   Today only WSG codes (e.g. `"ADMS"`, `"BULK"`) are supported and
#'   filter `segments.watershed_group_code = aoi`. Polygon / ltree AOIs
#'   are forward-compat -- they will route through `.frs_resolve_aoi()`
#'   when generalised. Default `NULL` processes every row in the
#'   segments table. With `direction = "downstream"`, an `aoi` also
#'   switches on the scoped walk, which needs a session that can create
#'   temp tables: see "Scoped downstream walks" below.
#' @param include_equivalents Logical. When `TRUE`, treats segments
#'   at the same `(blue_line_key, downstream_route_measure)` position
#'   as relative-direction matches of each other. Mirrors bcfishpass's
#'   `include_equivalents` arg. Default `FALSE`.
#' @param segments_wscode_col Character. Watershed-code column on
#'   the `segments` table. Default `"wscode_ltree"` matches
#'   `fresh.streams`, `bcfishpass.streams`, `bcfishpass.barriers_*`.
#' @param segments_localcode_col Character. Local-code column on
#'   `segments`. Default `"localcode_ltree"`.
#' @param features_wscode_col Character. Watershed-code column on
#'   the `features` table. Default `"wscode_ltree"`. Pass `"wscode"`
#'   when `features = "bcfishpass.observations"` (which uses
#'   unsuffixed column names) or any other FWA-snapped point dataset
#'   following the same convention.
#' @param features_localcode_col Character. Local-code column on
#'   `features`. Default `"localcode_ltree"`. See `features_wscode_col`.
#' @param result Character. `"ids"` (default) returns each segment's array
#'   of feature IDs. `"exists"` returns only whether a segment has any
#'   feature at the requested position, without building the arrays: the
#'   same walk (predicate, `aoi`, scoped downstream path) reduced to the
#'   distinct segment IDs it reaches, so no array is aggregated and the
#'   walk has no `ORDER BY`. Its segments are exactly the rows
#'   `"ids"` returns. Use it when the arrays would only be tested for
#'   presence (`id %in% result$id`). `"distinct"` returns each segment's
#'   feature IDs once each, sorted by the ID, from the same walk: the
#'   answer to which kinds of feature lie up or downstream when
#'   `feature_id_col` names a kind (a species code, say). Only distinct
#'   pairs leave the server, so it stays cheap where a segment reaches many
#'   features that share an ID (a main stem below thousands of records of a
#'   few species); with a unique `feature_id_col` it returns as much as
#'   `"ids"` (#284).
#'
#' @section Scoped downstream walks:
#' With `direction = "downstream"` and an `aoi`, the walk is cut to what
#' `fwa_downstream()` can return before it runs. A feature can only lie
#' downstream of a segment when it is on the segment's blue line, or when
#' its watershed code is an ancestor of, or equal to, the segment's
#' (`fwa_downstream()`'s two criteria). The function therefore:
#'
#' 1. copies the AOI's segments (the id, `blue_line_key`,
#'    `downstream_route_measure` and the two code columns) into a session
#'    temp table, with a btree index on `blue_line_key`, GiST indexes on
#'    both codes, and `ANALYZE`;
#' 2. admits only the features on one of those blue lines, or whose
#'    watershed code equals one of the segments' codes or one of their
#'    ancestors, through the feature table's own indexes;
#' 3. walks the temp table against the admitted features with the same
#'    `fwa_downstream()` predicate, and drops the temp table on exit.
#'
#' The answer is the same as the unprefiltered join's: the admitted set
#' contains every feature either criterion can reach, whatever
#' `include_equivalents` is. What changes is the plan. Unscoped, the join
#' order depends on the tables: against a large feature table the planner
#' can probe the segments once per feature in the whole table, and with a
#' province-wide segments table it can leave the segment-driven plan
#' altogether. Scoped, it probes a small indexed table once per admitted
#' feature (#272).
#'
#' **Session requirement.** A scoped call runs several statements that
#' must reach one backend, and one of them creates a temp table. In a
#' read-only transaction or on a hot standby the call stops there, with an
#' error naming the cause. A transaction-pooling connection pooler
#' (pgbouncer `pool_mode = transaction`) can send the statements to
#' different backends. The call then fails, either while building the table
#' (the same error) or at the walk, because the temp table is not on the
#' walk's backend, and the table can be left on the backend that made it.
#' Use a direct connection or session pooling. If the call is inside a transaction that
#' the walk aborts, the temp table's `DROP` fails too and the table lasts
#' until that transaction is rolled back.
#'
#' `aoi = NULL` and `direction = "upstream"` run the unprefiltered walk and
#' create nothing. A caller holding a segments table already cut to one
#' watershed group should still pass `aoi` to get the scoped walk.
#'
#' @return With `result = "ids"`, a data frame with two columns:
#'   - `<segment_id_col>` -- matches the input column name on segments.
#'   - `feature_ids` -- an R list-column of character vectors (one
#'     vector per row). The vectors carry the feature IDs aggregated
#'     from the requested direction, ordered by
#'     `(wscode_col DESC, localcode_col DESC, downstream_route_measure
#'     DESC, feature_id_col)`. The first three keys are
#'     `bcfishpass.load_dnstr`'s; the last breaks its ties (co-located
#'     features), so the order is a function of the data rather than the
#'     query plan when `feature_id_col` is unique. Segments with zero
#'     matches don't appear in the output (INNER JOIN). Postgres
#'     array literals are parsed to R character vectors via the
#'     internal `.frs_parse_pg_array()` helper -- limited to
#'     unquoted-element arrays (the common case for FWA-snapped IDs).
#'
#'   With `result = "exists"`, a data frame with one row per distinct
#'   `<segment_id_col>` that has at least one feature at the requested
#'   position, and a logical `has_features` that is `TRUE` on every row.
#'   Segments with none don't appear, as with `"ids"`. A feature counts
#'   whatever its ID, so a segment whose only features have a NULL ID is a
#'   row in both forms (an empty array under `"ids"`).
#'
#'   With `result = "distinct"`, the same two columns as `"ids"` and the same
#'   rows, with each segment's IDs once each, sorted by the ID (in its SQL
#'   type's order, so numerically for a numeric ID): the set `unique()`
#'   would give of the `"ids"` vector.
#'
#' @family network
#'
#' @export
#'
#' @examples
#' \dontrun{
#' conn <- frs_db_conn()
#'
#' # Barriers downstream of each segment (bcfishpass-parity use case)
#' dnstr_barriers <- frs_network_features(
#'   conn,
#'   segments       = "bcfishpass.streams",
#'   features       = "bcfishpass.barriers_pscis",
#'   segment_id_col = "segmented_stream_id",
#'   feature_id_col = "barriers_pscis_id",
#'   direction      = "downstream",
#'   aoi            = "ADMS"
#' )
#'
#' # Fish observations upstream of each barrier
#' upstr_obs <- frs_network_features(
#'   conn,
#'   segments       = "bcfishpass.barriers_pscis",
#'   features       = "bcfishobs.observations",
#'   segment_id_col = "barriers_pscis_id",
#'   feature_id_col = "observation_key",
#'   direction      = "upstream",
#'   aoi            = "ADMS"
#' )
#'
#' # Generic: water-quality stations downstream of each link segment
#' wq_dnstr <- frs_network_features(
#'   conn,
#'   segments       = "fresh.streams",
#'   features       = "wq.stations_snapped",
#'   feature_id_col = "station_id",
#'   direction      = "downstream",
#'   aoi            = "BABL"
#' )
#'
#' # bcfishpass.observations uses unsuffixed `wscode` / `localcode`
#' # columns -- pass the column names so the join matches.
#' obs_per_segment <- frs_network_features(
#'   conn,
#'   segments       = "bcfishpass.streams",
#'   features       = "bcfishpass.observations",
#'   segment_id_col = "segmented_stream_id",
#'   feature_id_col = "observation_key",
#'   direction      = "upstream",
#'   aoi                    = "ADMS",
#'   features_wscode_col    = "wscode",
#'   features_localcode_col = "localcode"
#' )
#' # feature_ids is a list-column of character vectors:
#' lengths(obs_per_segment$feature_ids)        # per-segment counts
#' obs_per_segment$feature_ids[[1]]            # character vector
#'
#' # Only whether any barrier lies downstream: the segments of the first
#' # call, without building their arrays
#' has_dnstr <- frs_network_features(
#'   conn,
#'   segments       = "bcfishpass.streams",
#'   features       = "bcfishpass.barriers_pscis",
#'   segment_id_col = "segmented_stream_id",
#'   feature_id_col = "barriers_pscis_id",
#'   direction      = "downstream",
#'   aoi            = "ADMS",
#'   result         = "exists"
#' )
#' setequal(has_dnstr$segmented_stream_id, dnstr_barriers$segmented_stream_id)
#'
#' DBI::dbDisconnect(conn)
#' }
frs_network_features <- function(
    conn,
    segments,
    features,
    segment_id_col = "id_segment",
    feature_id_col,
    direction,
    aoi = NULL,
    include_equivalents = FALSE,
    segments_wscode_col = "wscode_ltree",
    segments_localcode_col = "localcode_ltree",
    features_wscode_col = "wscode_ltree",
    features_localcode_col = "localcode_ltree",
    result = c("ids", "exists", "distinct")) {

  if (missing(direction)) {
    stop("`direction` is required (no default). ",
         "Use one of: \"downstream\", \"upstream\".",
         call. = FALSE)
  }
  direction <- match.arg(direction, c("downstream", "upstream"))
  result <- match.arg(result)

  if (missing(feature_id_col) ||
        !is.character(feature_id_col) ||
        length(feature_id_col) != 1L ||
        !nzchar(feature_id_col)) {
    stop("`feature_id_col` is required (no default).", call. = FALSE)
  }

  .frs_validate_identifier(segments, "segments")
  .frs_validate_identifier(features, "features")
  .frs_validate_identifier(segment_id_col, "segment_id_col")
  .frs_validate_identifier(feature_id_col, "feature_id_col")
  .frs_validate_identifier(segments_wscode_col, "segments_wscode_col")
  .frs_validate_identifier(segments_localcode_col, "segments_localcode_col")
  .frs_validate_identifier(features_wscode_col, "features_wscode_col")
  .frs_validate_identifier(features_localcode_col, "features_localcode_col")

  stopifnot(
    is.logical(include_equivalents),
    length(include_equivalents) == 1L,
    !is.na(include_equivalents)
  )

  if (!is.null(aoi)) {
    if (!is.character(aoi) || length(aoi) != 1L || !nzchar(aoi)) {
      stop("`aoi` must be a single non-empty character or NULL.",
           call. = FALSE)
    }
    if (!grepl("^[A-Z]{3,5}$", aoi)) {
      stop("`aoi` must be a watershed group code (e.g. \"ADMS\", ",
           "\"BULK\") matching `^[A-Z]{3,5}$`. Polygon and ltree AOIs ",
           "are not yet supported in this function -- file a follow-up ",
           "if needed.", call. = FALSE)
    }
  }

  fwa_predicate <- if (direction == "downstream") {
    "whse_basemapping.fwa_downstream"
  } else {
    "whse_basemapping.fwa_upstream"
  }

  ie_arg <- if (isTRUE(include_equivalents)) "true" else "false"

  # unique(): an id column may also be one of the key columns, and a
  # subquery projecting it twice would make `b.<col>` ambiguous.
  cols_segments <- unique(c(segment_id_col, "blue_line_key",
                            "downstream_route_measure",
                            segments_wscode_col, segments_localcode_col))
  cols_features <- unique(c(feature_id_col, "blue_line_key",
                            "downstream_route_measure",
                            features_wscode_col, features_localcode_col))

  # `aoi` is regex-validated `^[A-Z]{3,5}$` above -- safe to interpolate
  # without runtime quoting (no SQL-injection vector).
  from_segments <- segments
  from_features <- features
  aoi_filter <- ""
  if (direction == "downstream" && !is.null(aoi)) {
    # Scoped walk (#272): the AOI's segments in an indexed temp table, the
    # features cut to what fwa_downstream() can reach from them. The DROP is
    # registered before the CREATE, so a CREATE that half-ran is dropped too.
    tmp <- paste0("pg_temp.",
                  gsub("[^a-z0-9_]", "", basename(tempfile("frs_tmp_"))))
    on.exit(tryCatch(
      .frs_db_execute(conn, sprintf("DROP TABLE IF EXISTS %s", tmp)),
      error = function(e) NULL
    ), add = TRUE)
    .frs_walk_scope(conn, tmp, segments, aoi, cols_segments,
                    segments_wscode_col, segments_localcode_col)
    from_segments <- tmp
    from_features <- .frs_walk_prefilter(features, tmp, cols_features,
                                         features_wscode_col,
                                         segments_wscode_col)
  } else if (!is.null(aoi)) {
    aoi_filter <- sprintf("WHERE a.watershed_group_code = '%s'", aoi)
  }

  # The walk's FROM, join predicate and filter, written once for both
  # results so the exists mode cannot drift from the array walk (#281).
  walk_from <- sprintf("FROM %1$s a
      INNER JOIN %2$s b ON
        %3$s(
          a.blue_line_key, a.downstream_route_measure,
          a.%6$s, a.%7$s,
          b.blue_line_key, b.downstream_route_measure,
          b.%8$s, b.%9$s,
          %4$s, 1
        )
      %5$s",
    from_segments, from_features, fwa_predicate, ie_arg, aoi_filter,
    segments_wscode_col, segments_localcode_col,
    features_wscode_col, features_localcode_col
  )

  if (result == "distinct") {
    # The same join, each segment's ids aggregated once each (#284). No
    # ordered subquery: the array is sorted by the id itself, so the order is
    # a function of the data.
    sql <- sprintf("
      SELECT
        a.%1$s,
        array_agg(DISTINCT b.%2$s ORDER BY b.%2$s)
          FILTER (WHERE b.%2$s IS NOT NULL) AS feature_ids
      %3$s
      GROUP BY a.%1$s", segment_id_col, feature_id_col, walk_from)
    res <- frs_db_query(conn, sql)
    names(res)[1] <- segment_id_col
    res$feature_ids <- lapply(res$feature_ids, .frs_parse_pg_array)
    return(res)
  }

  if (result == "exists") {
    # The same join, reduced to the distinct segment ids it reaches (#281).
    # Measured against a correlated EXISTS, which drives from the segments
    # and was the slower form; see research/fwa_downstream_walk.md.
    sql <- sprintf("
      SELECT DISTINCT a.%s
      %s", segment_id_col, walk_from)
    res <- frs_db_query(conn, sql)
    names(res)[1] <- segment_id_col
    res$has_features <- rep(TRUE, nrow(res))
    return(res)
  }

  # SQL pattern mirrors bcfishpass.load_dnstr:
  # subquery-with-INNER-JOIN feeding array_agg + GROUP BY on segment_id.
  # The `ORDER BY a.<id>, b.wscode DESC, b.localcode DESC, b.drm DESC`
  # at the subquery level is bcfp's element ordering; `b.<feature id>`
  # last breaks its ties, which bcfp leaves to the plan (#272).
  #
  # INNER JOIN (vs LEFT) means segments with zero matches don't appear
  # in the output. That matches bcfp's table, where rows are only
  # populated for segments with at least one downstream feature.
  # Callers wanting "all segments + NULL for no-match" can LEFT JOIN
  # the result back to their segments table.
  sql_fmt <- "
    SELECT
      d.%1$s,
      array_agg(d.feature_id) FILTER (WHERE d.feature_id IS NOT NULL) AS feature_ids
    FROM (
      SELECT
        a.%1$s,
        b.%2$s AS feature_id
      %3$s
      ORDER BY a.%1$s,
               b.%4$s DESC,
               b.%5$s DESC,
               b.downstream_route_measure DESC,
               b.%2$s
    ) d
    GROUP BY d.%1$s"

  sql <- sprintf(
    sql_fmt,
    segment_id_col,
    feature_id_col,
    walk_from,
    features_wscode_col,
    features_localcode_col
  )

  res <- frs_db_query(conn, sql)
  names(res)[1] <- segment_id_col
  # Postgres array literals (`pq__text` strings like `"{a,b,c}"`) become
  # an R list-column of character vectors so callers can `lengths()`,
  # `%in%`, `lapply()`, etc. directly. Empty / NULL arrays parse to
  # `character(0)`. See `.frs_parse_pg_array()` for limits.
  res$feature_ids <- lapply(res$feature_ids, .frs_parse_pg_array)
  res
}

# Internal (#272): copy the AOI's segments into the session temp table `tmp`,
# index it for the walk's two criteria (btree on blue_line_key, GiST on both
# codes) and ANALYZE it, so the planner probes a small table it has
# statistics for. A failure is rethrown naming the likely cause, with the
# original kept as `$parent`.
.frs_walk_scope <- function(conn, tmp, segments, aoi, cols_segments,
                            wscode_col, localcode_col) {
  stmts <- c(
    sprintf("CREATE TEMP TABLE %s AS SELECT %s FROM %s WHERE watershed_group_code = '%s'",
            tmp, paste(cols_segments, collapse = ", "), segments, aoi),
    sprintf("CREATE INDEX ON %s (blue_line_key)", tmp),
    sprintf("CREATE INDEX ON %s USING gist (%s)", tmp, wscode_col),
    sprintf("CREATE INDEX ON %s USING gist (%s)", tmp, localcode_col),
    sprintf("ANALYZE %s", tmp)
  )
  tryCatch(
    for (stmt in stmts) .frs_db_execute(conn, stmt),
    error = function(e) {
      msg <- paste0(
        "`frs_network_features(aoi = \"", aoi, "\")` builds a session ",
        "temp table of the AOI's segments for a downstream walk, and ",
        "could not. A session that cannot create one (read-only ",
        "transaction or standby) fails here, as does a transaction ",
        "pooler that sent one of these statements to another backend, ",
        "and a `segments` table missing one of: ",
        paste(c(cols_segments, "watershed_group_code"), collapse = ", "),
        ".\nCaused by: ", conditionMessage(e)
      )
      stop(structure(
        class = c("frs_network_features_scope_error", "error", "condition"),
        list(message = msg, call = NULL, parent = e)
      ))
    }
  )
  invisible(tmp)
}

# Internal (#272): the feature table cut to what fwa_downstream() can return
# for the segments in `tmp`: features on one of their blue lines (criterion
# 1), or whose wscode equals a segment's wscode or one of its ancestors
# (criterion 2, `wscode_a <@ wscode_b`). `= ANY (ARRAY(...))` lets each arm
# use the feature table's own index; `IN (SELECT ...)` read the whole table
# in link#261's measurements. Only the columns the walk reads are projected,
# because a feature view may carry geometry the walk never reads.
.frs_walk_prefilter <- function(features, tmp, cols_features,
                                features_wscode_col, segments_wscode_col) {
  sprintf(
    "(
      SELECT %1$s
      FROM %2$s f
      WHERE f.%3$s = ANY (ARRAY(
              SELECT DISTINCT subpath(s.%4$s, 0, k) FROM %5$s s, generate_series(1, nlevel(s.%4$s)) k))
         OR f.blue_line_key = ANY (ARRAY(SELECT DISTINCT s.blue_line_key FROM %5$s s))
    )",
    paste0("f.", cols_features, collapse = ", "),
    features,
    features_wscode_col,
    segments_wscode_col,
    tmp
  )
}

# Internal: parse a Postgres array literal (`{a,b,c}`) into a character
# vector. Handles the FWA-snapped-feature ID common case (alphanumeric
# IDs, no commas/quotes inside elements). For elements containing
# commas, quotes, or backslashes, callers should pass `parse_arrays =
# FALSE` (future arg) and handle the raw `pq__text` themselves -- or
# this helper should grow a full pg_array parser per
# https://www.postgresql.org/docs/current/arrays.html#ARRAYS-IO.
.frs_parse_pg_array <- function(s) {
  s <- as.character(s)
  if (length(s) == 0L || is.na(s)) return(character(0))
  if (!startsWith(s, "{") || !endsWith(s, "}")) return(character(0))
  inner <- substr(s, 2L, nchar(s) - 1L)
  if (!nzchar(inner)) return(character(0))
  parts <- strsplit(inner, ",", fixed = TRUE)[[1]]
  ifelse(parts == "NULL", NA_character_, parts)
}
