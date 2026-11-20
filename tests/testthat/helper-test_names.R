# The guard behind test-test_table_names.R (#279): find names that two test
# runs against one database would share, where a test can reach a database.
#
# Which expressions are checked:
# - a test_that() block, when it opens or gates on a connection: a call to
#   frs_db_conn(), skip_if_no_conn(), skip_if_no_schema(), local_fwapg(),
#   frs_fwapg_conn(), .frs_db_available() or dbConnect(), or to any top-level
#   function in the scanned files that itself calls one (so a file's own
#   connector, such as bcfp_conn(), counts);
# - a top-level expression, unless it drives a "mock" connection (a "mock"
#   or "mock_conn" string constant) and calls none of those, because a helper
#   defined there can be handed a live connection by its caller.
# What is left alone drives a mock connection, where a `working.` name is SQL
# text that never reaches a database.
#
# What is flagged in a checked expression:
# - "working": a string constant naming the working schema, in any case and
#   quoting: `working.x`, a `"working."` fragment, 'working' or "working" in
#   SQL, a bare "working", or a search_path that holds it. "CREATE SCHEMA IF
#   NOT EXISTS working" names no table and is not flagged;
# - "index": a fixed name in CREATE INDEX or CONSTRAINT, since an index name
#   is unique within its schema;
# - "label": a frs_habitat() label not built with frs_test_label(), which
#   would name frs_habitat()'s own working.streams_<label> tables;
# - "wsg": a frs_habitat() call in watershed-group mode, whose working tables
#   are named after the group and cannot be made per run;
# - "to": a call that leaves `to` at a default inside the working schema.
#
# Out of its sight: a bare table name ("test_x" compared with
# information_schema's table_name), and a name assembled in a variable
# somewhere else. Use frs_test_tbl_parts() for the first.
.frs_test_live_base <- c("frs_db_conn", "skip_if_no_conn", "skip_if_no_schema",
                         "local_fwapg", "frs_fwapg_conn", ".frs_db_available",
                         "dbConnect")

.frs_test_names_working <- function(x) {
  grepl("(^|[^A-Za-z0-9_.])\"?working\"?[.'\",]", x, ignore.case = TRUE) |
    grepl("^\\s*working\\s*$", x, ignore.case = TRUE) |
    grepl("search_path[^;]*\\bworking\\b", x, ignore.case = TRUE)
}

.frs_test_names_index <- function(x) {
  grepl(paste0("\\bCREATE\\s+(UNIQUE\\s+)?INDEX\\s+(CONCURRENTLY\\s+)?",
               "(IF\\s+NOT\\s+EXISTS\\s+)?[A-Za-z_][A-Za-z0-9_]*\\s+ON\\b"),
        x, ignore.case = TRUE) |
    grepl("\\bCONSTRAINT\\s+[A-Za-z_]", x, ignore.case = TRUE)
}

# Functions whose `to` defaults into the working schema, with the position of
# `to` among their formals, read from the package so the list keeps itself
# current.
.frs_test_default_to <- function(ns = asNamespace("fresh")) {
  out <- list()
  for (f in ls(ns, all.names = TRUE)) {
    fn <- get(f, envir = ns)
    if (!is.function(fn)) next
    fm <- formals(fn)
    if (is.null(fm) || !"to" %in% names(fm)) next
    # Deparsed straight from the list: a formal with no default is the empty
    # symbol, which errors when assigned and then read.
    txt <- paste(deparse(fm[["to"]]), collapse = "")
    if (grepl("working\\.", txt)) out[[f]] <- match("to", names(fm))
  }
  unlist(out)
}

# Parse data of each top-level expression of `file`: its own rows, collected
# by parse id (columns would drift on a line with a multibyte character), and
# the whole file's, for getParseText().
.frs_test_blocks <- function(file) {
  exprs <- parse(file, keep.source = TRUE)
  pd <- utils::getParseData(exprs, includeText = TRUE)
  top <- pd[pd$parent == 0 & pd$token != "COMMENT", ]
  top <- top[order(top$line1, top$col1), ]
  stopifnot(nrow(top) == length(exprs))
  lapply(seq_len(nrow(top)), function(i) {
    ids <- top$id[i]
    repeat {
      more <- setdiff(pd$id[pd$parent %in% ids], ids)
      if (!length(more)) break
      ids <- c(ids, more)
    }
    list(expr = exprs[[i]], pd = pd[pd$id %in% ids, ], all = pd)
  })
}

