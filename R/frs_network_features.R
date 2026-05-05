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
#'   segments table.
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
#'
#' @return A tibble with two columns:
#'   - `<segment_id_col>` -- matches the input column name on segments.
#'   - `feature_ids` -- an R list-column of character vectors (one
#'     vector per row). The vectors carry the feature IDs aggregated
#'     from the requested direction, ordered by
#'     `(wscode_col DESC, localcode_col DESC, downstream_route_measure
#'     DESC)` to mirror `bcfishpass.load_dnstr`. Segments with zero
#'     matches don't appear in the output (INNER JOIN). Postgres
#'     array literals are parsed to R character vectors via the
#'     internal `.frs_parse_pg_array()` helper -- limited to
#'     unquoted-element arrays (the common case for FWA-snapped IDs).
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
    features_localcode_col = "localcode_ltree") {

  if (missing(direction)) {
    stop("`direction` is required (no default). ",
         "Use one of: \"downstream\", \"upstream\".",
         call. = FALSE)
  }
  direction <- match.arg(direction, c("downstream", "upstream"))

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

  # `aoi` is regex-validated `^[A-Z]{3,5}$` above -- safe to interpolate
  # without runtime quoting (no SQL-injection vector).
  aoi_filter <- if (!is.null(aoi)) {
    sprintf("WHERE a.watershed_group_code = '%s'", aoi)
  } else {
    ""
  }

  # SQL pattern mirrors bcfishpass.load_dnstr exactly:
  # subquery-with-INNER-JOIN feeding array_agg + GROUP BY on segment_id.
  # The `ORDER BY a.<id>, b.wscode DESC, b.localcode DESC, b.drm DESC`
  # at the subquery level is what gives bcfp its canonical element
  # ordering; we preserve byte-identical output by reproducing the same
  # subquery shape.
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
      FROM %3$s a
      INNER JOIN %4$s b ON
        %5$s(
          a.blue_line_key, a.downstream_route_measure,
          a.%8$s, a.%9$s,
          b.blue_line_key, b.downstream_route_measure,
          b.%10$s, b.%11$s,
          %6$s, 1
        )
      %7$s
      ORDER BY a.%1$s,
               b.%10$s DESC,
               b.%11$s DESC,
               b.downstream_route_measure DESC
    ) d
    GROUP BY d.%1$s"

  sql <- sprintf(
    sql_fmt,
    segment_id_col,
    feature_id_col,
    segments,
    features,
    fwa_predicate,
    ie_arg,
    aoi_filter,
    segments_wscode_col,
    segments_localcode_col,
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
