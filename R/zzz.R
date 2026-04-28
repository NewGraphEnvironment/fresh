.onAttach <- function(libname, pkgname) {
  f <- system.file("extdata", "quotes.csv", package = pkgname)
  if (!nzchar(f)) return(invisible())
  q <- utils::read.csv(f, stringsAsFactors = FALSE, encoding = "UTF-8")
  if (nrow(q) == 0) return(invisible())
  row <- q[sample(nrow(q), 1), ]
  packageStartupMessage(sprintf("\n '%s' - %s", row$quote, row$author))
}
