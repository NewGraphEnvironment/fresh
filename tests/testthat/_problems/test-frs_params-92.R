# Extracted from test-frs_params.R:92

# test -------------------------------------------------------------------------
csv <- system.file("testdata", "test_params.csv", package = "fresh")
params <- frs_params(csv = csv)
expect_length(params$CO$rules$spawn, 2)
expect_length(params$CO$rules$rear, 4)
