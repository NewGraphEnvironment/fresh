#' Apply Database Migrations Inside a Transaction That Is Rolled Back
#'
#' Applies one or more migration files to `conn` inside a single transaction,
#' and registers the rollback to fire when `env` exits. The effect of a pending
#' migration can then be measured, or tests run against it, without migrating a
#' database other people use.
#'
#' fwapg's migrations carry their own `BEGIN;` and `COMMIT;`. Left in, that
#' `COMMIT;` would commit the trial's transaction, so the pair is stripped and
#' any other transaction control is refused before anything runs. The backstop
#' is that the session must still hold the transaction it opened, with the same
#' id, after each file: a migration that committed and began again would hold
#' another. That check **detects** a commit, after the fact — it cannot
#' prevent one. Preventing is the screen's job, and the screen is what the
#' `files` guarantee above is about.
#'
#' What a rollback cannot undo is covered by neither check, so those calls are
#' refused too: work committed on another connection (`dblink`,
#' `pg_background`, a shell through `COPY ... FROM PROGRAM`), sequence changes
#' (`setval`, `nextval`) and files written on the server (`lo_export`,
#' `pg_file_write`). The scan reaches inside function bodies, because the
#' migration may call what it creates.
#'
#' Those are **token** refusals, not measurements of what a statement would
#' do: a `DEFAULT nextval('s')` clause draws nothing at DDL time and is
#' refused anyway, while a `serial` column — identical semantics — is not
#' named and passes. The list errs toward refusing. Read a migration before
#' trying it; a refusal is a reason to look, not proof of a hazard.
#'
#' Transaction control is looked for only where the server would execute it:
#' comments, string literals and dollar-quoted bodies are blanked first, with
#' line breaks kept, so a plpgsql body's own `BEGIN` / `END;` / `END IF;` is
#' not mistaken for the statement that would end the trial's transaction
#' (fwapg's `db/schema.sql` writes bare `END;` seven times). A region that
#' never closes — an unterminated comment, string or dollar quote — is a
#' refusal rather than a guess, because the scan would otherwise be reading
#' the wrong half of the file. `COMMIT` *inside* a body is left to the server,
#' which answers `invalid transaction termination` while the trial holds an
#' explicit transaction block.
#'
#' @param conn A [DBI::DBIConnection-class] object. Must **not** already be in
#'   a transaction — [DBI::dbBegin()] errors on one that is.
#' @param files Character. Paths to the migration files, applied in the order
#'   given. Every file is read and checked before the first one runs, so a
#'   refusal anywhere leaves the database untouched.
#' @param env An environment. The rollback is deferred to its exit
#'   (`withr::defer()`), so it fires when the calling function returns. A
#'   refusal *after* file `n` has run is undone by that deferred rollback, not
#'   by the refusal itself. The global environment is refused: there its exit
#'   is the end of the session, so the trial would hold its transaction — and
#'   every lock the migration's DDL took — open and unannounced until R
#'   quits. Call it from inside a function, which is also what makes the
#'   rollback observable.
#'
#' @return The connection, invisibly.
#'
#' @family database
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # measure a pending migration's effect, then let the rollback fire
#' measure <- function(migrations) {
#'   conn <- frs_db_conn()
#'   on.exit(DBI::dbDisconnect(conn), add = TRUE)
#'   frs_migration_trial(conn, migrations)
#'   DBI::dbGetQuery(conn, "SELECT count(*) FROM whse_basemapping.fwa_stream_networks_sp")
#' }
#' measure(c("~/Projects/repo/fwapg/db/migrations/202610131654__watershedatmeasure_drop_exbc.sql",
#'           "~/Projects/repo/fwapg/db/migrations/202610240132__indexpoint_tiebreak.sql"))
#' }
frs_migration_trial <- function(conn, files, env = parent.frame()) {
  if (!is.character(files) || !length(files)) {
    stop("frs_migration_trial() needs one or more migration file paths", call. = FALSE)
  }
  if (identical(env, globalenv())) {
    # the global environment exits when R does, so the rollback would be
    # deferred to the end of the session, holding the migration's locks
    stop("frs_migration_trial() will not defer its rollback to the global environment: ",
         "call it from inside a function, so the rollback fires when that function returns",
         call. = FALSE)
  }
  absent <- files[!file.exists(files)]
  if (length(absent)) {
    stop("frs_migration_trial() found no such migration file: ",
         paste(absent, collapse = ", "), call. = FALSE)
  }
  # every file is checked before any of them runs, and a refusal names its own
  bodies <- vapply(files, function(f) {
    tryCatch(.frs_migration_trial_sql(paste(readLines(f, warn = FALSE), collapse = "\n")),
             error = function(e) stop(basename(f), ": ", conditionMessage(e), call. = FALSE))
  }, character(1), USE.NAMES = FALSE)
  DBI::dbBegin(conn)
  withr::defer(DBI::dbRollback(conn), envir = env)
  # A migration's DDL takes AccessExclusiveLock on what it replaces, and the
  # trial holds it for the whole of `env`. Waiting for such a lock behind
  # another session is not something to do silently: SET LOCAL reverts with
  # the transaction, so this does not outlive the trial.
  DBI::dbExecute(conn, "SET LOCAL lock_timeout = '60s'")
  xid <- DBI::dbGetQuery(conn, "SELECT pg_current_xact_id()::text AS x")$x
  for (i in seq_along(files)) {
    # immediate: RPostgres otherwise prepares the statement, and a prepared
    # statement cannot carry the several commands a migration is made of
    DBI::dbExecute(conn, bodies[[i]], immediate = TRUE)
    now <- DBI::dbGetQuery(conn, "SELECT pg_current_xact_id_if_assigned()::text AS x")$x
    if (!identical(now, xid)) {
      stop("after applying ", basename(files[[i]]), " the session no longer holds transaction ",
           xid, ", so the migration may have been committed: check the database", call. = FALSE)
    }
  }
  invisible(conn)
}

