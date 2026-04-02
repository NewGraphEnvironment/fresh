#' Species Present in a Watershed Group
#'
#' Look up which species have bcfishpass habitat models for a given watershed
#' group code. Returns species codes and their corresponding bcfishpass view
#' names. Based on the
#' [wsg_species_presence.csv](https://github.com/smnorris/bcfishpass/blob/main/data/wsg_species_presence.csv)
#' bundled in the package.
#'
#' Some species share a combined view in bcfishpass: cutthroat trout (`ct`),
#' Dolly Varden (`dv`), and rainbow trout (`rb`) all use
#' `streams_ct_dv_rb_vw`. Arctic grayling (`gr`) has no bcfishpass view and
#' is excluded from view mapping.
#'
#' @param watershed_group_code Character. One or more watershed group codes
#'   (e.g. `"BULK"`, `c("BULK", "MORR")`).
#'
#' @return A data frame with columns:
#'   \describe{
#'     \item{watershed_group_code}{Watershed group code}
#'     \item{species_code}{Uppercase species code (e.g. `"CO"`, `"BT"`)}
#'     \item{view}{bcfishpass view name (e.g.
#'       `"bcfishpass.streams_co_vw"`), or `NA` for species without a view}
#'   }
#'
#' @family parameters
#'
#' @export
#'
#' @examples
#' # Which species are modelled in the Bulkley watershed group?
#' frs_wsg_species("BULK")
#'
#' # Multiple watershed groups
#' frs_wsg_species(c("BULK", "MORR"))
#'
#' # Just the unique views needed for BULK
#' sp <- frs_wsg_species("BULK")
#' unique(sp$view[!is.na(sp$view)])
frs_wsg_species <- function(watershed_group_code) {
  stopifnot(is.character(watershed_group_code), length(watershed_group_code) > 0)

  wsg <- .frs_wsg_presence()
  cols_species <- c("bt", "ch", "cm", "co", "ct", "dv", "gr",
                    "pk", "rb", "sk", "st", "wct")

  rows <- wsg[wsg$watershed_group_code %in% watershed_group_code, , drop = FALSE]
  if (nrow(rows) == 0) {
    missing <- setdiff(watershed_group_code, wsg$watershed_group_code)
    stop("Watershed group code(s) not found: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }

  # Build result: one row per wsg × species present
  out <- do.call(rbind, lapply(seq_len(nrow(rows)), function(i) {
    r <- rows[i, ]
    present <- cols_species[vapply(cols_species, function(sp) {
      identical(as.character(r[[sp]]), "t")
    }, logical(1))]
    if (length(present) == 0) return(NULL)
    data.frame(
      watershed_group_code = r$watershed_group_code,
      species_code = toupper(present),
      view = vapply(present, .frs_species_view, character(1),
                    USE.NAMES = FALSE),
      stringsAsFactors = FALSE,
      row.names = NULL
    )
  }))

  if (is.null(out)) {
    return(data.frame(watershed_group_code = character(),
                      species_code = character(),
                      view = character(),
                      stringsAsFactors = FALSE))
  }
  out
}


#' Map a species code to its bcfishpass view name
#'
#' @param sp Character. Lowercase species code.
#' @return Character. Schema-qualified view name, or `NA_character_`.
#' @noRd
.frs_species_view <- function(sp) {
  # ct, dv, rb share a combined view
  if (sp %in% c("ct", "dv", "rb")) return("bcfishpass.streams_ct_dv_rb_vw")
  # gr has no bcfishpass view
  if (sp == "gr") return(NA_character_)
  paste0("bcfishpass.streams_", sp, "_vw")
}


#' Load the bundled wsg_species_presence CSV (cached)
#' @return Data frame.
#' @noRd
.frs_wsg_presence <- function() {
  csv <- system.file("extdata", "wsg_species_presence.csv", package = "fresh")
  if (!nzchar(csv)) {
    stop("wsg_species_presence.csv not found in package extdata", call. = FALSE)
  }
  utils::read.csv(csv, stringsAsFactors = FALSE)
}
