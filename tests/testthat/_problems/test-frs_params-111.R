# Extracted from test-frs_params.R:111

# test -------------------------------------------------------------------------
tmp <- tempfile(fileext = ".yaml")
on.exit(unlink(tmp))
writeLines(c(
    "CO:",
    "  spawn:",
    "    - edge_types: [stream, canal]",
    "      mad: [0.164, 9999]"), tmp)
rules <- .frs_load_rules(tmp)