# The migration's statements with its own leading `BEGIN;` and trailing
# `COMMIT;` lines blanked (as a pair, and kept as empty lines so a server error
# still names the file's line), refusing any transaction control left after
# that, and any call whose effect a rollback does not undo.
.frs_migration_trial_sql <- function(sql) {
  lines <- strsplit(sql, "\n", fixed = TRUE)[[1]]
  # which lines carry code is decided on the blanked text, so a `/* header */`
  # first line does not hide the migration's own BEGIN; and get the whole file
  # refused for "controlling its own transaction"
  bare <- strsplit(.frs_sql_blank(sql)$calls, "\n", fixed = TRUE)[[1]]
  code <- which(nzchar(trimws(bare)))
  first <- code[1]
  last <- code[length(code)]
  own <- length(code) > 1 && grepl("^\\s*BEGIN\\s*;\\s*$", lines[first], ignore.case = TRUE) &&
    grepl("^\\s*COMMIT\\s*;\\s*$", lines[last], ignore.case = TRUE)
  if (own) {
    lines[c(first, last)] <- ""
  }
  body <- paste(lines, collapse = "\n")
  blanked <- .frs_sql_blank(body)
  if (!nzchar(trimws(blanked$code))) {
    # a truncated or wrong-but-existing file would otherwise report a
    # successful trial of nothing, and the next measurement would be taken
    # against an unmigrated database
    stop("the migration has no statements in it, only comments or whitespace: ",
         "refusing to run it", call. = FALSE)
  }

  # Calls a rollback does not undo. Scanned with comments and string literals
  # blanked (a mention in a comment is not a call) but function bodies kept,
  # because the migration may call what it creates.
  calls <- "(?i)(\\b(dblink\\w*|pg_background\\w*|setval|nextval|lo_export|pg_file_write)\\b"
  calls <- paste0(calls, "|\\b(FROM|TO)\\s+PROGRAM\\b)")
  out <- .frs_sql_scan(blanked$calls, calls)
  if (length(out$at)) {
    # each match with its own line: `at` and `what` are parallel, so taking the
    # first text and every line reads as one call on several lines
    stop("the migration calls ", paste(unique(sprintf("%s (line %d)", out$what, out$at)),
                                       collapse = ", "),
         ", whose effect a rollback does not undo: refusing to run it", call. = FALSE)
  }

  # Transaction control, scanned where the server would execute it: function
  # bodies are blanked too, so a plpgsql `BEGIN` / `END;` is not mistaken for
  # one. Any statement that STARTS with one of these words is transaction
  # control, so the option trailers (`WORK`, `AND CHAIN`, `ISOLATION LEVEL`,
  # …) need no grammar of their own.
  txn <- paste0("(?i)(^|;)\\s*(?<kw>BEGIN|COMMIT|END|ROLLBACK|ABORT|START\\s+TRANSACTION|",
                "PREPARE\\s+TRANSACTION)\\b")
  # the line is the keyword's, not that of the `;` the match starts at
  hit <- .frs_sql_scan(blanked$code, txn, group = "kw")
  if (length(hit$at)) {
    stop("the migration controls its own transaction at line ",
         paste(unique(hit$at), collapse = ", "),
         ", which would end the trial\u2019s: refusing to run it", call. = FALSE)
  }
  body
}


