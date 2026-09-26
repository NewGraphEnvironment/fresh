# Extracted from test-frs_params.R:125

# test -------------------------------------------------------------------------
write_mad <- function(val) {
    tmp <- tempfile(fileext = ".yaml")
    writeLines(c("CO:", "  spawn:", paste0("    - mad: ", val)), tmp)
    tmp
  }
bad <- c("[a, b]", "[0.5]", "[0.5, 1, 2]", "0.5", "[10, 1]")
for (val in bad) {
    tmp <- write_mad(val)
    expect_error(.frs_load_rules(tmp), "CO/spawn rule 1 mad must be",
                 info = val)
    unlink(tmp)
  }
