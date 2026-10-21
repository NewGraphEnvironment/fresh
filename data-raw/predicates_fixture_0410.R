# Freeze fresh 0.41.0's compiled habitat predicates for a fixed set of
# rules and thresholds, so the #263 byte-identity test compares against
# the released compiler rather than against itself.
#
# Run from a git worktree of the v0.41.0 tag, pointing at this checkout:
#   git worktree add <scratch>/fresh_0410 v0.41.0
#   Rscript data-raw/predicates_fixture_0410.R <scratch>/fresh_0410 .
# Inputs (copies, frozen 2026-10-21): fresh's bundled rules and thresholds,
# and link's `default` and `bcfishpass` bundles at link@0533ba52.
args <- commandArgs(trailingOnly = TRUE)
old_tree <- args[[1]]
this_tree <- args[[2]]
pkgload::load_all(old_tree, quiet = TRUE)
fx <- file.path(this_tree, "tests/testthat/fixtures/predicates_0410")
sets <- c(fresh = "fresh", link_default = "link_default",
          link_bcfishpass = "link_bcfishpass")
out <- list()
for (k in names(sets)) {
  params <- frs_params(
    csv = file.path(fx, sprintf("thresholds_%s.csv", sets[[k]])),
    rules_yaml = file.path(fx, sprintf("rules_%s.yaml", sets[[k]])))
  for (sp in names(params)) {
    for (model in c("cw", "mad")) {
      sp_params <- list(species_code = sp, spawn_gradient_min = 0,
                        spawn_gradient_max = params[[sp]]$spawn_gradient_max,
                        params_sp = params[[sp]])
      out[[paste(k, sp, model, sep = "/")]] <- frs_habitat_predicates(
        sp_params, model = model, near_river_table = "w.streams_near_river")
    }
  }
}
saveRDS(out, file.path(fx, "predicates.rds"), version = 3)
cat("wrote", length(out), "predicate sets\n")