# Every match of `pat` in `text`, as the line each one starts on. A regex that
# gives up has not looked, so a warning is a refusal rather than "no match"
# (`gregexpr()` only warns and reports -1 past PCRE's backtracking limit).
.frs_sql_scan <- function(text, pat, group = NULL) {
  warned <- NULL
  hit <- withCallingHandlers(gregexpr(pat, text, perl = TRUE)[[1]],
                             warning = function(w) {
                               warned <<- conditionMessage(w)
                               invokeRestart("muffleWarning")
                             })
  if (!is.null(warned)) {
    stop("could not scan the migration (", warned, "): refusing to run it", call. = FALSE)
  }
  if (hit[1] < 0) {
    return(list(at = integer(), what = character()))
  }
  from <- if (is.null(group)) as.integer(hit) else attr(hit, "capture.start")[, group]
  # `at` and `what` stay parallel, one entry per match, so a caller cannot
  # cross one match's text with another's line
  list(at = vapply(from, function(i) .frs_sql_line(text, i), 1L),
       what = trimws(substring(text, hit, hit + attr(hit, "match.length") - 1L)))
}


# What PostgreSQL does not execute as top-level SQL, blanked to spaces with
# every line break kept, so a line number still names the file's line. Returns
#   code  - comments, string literals AND dollar-quoted bodies blanked
#   calls - comments and string literals blanked, bodies kept
# A region that never closes is a refusal: the scan would otherwise be reading
# the wrong half of the file as code.
.frs_sql_blank <- function(sql) {
  ch <- strsplit(sql, "", fixed = TRUE)[[1]]
  n <- length(ch)
  # 1 = code, 2 = blank in both, 3 = blank in `code` only (a body)
  kind <- rep(1L, n)
  i <- 1L
  # PostgreSQL's scanner treats every byte >= 0x80 as a letter
  # (ident_start [A-Za-z\200-\377_], ident_cont adding [0-9$]), so a narrower
  # class here reads `t\u00e9$a$` as an identifier followed by a dollar quote where
  # the server's longest match reads ONE identifier — and then blanks a region
  # the server executes. A byte R cannot decode counts as non-ASCII, which
  # errs toward reading it as code.
  wide <- function(x) {
    n <- suppressWarnings(utf8ToInt(x))
    length(n) != 1L || is.na(n) || n > 127L
  }
  ident <- function(x) grepl("^[A-Za-z0-9_$]$", x) || wide(x)
  # a dollar-quote tag follows identifier rules except that `$` ends it
  # (dolq_start / dolq_cont), so the tag class is the same minus `$`
  tag_cont <- function(x) grepl("^[A-Za-z0-9_]$", x) || wide(x)
  while (i <= n) {
    c1 <- ch[[i]]
    c2 <- if (i < n) ch[[i + 1L]] else ""
    if (c1 == "-" && c2 == "-") {
      j <- i
      while (j <= n && ch[[j]] != "\n" && ch[[j]] != "\r") j <- j + 1L
      kind[i:(j - 1L)] <- 2L
      i <- j
    } else if (c1 == "/" && c2 == "*") {
      depth <- 1L
      j <- i + 2L
      while (j <= n && depth > 0L) {
        if (ch[[j]] == "/" && j < n && ch[[j + 1L]] == "*") {
          depth <- depth + 1L
          j <- j + 2L
        } else if (ch[[j]] == "*" && j < n && ch[[j + 1L]] == "/") {
          depth <- depth - 1L
          j <- j + 2L
        } else {
          j <- j + 1L
        }
      }
      if (depth > 0L) {
        stop("the migration has a block comment that never closes, at line ",
             .frs_sql_line(sql, i), ": refusing to run it", call. = FALSE)
      }
      kind[i:(j - 1L)] <- 2L
      i <- j
    } else if (c1 == "\"") {
      # A quoted identifier is code, but inside it PostgreSQL treats ' -- /*
      # and $ as ordinary characters, so it has to be consumed as one token or
      # a `"x--y"` blanks the rest of the line and a `"a's"` pairs the wrong
      # quotes — either of which hides a top-level COMMIT. `""` is a literal ".
      j <- i + 1L
      closed <- FALSE
      while (j <= n) {
        if (ch[[j]] == "\"") {
          if (j < n && ch[[j + 1L]] == "\"") {
            j <- j + 2L
            next
          }
          closed <- TRUE
          j <- j + 1L
          break
        }
        j <- j + 1L
      }
      if (!closed) {
        stop("the migration has a quoted identifier that never closes, at line ",
             .frs_sql_line(sql, i), ": refusing to run it", call. = FALSE)
      }
      # kind stays 1: it is code, it is only skipped over
      i <- j
    } else if (c1 == "'") {
      # E'' takes backslash escapes; a plain literal escapes a quote as ''
      esc <- i > 1L && (ch[[i - 1L]] == "E" || ch[[i - 1L]] == "e") &&
        (i < 3L || !ident(ch[[i - 2L]]))
      j <- i + 1L
      closed <- FALSE
      while (j <= n) {
        if (esc && ch[[j]] == "\\") {
          j <- j + 2L
          next
        }
        if (ch[[j]] == "'") {
          if (j < n && ch[[j + 1L]] == "'") {
            j <- j + 2L
            next
          }
          closed <- TRUE
          j <- j + 1L
          break
        }
        j <- j + 1L
      }
      if (!closed) {
        stop("the migration has a string literal that never closes, at line ",
             .frs_sql_line(sql, i), ": refusing to run it", call. = FALSE)
      }
      kind[i:(j - 1L)] <- 2L
      i <- j
    } else if (c1 == "$" && (i == 1L || !ident(ch[[i - 1L]]))) {
      # a dollar quote opens with $tag$, tag empty or an identifier
      tag <- ""
      j <- i + 1L
      while (j <= n && tag_cont(ch[[j]])) {
        tag <- paste0(tag, ch[[j]])
        j <- j + 1L
      }
      if (j <= n && ch[[j]] == "$" && !grepl("^[0-9]", tag)) {
        open <- paste0("$", tag, "$")
        close <- utils::head(gregexpr(open, substring(sql, j + 1L), fixed = TRUE)[[1]], 1L)
        if (close < 0) {
          stop("the migration has a ", open, " quoted body that never closes, at line ",
               .frs_sql_line(sql, i), ": refusing to run it", call. = FALSE)
        }
        end <- j + close + nchar(open) - 1L
        kind[i:end] <- 3L
        i <- end + 1L
      } else {
        i <- i + 1L
      }
    } else {
      i <- i + 1L
    }
  }
  nl <- ch == "\n"
  mk <- function(drop) {
    out <- ch
    out[drop & !nl] <- " "
    paste(out, collapse = "")
  }
  list(code = mk(kind > 1L), calls = mk(kind == 2L))
}


# The 1-based line that byte offset `i` falls on
.frs_sql_line <- function(sql, i) {
  sum(gregexpr("\n", substr(sql, 1, i), fixed = TRUE)[[1]] > 0) + 1L
}
