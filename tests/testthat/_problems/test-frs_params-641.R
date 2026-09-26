# Extracted from test-frs_params.R:641

# test -------------------------------------------------------------------------
sql <- .frs_rule_to_sql(list(mad = c(0.164, 9999)))
expect_equal(sql, "(s.mad_m3s BETWEEN 0.164 AND 9999)")
