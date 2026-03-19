#' FWA Edge Type Lookup Table
#'
#' Return the FWA edge type codes bundled with this package, optionally
#' filtered by category. Source: Table 2 "Edge Type Code Table" from the
#' GeoBC Freshwater Atlas User Guide (GeoBC 2009, p. 11).
#'
#' @param category Character or `NULL`. If provided, filter to rows matching
#'   this category. One of `"lake"`, `"wetland"`, `"river"`, `"stream"`,
#'   `"subsurface"`, `"connector"`, `"construction"`, `"boundary"`,
#'   `"unknown"`. Default `NULL` returns all rows.
#'
#' @return A data.frame with columns `edge_type` (integer), `description`
#'   (character), and `category` (character).
#'
#' @family reference
#'
#' @export
#'
#' @examples
#' # All edge types
#' frs_edge_types()
#'
#' # Just lake codes
#' frs_edge_types(category = "lake")
#'
#' # Stream-type codes (definite, probable, intermittent, inferred)
#' frs_edge_types(category = "stream")
#'
#' # Use with frs_classify() to scope classification by waterbody type
#' lake_codes <- frs_edge_types(category = "lake")$edge_type
#' paste("edge_type IN (", paste(lake_codes, collapse = ", "), ")")
frs_edge_types <- function(category = NULL) {
  path <- system.file("extdata", "edge_types.csv", package = "fresh")
  if (!nzchar(path)) {
    stop("edge_types.csv not found in fresh package", call. = FALSE)
  }
  d <- read.csv(path, stringsAsFactors = FALSE)

  if (!is.null(category)) {
    stopifnot(is.character(category), length(category) == 1)
    valid <- unique(d$category)
    if (!category %in% valid) {
      stop(sprintf("category must be one of: %s", paste(valid, collapse = ", ")),
           call. = FALSE)
    }
    d <- d[d$category == category, ]
  }

  d
}
