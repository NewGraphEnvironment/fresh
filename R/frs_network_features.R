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

  # Phase 2 (next commit): replace this stop() with the SQL implementation.
  stop("`frs_network_features()` SQL body lands in Phase 2 of #201. ",
       "Validation passed for: direction = \"", direction, "\", aoi = \"",
       aoi %||% "NULL", "\".",
       call. = FALSE)
}
