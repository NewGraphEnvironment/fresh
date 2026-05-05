#' Per-Segment Arrays of Features Relative to a Stream Network
#'
#' For each row in a segments table, return an array of feature IDs
#' from a features table that lie at the requested relative position
#' (downstream of, or upstream of) that segment in the FWA stream
#' network. The features can be any point dataset snapped to FWA —
#' barriers, crossings, observations, water-quality stations, fish
#' surveys, sediment-sample points, weather stations — anything with
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
#'   `"observation_key"`, `"station_id"`). **Required — no default;
#'   caller passes the actual column name.**
#' @param direction Character. **Required — no default.** One of
#'   `"downstream"` or `"upstream"`. `"downstream"` returns features
#'   that lie below each segment (toward the river mouth). `"upstream"`
#'   returns features above each segment.
#' @param aoi Character. Optional area-of-interest filter on segments.
#'   Today only WSG codes (e.g. `"ADMS"`, `"BULK"`) are supported and
#'   filter `segments.watershed_group_code = aoi`. Polygon / ltree AOIs
#'   are forward-compat — they will route through `.frs_resolve_aoi()`
#'   when generalised. Default `NULL` processes every row in the
#'   segments table.
#' @param include_equivalents Logical. When `TRUE`, treats segments
#'   at the same `(blue_line_key, downstream_route_measure)` position
#'   as relative-direction matches of each other. Mirrors bcfishpass's
#'   `include_equivalents` arg. Default `FALSE`.
#'
#' @return A tibble with two columns:
#'   - `<segment_id_col>` — matches the input column name on segments
#'   - `feature_ids` — a `text[]` array of feature IDs in the requested
#'     direction relative to each segment. **`NULL` when zero matches**
#'     (don't expect synthesised empty arrays — `array_agg` over zero
#'     rows is `NULL` in Postgres and that propagates).
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
    include_equivalents = FALSE) {

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
           "are not yet supported in this function — file a follow-up ",
           "if needed.", call. = FALSE)
    }
  }

  fwa_predicate <- if (direction == "downstream") {
    "whse_basemapping.fwa_downstream"
  } else {
    "whse_basemapping.fwa_upstream"
  }

  ie_arg <- if (isTRUE(include_equivalents)) "true" else "false"

  # `aoi` is regex-validated `^[A-Z]{3,5}$` above — safe to interpolate
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
          a.wscode_ltree, a.localcode_ltree,
          b.blue_line_key, b.downstream_route_measure,
          b.wscode_ltree, b.localcode_ltree,
          %6$s, 1
        )
      %7$s
      ORDER BY a.%1$s,
               b.wscode_ltree DESC,
               b.localcode_ltree DESC,
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
    aoi_filter
  )

  res <- frs_db_query(conn, sql)
  names(res)[1] <- segment_id_col
  res
}
