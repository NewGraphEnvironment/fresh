#!/usr/bin/env Rscript
# Mutation sweep: prove that each guard in R/ is caught by a named test
# (fresh#280). Addresses every site by text, never by line number, so a
# site list survives edits that do not touch the predicate itself.
#
# Usage, from the package root, with the tests' environment (PG* vars):
#
#   Rscript dev/mutation_sweep.R <sites.csv> <test filter> [results.csv]
#
# <sites.csv>: one row per site, columns
#   label        short name for the table
#   file         path from the package root, e.g. R/frs_habitat.R
#   pattern      fixed text, not a regex; the site is the `occurrence`-th
#                line of `file` that contains it
#   occurrence   1-based count of matching lines
#   action       "delete" removes that line; "substitute" replaces the
#                first `pattern` on that line with `replacement`
#   replacement  for substitute; may be empty
# <test filter>: testthat's `filter`, a regex on test file names without
#   the test- prefix and .R suffix, e.g. "frs_bucket_connected".
# [results.csv]: defaults to <sites>_results.csv beside the site list.
#
# What it does:
#   1. copies DESCRIPTION NAMESPACE .Rbuildignore R man tests inst to a
#      temp directory: all pkgload::load_all() needs, and never the whole
#      working tree, which can carry caches and rasters;
#   2. checks every site matches before any test runs: a pattern with
#      fewer matching lines than `occurrence` is an error, not a miss;
#   3. runs the filtered tests on the unmutated copy and REFUSES unless
#      that baseline is 0 red and 0 skipped (a skip and a pass are
#      indistinguishable in a summary line, so a sweep over a skipping
#      baseline proves nothing);
#   4. per site: applies the one mutation, runs the tests, records how
#      many tests went red or skipped and the names of the red ones, and
#      restores the file;
#   5. prints the table and writes it to results.csv.
#
# A site whose mutated copy fails to load (a deleted line that also closed
# a string or a call) is recorded as an ERROR row and counted as uncaught:
# re-specify it, usually as a substitute.
#
# Exit status: 0 every site caught; 1 at least one site caught by no
# test; 2 refused (baseline not clean, bad input, unmatched site).
#
# One sweep at a time per database: each site is a full test run against
# the same database the suite uses (fresh#242 findings, "Errors
# Encountered").

sweep_cols <- c("label", "file", "pattern", "occurrence", "action", "replacement")

# Copy the package sources load_all() needs, nothing else.
sweep_copy <- function(pkg, to) {
  parts <- c("DESCRIPTION", "NAMESPACE", ".Rbuildignore", "R", "man", "tests", "inst")
  need <- c("DESCRIPTION", "NAMESPACE", "R", "tests")
  have <- parts[file.exists(file.path(pkg, parts))]
  absent <- setdiff(need, have)
  if (length(absent)) {
    stop("not a package root: ", pkg, " has no ", paste(absent, collapse = ", "))
  }
  dir.create(to, recursive = TRUE, showWarnings = FALSE)
  ok <- file.copy(file.path(pkg, have), to, recursive = TRUE)
  if (!all(ok)) stop("copy failed: ", paste(have[!ok], collapse = ", "))
  invisible(to)
}

# Read and validate the site list. Every column is character; occurrence
# is coerced and checked here so a bad row fails before any test runs.
sweep_sites_read <- function(path) {
  sites <- utils::read.csv(path, colClasses = "character",
                           na.strings = character(), strip.white = FALSE)
  absent <- setdiff(sweep_cols, names(sites))
  if (length(absent)) {
    stop(path, " lacks column(s): ", paste(absent, collapse = ", "))
  }
  if (nrow(sites) == 0) stop(path, " lists no sites")
  occ <- suppressWarnings(as.integer(sites$occurrence))
  bad <- is.na(occ) | occ < 1 | occ != as.numeric(sites$occurrence)
  if (any(bad)) {
    stop("occurrence must be a positive integer; not so for site(s): ",
         paste(sites$label[bad], collapse = ", "))
  }
  sites$occurrence <- occ
  bad <- !sites$action %in% c("delete", "substitute")
  if (any(bad)) {
    stop("action must be delete or substitute; not so for site(s): ",
         paste(sites$label[bad], collapse = ", "))
  }
  bad <- !nzchar(sites$pattern)
  if (any(bad)) {
    stop("pattern is empty for site(s): ", paste(sites$label[bad], collapse = ", "))
  }
  bad <- sites$action == "substitute" & sites$replacement == sites$pattern
  if (any(bad)) {
    stop("replacement equals pattern (no mutation) for site(s): ",
         paste(sites$label[bad], collapse = ", "))
  }
  bad <- duplicated(sites$label)
  if (any(bad)) {
    stop("duplicate label(s): ", paste(unique(sites$label[bad]), collapse = ", "))
  }
  sites
}

# Apply one site's mutation to a file's lines. Errors name the site when
# the pattern has fewer matching lines than `occurrence` asks for.
sweep_mutate <- function(lines, site) {
  hits <- which(grepl(site$pattern, lines, fixed = TRUE))
  if (length(hits) < site$occurrence) {
    stop(sprintf("site %s: pattern %s matches %d line(s) of %s, occurrence %d asked",
                 sQuote(site$label), sQuote(site$pattern), length(hits),
                 site$file, site$occurrence))
  }
  i <- hits[site$occurrence]
  if (site$action == "delete") {
    return(lines[-i])
  }
  # substitute: first match on that line, both strings taken literally
  pos <- regexpr(site$pattern, lines[i], fixed = TRUE)
  lines[i] <- paste0(substr(lines[i], 1L, pos - 1L), site$replacement,
                     substr(lines[i], pos + attr(pos, "match.length"),
                            nchar(lines[i])))
  lines
}

