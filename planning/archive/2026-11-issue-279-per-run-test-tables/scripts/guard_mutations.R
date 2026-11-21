# Guard mutation table for #279: each mutation goes into a copy of a real test file; the tree is not touched.
# Run from the repo root: Rscript <this> <scratch dir>
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-test_names.R")
dt <- .frs_test_default_to()
td <- "tests/testthat"
muts <- list(
  list(f = "test-frs_extract.R", a = 'frs_test_tbl("test_extract")', b = '"working.test_extract"', what = "fixed literal"),
  list(f = "test-frs_extract.R", a = 'frs_test_tbl("test_extract")', b = 'paste0("working.", "test_extract")', what = "paste0 fragment"),
  list(f = "test-frs_extract.R", a = 'frs_test_tbl("test_extract")', b = '"WORKING.test_extract"', what = "upper case"),
  list(f = "test-utils.R", a = '"CREATE UNIQUE INDEX %s_pkey', b = '"CREATE UNIQUE INDEX test_282_uniq_pkey', what = "fixed index name"),
  list(f = "test-frs_habitat_classify.R", a = 'label = frs_test_label(label)', b = 'label = label', what = "label through a variable"),
  list(f = "test-frs_habitat.R", a = 'label = frs_test_label("n143"),', b = 'label = frs_test_label("n143"), wsg = "BULK",', what = "wsg-mode call"),
  list(f = "test-frs_barriers_minimal.R", a = ',\n                         to = frs_test_tbl("test_bm_nocols_min"))', b = ')', what = "default to"),
  list(f = "test-utils.R", a = 'sprintf("SET search_path TO %s, public",\n                               frs_test_tbl_parts(src)$schema)', b = '"SET search_path TO working, public"', what = "search_path")
)
base <- .frs_test_guard_files(td)
cat("unmutated hits:", nrow(.frs_test_fixed_names(base, dt, defs_from = .frs_test_guard_defs(td))), "\n")
for (m in muts) {
  src <- paste(readLines(file.path(td, m$f)), collapse = "\n")
  n <- lengths(regmatches(src, gregexpr(m$a, src, fixed = TRUE)))
  if (n < 1) { cat(sprintf("%-26s NOT APPLIED (anchor missing)\n", m$what)); next }
  dst <- file.path(commandArgs(TRUE)[1], m$f)
  writeLines(sub(m$a, m$b, src, fixed = TRUE), dst)
  h <- .frs_test_fixed_names(c(setdiff(base, file.path(td, m$f)), dst), dt, defs_from = .frs_test_guard_defs(td))
  cat(sprintf("%-26s %s  %s\n", m$what, if (nrow(h)) "RED  " else "GREEN",
              paste(unique(paste0(h$kind, "@", h$line)), collapse = " ")))
}