# String constants' values, from getParseText(): the parse data's own text
# column abbreviates a long one.
.frs_test_str <- function(all, id) {
  vapply(utils::getParseText(all, id), function(t) eval(parse(text = t)),
         character(1), USE.NAMES = FALSE)
}

# The arguments of the call named by the SYMBOL_FUNCTION_CALL row `fc_id`:
# one row each, with its name ("" when positional) and its expr id.
.frs_test_call_args <- function(pd, fc_id) {
  fn_expr <- pd$parent[pd$id == fc_id]
  call_id <- pd$parent[pd$id == fn_expr]
  kids <- pd[pd$parent == call_id, ]
  kids <- kids[order(kids$line1, kids$col1), ]
  kids <- kids[kids$id != fn_expr & kids$token != "COMMENT", ]
  nm <- character(); id <- integer(); cur <- ""
  for (k in seq_len(nrow(kids))) {
    if (kids$token[k] == "SYMBOL_SUB") {
      cur <- kids$text[k]
    } else if (kids$token[k] == "expr") {
      nm <- c(nm, cur); id <- c(id, kids$id[k]); cur <- ""
    }
  }
  data.frame(name = nm, id = id, stringsAsFactors = FALSE)
}

.frs_test_fixed_names <- function(files, default_to = .frs_test_default_to()) {
  blocks <- lapply(files, .frs_test_blocks)

  # Live connectors, grown to a fixpoint over top-level function definitions
  live <- .frs_test_live_base
  defs <- list()
  for (b in unlist(blocks, recursive = FALSE)) {
    e <- b$expr
    if (is.call(e) && (identical(e[[1]], as.name("<-")) ||
                       identical(e[[1]], as.name("="))) &&
        is.name(e[[2]]) && is.call(e[[3]]) &&
        identical(e[[3]][[1]], as.name("function"))) {
      defs[[as.character(e[[2]])]] <-
        unique(b$pd$text[b$pd$token == "SYMBOL_FUNCTION_CALL"])
    }
  }
  repeat {
    add <- names(defs)[vapply(defs, function(calls) any(calls %in% live),
                              logical(1))]
    add <- setdiff(add, live)
    if (!length(add)) break
    live <- c(live, add)
  }

  out <- list()
  hit <- function(file, line, kind, text) {
    out[[length(out) + 1L]] <<- data.frame(
      file = basename(file), line = line, kind = kind, text = text,
      stringsAsFactors = FALSE)
  }
  for (fi in seq_along(files)) {
    file <- files[fi]
    for (b in blocks[[fi]]) {
      pd <- b$pd; all <- b$all; e <- b$expr
      fc <- pd[pd$token == "SYMBOL_FUNCTION_CALL", ]
      is_live <- any(fc$text %in% live)
      is_test <- is.call(e) && identical(e[[1]], as.name("test_that"))
      s <- pd[pd$token == "STR_CONST", ]
      val <- if (nrow(s)) .frs_test_str(all, s$id) else character()
      if (is_test && !is_live) next
      if (!is_test && !is_live && any(val %in% c("mock", "mock_conn"))) next

      w <- .frs_test_names_working(val)
      if (any(w)) hit(file, s$line1[w], "working", val[w])
      ix <- .frs_test_names_index(val)
      if (any(ix)) hit(file, s$line1[ix], "index", val[ix])

      for (j in seq_len(nrow(fc))) {
        fname <- fc$text[j]
        if (fname != "frs_habitat" && !fname %in% names(default_to)) next
        args <- .frs_test_call_args(all, fc$id[j])
        if (fname == "frs_habitat") {
          for (l in args$id[args$name == "label"]) {
            txt <- utils::getParseText(all, l)
            if (!grepl("frs_test_label(", txt, fixed = TRUE)) {
              hit(file, fc$line1[j], "label", txt)
            }
          }
          if ("wsg" %in% args$name || sum(args$name == "") >= 2L) {
            hit(file, fc$line1[j], "wsg", "frs_habitat() in wsg mode")
          }
        }
        if (fname %in% names(default_to) && !"to" %in% args$name &&
            sum(args$name == "") < default_to[[fname]]) {
          hit(file, fc$line1[j], "to", paste0(fname, "() with its default to"))
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

# Every file the guard reads: tests, helpers and setup, less the files that
# define the per-run helpers and this guard, and the guard's own tests, whose
# snippets are fixed names on purpose.
.frs_test_guard_files <- function(dir = testthat::test_path()) {
  f <- list.files(dir, "^(test|helper|setup)-.*\\.R$", full.names = TRUE)
  f[!basename(f) %in% c("helper-db.R", "helper-test_names.R",
                        "test-test_table_names.R")]
}
