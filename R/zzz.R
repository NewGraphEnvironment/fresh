.onAttach <- function(libname, pkgname) {
  f <- system.file("extdata", "quotes.csv", package = pkgname)
  if (!nzchar(f)) return(invisible())
  q <- utils::read.csv(f, stringsAsFactors = FALSE, encoding = "UTF-8")
  if (nrow(q) == 0) return(invisible())
  row <- q[sample(nrow(q), 1), ]
  quote_fmt <- cli::style_italic(sprintf("'%s'", row$quote))
  msg <- sprintf("\n %s %s", quote_fmt, cli::col_grey(paste0("- ", row$author)))
  if (isTRUE(getOption("frs.quote_show_source", TRUE)) &&
      !is.null(row$source) && nzchar(row$source)) {
    link <- cli::style_hyperlink(cli::col_blue("source"), row$source)
    msg <- paste0(msg, "\n  ", link)
  }
  packageStartupMessage(msg)
}
