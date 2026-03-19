# Fetch bcfishpass habitat parameters from upstream (smnorris/bcfishpass)
#
# These are the NewGraph defaults — thresholds by species and the
# MAD vs channel_width method control per watershed group.
#
# Source: https://github.com/smnorris/bcfishpass/tree/main/parameters/example_newgraph

base_url <- "https://raw.githubusercontent.com/smnorris/bcfishpass/main/parameters/example_newgraph"

thresholds <- read.csv(paste0(base_url, "/parameters_habitat_thresholds.csv"))
method <- read.csv(paste0(base_url, "/parameters_habitat_method.csv"))

write.csv(thresholds, "inst/extdata/parameters_habitat_thresholds.csv",
          row.names = FALSE)
write.csv(method, "inst/extdata/parameters_habitat_method.csv",
          row.names = FALSE)

# Access gradient thresholds — not in bcfishpass parameter CSVs,
# hardcoded in model_access_*.sql scripts. See fresh#54 for source mapping.
access <- data.frame(
  species_code = c("BT", "CH", "CM", "CO", "CT", "DV", "PK", "RB", "SK", "ST", "WCT"),
  access_gradient_max = c(0.25, 0.15, 0.15, 0.15, 0.25, 0.25, 0.15, 0.25, 0.15, 0.20, 0.20),
  spawn_gradient_min = rep(0.005, 11),
  rear_gradient_min = rep(0, 11)
)
write.csv(access, "inst/extdata/parameters_fresh.csv",
          row.names = FALSE)

cat("Saved inst/extdata/parameters_habitat_thresholds.csv\n")
cat("  Species:", paste(thresholds$species_code, collapse = ", "), "\n")
cat("Saved inst/extdata/parameters_habitat_method.csv\n")
cat("  Watershed groups:", nrow(method), "\n")
cat("  Methods:", paste(unique(method$model), collapse = ", "), "\n")
cat("Saved inst/extdata/parameters_fresh.csv\n")
cat("  Species:", paste(access$species_code, collapse = ", "), "\n")
