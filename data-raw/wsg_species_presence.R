# Fetch watershed group species presence from upstream (smnorris/bcfishpass)
#
# Maps which species to model in each BC watershed group.
# Used by frs_wsg_species() to determine which bcfishpass views to query.
#
# Source: https://github.com/smnorris/bcfishpass/blob/main/data/wsg_species_presence.csv

url <- "https://raw.githubusercontent.com/smnorris/bcfishpass/main/data/wsg_species_presence.csv"
wsg <- read.csv(url, stringsAsFactors = FALSE)

write.csv(wsg, "inst/extdata/wsg_species_presence.csv", row.names = FALSE)

cat("Saved inst/extdata/wsg_species_presence.csv\n")
cat("  Watershed groups:", nrow(wsg), "\n")
cols_species <- c("bt", "ch", "cm", "co", "ct", "dv", "gr", "pk", "rb", "sk", "st", "wct")
for (sp in cols_species) {
  n <- sum(wsg[[sp]] == "t", na.rm = TRUE)
  if (n > 0) cat("  ", toupper(sp), ": ", n, " WSGs\n", sep = "")
}
