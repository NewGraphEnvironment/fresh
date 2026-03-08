#' Filter Stream Segments by Strahler Order
#'
#' Simple filter on an sf data frame of stream segments. Keeps rows where
#' `stream_order >= min_order`.
#'
#' @param streams An `sf` data frame with a `stream_order` column (e.g. from
#'   [frs_stream_fetch()] or [frs_network_upstream()]).
#' @param min_order Integer. Minimum Strahler stream order to keep.
#'
#' @return An `sf` data frame with low-order streams removed.
#'
#' @family prune
#'
#' @export
#'
#' @examples
#' \dontrun{
#' streams <- frs_stream_fetch(watershed_group_code = "BULK")
#' big_streams <- frs_order_filter(streams, min_order = 4)
#' }
frs_order_filter <- function(streams, min_order) {
  stopifnot("stream_order" %in% names(streams))
  streams[streams$stream_order >= min_order, ]
}
