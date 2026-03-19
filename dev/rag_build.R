# Build ragnar search store from FWA User Guide
#
# Local developer tool — output gitignored at data/rag/.
# Requires: ragnar, Ollama running with nomic-embed-text model.
#
# Source: GeoBC (2010) Freshwater Atlas User Guide
# Zotero parent key: S2EMGWR5, attachment key: NC5QSXCI
#
# Usage: source this file interactively, or:
#   Rscript dev/rag_build.R

library(ragnar)

pdf_path <- path.expand("~/Zotero/storage/NC5QSXCI/fwa_user_guide.pdf")
store_path <- file.path("data", "rag", "fwa_user_guide.duckdb")

if (!file.exists(pdf_path)) {
  stop("FWA User Guide PDF not found at: ", pdf_path,
       "\nCheck Zotero storage for attachment key NC5QSXCI")
}

fs::dir_create(dirname(store_path))

store <- ragnar_store_create(
  location = store_path,
  embed = embed_ollama(model = "nomic-embed-text"),
  overwrite = TRUE
)

ragnar_store_ingest(store, pdf_path, progress = TRUE)

n_chunks <- DBI::dbGetQuery(store@con, "SELECT COUNT(*) AS n FROM chunks")$n
DBI::dbDisconnect(store@con)

cat("Store:", store_path, "| Chunks:", n_chunks, "\n")
