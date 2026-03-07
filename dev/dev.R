# fresh — dev setup script
# Run interactively, not idempotent.

# 1. Package scaffold
usethis::create_package(".")
usethis::use_mit_license("New Graph Environment Ltd.")
usethis::use_testthat(edition = 3)
usethis::use_pkgdown()
usethis::use_directory("dev")
usethis::use_directory("data-raw")
usethis::use_github_action("pkgdown")

# 2. GitHub repo
# gh repo create NewGraphEnvironment/fresh --private --source . --push

# 3. Branch protection
# gh api repos/NewGraphEnvironment/fresh/rulesets --method POST --input - <<'EOF'
# {
#   "name": "Protect main",
#   "target": "branch",
#   "enforcement": "active",
#   "bypass_actors": [
#     { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" }
#   ],
#   "conditions": { "ref_name": { "include": ["refs/heads/main"], "exclude": [] } },
#   "rules": [ { "type": "deletion" }, { "type": "non_fast_forward" } ]
# }
# EOF

# 4. GitHub Pages — set to serve from gh-pages branch after first pkgdown deploy

# 5. Hex sticker
# source("data-raw/make_hexsticker.R")
