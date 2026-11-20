# The guard behind test-test_table_names.R (#279): find fixed names in the
# shared `working` schema where a test can reach a database.
#
# A test_that() block is checked when its text opens or gates on a connection.
# A top-level expression is checked unless it drives a "mock" connection and
# names none of those, because a helper defined there can be handed a live
# connection by its caller. What is left alone drives a "mock" connection,
# where a `working.` name is SQL text that never reaches a database.
#
# Two things are flagged in a checked expression:
# - a string constant naming the working schema: `working.x`, a bare
#   "working", or 'working' inside SQL text;
# - a string literal passed straight to frs_habitat(label = ), which names
#   frs_habitat()'s own working.streams_<label> tables.
# A label held in a variable is out of its sight: build it with
# frs_test_label() where the variable is assigned.
.frs_test_live_pattern <- paste(
  "frs_db_conn\\(", "skip_if_no_conn", "local_fwapg", "frs_db_available",
  "dbConnect", sep = "|")

.frs_test_names_working <- function(x) {
  grepl("(^|[^A-Za-z0-9_.])working(\\.[A-Za-z_]|'|$)", x)
}

.frs_test_fixed_names <- function(file) {
  exprs <- parse(file, keep.source = TRUE)
  pd <- utils::getParseData(exprs, includeText = TRUE)
  out <- list()
  for (i in seq_along(exprs)) {
    e <- exprs[[i]]
    sr <- attr(exprs, "srcref")[[i]]
    txt <- paste(as.character(sr), collapse = "\n")
    is_test <- is.call(e) && identical(e[[1]], as.name("test_that"))
    live <- grepl(.frs_test_live_pattern, txt)
    if (is_test && !live) next
    if (!is_test && !live && grepl("[\"']mock[\"']", txt)) next
    # Rows of the parse data inside this expression's span
    in_span <- (pd$line1 > sr[1] | (pd$line1 == sr[1] & pd$col1 >= sr[2])) &
      (pd$line2 < sr[3] | (pd$line2 == sr[3] & pd$col2 <= sr[4]))
    span <- pd[in_span, ]

    s <- span[span$token == "STR_CONST", ]
    if (nrow(s)) {
      # getParseText(), not the text column: parse data abbreviates a long
      # string constant there
      val <- vapply(utils::getParseText(pd, s$id),
                    function(t) eval(parse(text = t)), character(1))
      hit <- .frs_test_names_working(val)
      if (any(hit)) {
        out[[length(out) + 1L]] <- data.frame(
          file = basename(file), line = s$line1[hit], kind = "working",
          text = unname(val[hit]), stringsAsFactors = FALSE)
      }
    }

    # frs_habitat(..., label = "<literal>")
    fc <- span[span$token == "SYMBOL_FUNCTION_CALL" & span$text == "frs_habitat", ]
    for (j in seq_len(nrow(fc))) {
      call_id <- pd$parent[pd$id == pd$parent[pd$id == fc$id[j]]]
      kids <- pd[pd$parent == call_id, ]
      kids <- kids[order(kids$line1, kids$col1), ]
      k <- which(kids$token == "SYMBOL_SUB" & kids$text == "label")
      for (m in k) {
        val_expr <- kids$id[m + 2L]
        lit <- pd[pd$parent == val_expr & pd$token == "STR_CONST", ]
        if (nrow(lit)) {
          out[[length(out) + 1L]] <- data.frame(
            file = basename(file), line = lit$line1[1], kind = "label",
            text = eval(parse(text = utils::getParseText(pd, lit$id[1]))),
            stringsAsFactors = FALSE)
        }
      }
    }
  }
  if (!length(out)) {
    return(data.frame(file = character(), line = integer(), kind = character(),
                      text = character(), stringsAsFactors = FALSE))
  }
  do.call(rbind, out)
}
