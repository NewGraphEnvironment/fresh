# Extracted from test-frs_params.R:653

# test -------------------------------------------------------------------------
rule <- list(edge_types_explicit = c(1000L), mad = c(0.03, 40))
csv_thresholds <- list(
    gradient = c(0, 0.0549),
    channel_width = c(1.5, 9999))
sql <- .frs_rule_to_sql(rule, csv_thresholds)
expect_match(sql, "s\\.edge_type IN \\(1000\\)")
expect_match(sql, "s\\.gradient BETWEEN 0 AND 0\\.0549")
expect_match(sql, "s\\.channel_width BETWEEN 1\\.5 AND 9999")
expect_match(sql, "s\\.mad_m3s BETWEEN 0\\.03 AND 40")