# Run the filtered tests on the copy. One row per test: red is a failed
# expectation or an uncaught error (testthat counts those separately).
sweep_run <- function(copy, filter) {
  res <- testthat::test_local(copy, filter = filter, reporter = "silent",
                              stop_on_failure = FALSE, stop_on_warning = FALSE)
  df <- as.data.frame(res)
  if (nrow(df) == 0) stop("filter ", sQuote(filter), " matched no tests")
  data.frame(file = df$file, test = df$test,
             red = df$failed > 0 | df$error, skipped = df$skipped,
             stringsAsFactors = FALSE)
}

sweep_main <- function(args) {
  options(width = 200)
  if (length(args) < 2 || length(args) > 3) {
    cat("usage: Rscript dev/mutation_sweep.R <sites.csv> <test filter> [results.csv]\n")
    return(2L)
  }
  sites_path <- args[[1]]
  filter <- args[[2]]
  out <- if (length(args) == 3) args[[3]] else
    paste0(sub("\\.csv$", "", sites_path), "_results.csv")
  pkg <- normalizePath(".")
  sites <- sweep_sites_read(sites_path)

  copy <- tempfile("mutation_sweep_")
  on.exit(unlink(copy, recursive = TRUE), add = TRUE)
  sweep_copy(pkg, copy)
  cat("copied", length(list.files(copy, recursive = TRUE)), "files to", copy, "\n")

  # Every site must resolve before the first test run
  originals <- list()
  for (k in seq_len(nrow(sites))) {
    f <- file.path(copy, sites$file[k])
    if (!file.exists(f)) {
      stop("site ", sQuote(sites$label[k]), ": no such file ", sites$file[k])
    }
    if (is.null(originals[[sites$file[k]]])) {
      originals[[sites$file[k]]] <- readLines(f, warn = FALSE)
    }
    invisible(sweep_mutate(originals[[sites$file[k]]], sites[k, ]))
  }

  Sys.setenv(NOT_CRAN = "true")
  cat("baseline: filter", sQuote(filter), "\n")
  base <- sweep_run(copy, filter)
  bad <- base[base$red | base$skipped, ]
  if (nrow(bad)) {
    cat(sprintf("REFUSED: baseline is %d red, %d skipped of %d tests; a sweep needs 0 and 0\n",
                sum(base$red), sum(base$skipped), nrow(base)))
    print(bad, row.names = FALSE, right = FALSE)
    return(2L)
  }
  cat(sprintf("baseline: %d tests, 0 red, 0 skipped\n", nrow(base)))

  rows <- vector("list", nrow(sites))
  for (k in seq_len(nrow(sites))) {
    site <- sites[k, ]
    f <- file.path(copy, site$file)
    writeLines(sweep_mutate(originals[[site$file]], site), f)
    # A mutation that no longer parses (a deleted line closed a string or
    # a call) is a mis-specified site, not a caught one: record it and go
    # on, so one such site does not throw the rest of the sweep away.
    r <- tryCatch(sweep_run(copy, filter), error = function(e) e)
    writeLines(originals[[site$file]], f)
    if (inherits(r, "error")) {
      # rlang chains the parse error under $parent; keep both first lines
      msg <- paste(vapply(c(list(r), list(r$parent)[!is.null(r$parent)]),
                          function(e) strsplit(conditionMessage(e), "\n", fixed = TRUE)[[1]][1],
                          character(1)), collapse = " | ")
      cat(sprintf("[%d/%d] %s: ERROR %s\n", k, nrow(sites), site$label, msg))
      rows[[k]] <- data.frame(label = site$label, file = site$file,
                              action = site$action, occurrence = site$occurrence,
                              red = NA_integer_, skipped = NA_integer_,
                              caught = FALSE, caught_by = paste("ERROR:", msg),
                              stringsAsFactors = FALSE)
      next
    }
    caught_by <- r$test[r$red]
    cat(sprintf("[%d/%d] %s: %d red, %d skipped\n", k, nrow(sites), site$label,
                length(caught_by), sum(r$skipped)))
    rows[[k]] <- data.frame(label = site$label, file = site$file,
                            action = site$action, occurrence = site$occurrence,
                            red = length(caught_by), skipped = sum(r$skipped),
                            caught = length(caught_by) > 0,
                            caught_by = paste(caught_by, collapse = "; "),
                            stringsAsFactors = FALSE)
  }
  tbl <- do.call(rbind, rows)
  utils::write.csv(tbl, out, row.names = FALSE)

  # Console: clip caught_by so the table stays one row per site; the CSV
  # carries every name
  shown <- tbl
  long <- nchar(shown$caught_by) > 70
  shown$caught_by[long] <- paste0(substr(shown$caught_by[long], 1, 67), "...")
  cat("\n")
  print(shown, row.names = FALSE, right = FALSE)
  uncaught <- sum(!tbl$caught)
  cat(sprintf("\nsites with no test catching them: %d of %d\n", uncaught, nrow(tbl)))
  cat("saved:", out, "\n")
  if (uncaught > 0) 1L else 0L
}

if (sys.nframe() == 0L) {
  # Bad input (an unmatched site, a malformed list) is a refusal too: exit
  # 2, not R's default 1, which is the "swept, one site uncaught" status
  status <- tryCatch(sweep_main(commandArgs(trailingOnly = TRUE)),
                     error = function(e) {
                       cat("REFUSED:", conditionMessage(e), "\n")
                       2L
                     })
  quit(save = "no", status = status)
}
