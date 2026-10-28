test_that("a migration's own BEGIN; and COMMIT; are stripped and its plpgsql kept", {
  migration <- c(
    "BEGIN;", "", "-- a comment", "DROP FUNCTION f(integer);",
    "CREATE FUNCTION f(x integer) RETURNS integer LANGUAGE plpgsql AS $$",
    "BEGIN", "  IF x > 0 THEN", "    RETURN x;", "  END IF;", "  RETURN 0;", "END", "$$;",
    "", "COMMIT;", ""
  )
  sql <- paste(migration, collapse = "\n")
  body <- fresh:::.frs_migration_trial_sql(sql)
  lines <- strsplit(body, "\n", fixed = TRUE)[[1]]
  expect_false(any(grepl("^(BEGIN|COMMIT);", lines)))
  expect_true(all(c("BEGIN", "END", "  END IF;", "DROP FUNCTION f(integer);") %in% lines))
  # line numbers survive the strip, so a server error names the file's line
  expect_identical(which(lines == "DROP FUNCTION f(integer);"), 4L)
})

test_that("a migration with no transaction of its own passes through", {
  expect_identical(fresh:::.frs_migration_trial_sql("SELECT 1;\nSELECT 2;"), "SELECT 1;\nSELECT 2;")
})

test_that("transaction control left inside the migration is refused, with its line", {
  refuse <- function(x) expect_error(fresh:::.frs_migration_trial_sql(x), "controls its own transaction")
  refuse("BEGIN;\nSELECT 1;\nCOMMIT;\nSELECT 2;\nCOMMIT;")
  refuse("BEGIN;\nSELECT 1;\ncommit ;\nSELECT 2;\nCOMMIT;")
  refuse("SELECT 1;\nROLLBACK;\nSELECT 2;")
  refuse("SELECT 1;\nEND;\nSELECT 2;")
  refuse("SELECT 1; COMMIT;\nSELECT 2;")
  refuse("SELECT 1;\nCOMMIT AND CHAIN;")
  refuse("SELECT 1;\nSTART TRANSACTION ISOLATION LEVEL SERIALIZABLE;")
  refuse("SELECT 1;\nBEGIN WORK;\nSELECT 2;")
  refuse("SELECT 1;\nPREPARE TRANSACTION 'x';")
  # the server allows a line break or a comment around the keyword
  refuse("SELECT 1;\nCOMMIT\n;")
  refuse("SELECT 1;\nCOMMIT -- c\n;")
  refuse("SELECT 1;\n/* c */ COMMIT;")
  refuse("SELECT 1;\nCOMMIT/* c */;")
  refuse("SELECT 1; /* a\nb */\nROLLBACK;")
  # and between a command's words, and a last statement needs no semicolon
  refuse("SELECT 1;\nCOMMIT\nAND CHAIN;")
  refuse("SELECT 1;\nEND\nTRANSACTION;")
  refuse("SELECT 1;\nROLLBACK /* x */ WORK;")
  refuse("SELECT 1;\nCOMMIT -- c\nWORK;")
  refuse("SELECT 1;\nCOMMIT")
  refuse("SELECT 1;\nCOMMIT\n\n")
  # a long run of comments before one cannot hide it by exhausting the regex
  refuse(paste0("SELECT 1;\n-- ", strrep("-", 40), "\nSELECT 2;\nCOMMIT;"))
  refuse(paste0("SELECT 1;\n", strrep("-", 400), "\nSELECT 2;\nCOMMIT;"))
  refuse(paste0("SELECT 1;\n", strrep("/* x */\n", 20), "COMMIT;"))
  refuse("SELECT 1;\nCOMMIT /* a /* b */ c */;")
  refuse("SELECT 1; -- c\rCOMMIT;")
  # a COMMIT; with no BEGIN; before it is not the migration's own pair
  refuse("SELECT 1;\nCOMMIT;")
  expect_error(fresh:::.frs_migration_trial_sql("BEGIN;\nSELECT 1;\nCOMMIT;\nSELECT 2;\nCOMMIT;"),
               "at line 3\\b")
  expect_error(fresh:::.frs_migration_trial_sql("SELECT 1; /* a\nb */\nROLLBACK;"), "at line 3\\b")
})

test_that("calls whose effect a rollback does not undo are refused", {
  refuse <- function(x) expect_error(fresh:::.frs_migration_trial_sql(x), "a rollback does not undo")
  refuse("SELECT dblink_exec('host=x', 'DROP TABLE t');")
  refuse("COPY t FROM PROGRAM 'psql -c commit';")
  refuse("COPY t TO PROGRAM 'cat > /tmp/x';")
  refuse("SELECT setval('s', 1);")
  # nextval advances a sequence, which a rollback does not undo either
  refuse("SELECT nextval('s');")
  # the list names tokens, not effects: a DEFAULT clause draws nothing at DDL
  # time and is refused anyway, while `serial` — identical semantics — is not
  # named and passes. Pinned so the asymmetry is deliberate, not a surprise.
  refuse("CREATE TABLE t (id integer DEFAULT nextval('s'));")
  expect_identical(fresh:::.frs_migration_trial_sql("CREATE TABLE t (id serial);"),
                   "CREATE TABLE t (id serial);")
  refuse("SELECT pg_background_launch('VACUUM');")
  refuse("SELECT lo_export(1, '/tmp/x');")
  # and the scan reaches inside a function body: the migration may call it
  refuse(paste("CREATE FUNCTION f() RETURNS void LANGUAGE plpgsql AS $$",
               "BEGIN", "  PERFORM dblink_exec('host=x', 'DROP TABLE t');",
               "END", "$$;", sep = "\n"))
  # a mention in a comment or a string is not a call
  pass <- function(x) expect_identical(fresh:::.frs_migration_trial_sql(x), x)
  pass("-- this program loads the data\nSELECT 1;")
  pass("SELECT 1; -- setval() is deliberately not used here")
  pass("COMMENT ON TABLE t IS 'run this program to reload';")
})

test_that("a quoted identifier is code, not a place to hide a COMMIT", {
  # inside "..." PostgreSQL treats ' -- /* and $ as ordinary characters, so a
  # lexer without that token class blanks real SQL and lets a top-level COMMIT
  # through — the one failure direction that matters here
  refuse <- function(x) expect_error(fresh:::.frs_migration_trial_sql(x),
                                     "controls its own transaction")
  refuse('ALTER TABLE t RENAME TO "x--y"; COMMIT;')
  refuse(paste("COMMENT ON COLUMN t.\"a's\" IS 'x';", "COMMIT;",
               "COMMENT ON COLUMN t.\"b's\" IS 'z';", sep = "\n"))
  refuse('CREATE TABLE "t/*" (x integer); COMMIT;')
  refuse('CREATE TABLE "t$$" (x integer); COMMIT;')
  # a "" is a literal quote inside the identifier, not the end of it
  refuse('CREATE TABLE "a""--b" (x integer); COMMIT;')
  # and a quoted identifier on its own is ordinary code
  pass <- function(x) expect_identical(fresh:::.frs_migration_trial_sql(x), x)
  pass('CREATE TABLE "x--y" (x integer);')
  pass('COMMENT ON COLUMN t."a\'s" IS \'x\';')
  expect_error(fresh:::.frs_migration_trial_sql('CREATE TABLE "open (x integer);'),
               "quoted identifier that never closes")
})

test_that("a non-ASCII letter before a dollar quote is part of the identifier", {
  # PostgreSQL's ident_start is [A-Za-z\200-\377_]: every byte >= 0x80 is a
  # letter, so `t\u00e9$a$` is ONE identifier under its longest match. A lexer
  # whose identifier class is ASCII-only reads it as an identifier followed by
  # a dollar quote, blanks everything to the next `$a$`, and lets whatever is
  # in between — a COMMIT — reach the server. This is the one construct in the
  # round-3 enumeration that went fail-open.
  hidden <- paste(
    sprintf("CREATE TABLE public.t%s$a$ (x integer);", "\u00e9"),
    "CREATE TABLE public.frs_victim (x integer);",
    "COMMIT;",
    sprintf("SELECT 1 AS t%s$a$;", "\u00e9"), sep = "\n")
  expect_error(fresh:::.frs_migration_trial_sql(hidden), "controls its own transaction")
  # and a tag may itself carry a non-ASCII letter, which is then a real body
  pass <- function(x) expect_identical(fresh:::.frs_migration_trial_sql(x), x)
  pass(paste(sprintf("CREATE FUNCTION f() RETURNS void LANGUAGE plpgsql AS $t%s$", "\u00e9"),
             "BEGIN", "END", sprintf("$t%s$;", "\u00e9"), sep = "\n"))
  # `$` continues an identifier too, so `a$b$` is one token, not a quote
  pass("SELECT 1 AS a$b$;")
})

test_that("a comment around the migration's own pair is not a refusal", {
  # the own-BEGIN;/COMMIT; pair is found on the blanked text, so a block
  # comment at either end does not hide it and get the file refused
  body <- paste("/* fwapg#41 */", "BEGIN;", "SELECT 1;", "COMMIT;", "/* done */",
                sep = "\n")
  out <- fresh:::.frs_migration_trial_sql(body)
  lines <- strsplit(out, "\n", fixed = TRUE)[[1]]
  expect_identical(lines[[2]], "")
  expect_identical(lines[[4]], "")
  expect_identical(lines[[3]], "SELECT 1;")
})

test_that("each rollback-unsafe call is reported with its own line", {
  expect_error(
    fresh:::.frs_migration_trial_sql("SELECT 1;\nSELECT setval('s', 1);\nSELECT 2;\nSELECT dblink_exec('h', 'x');"),
    "setval \\(line 2\\).*dblink_exec \\(line 4\\)")
})

test_that("a plpgsql body's own BEGIN and END; are not transaction control", {
  # fwapg's db/schema.sql writes bare `END;` seven times, so refusing it would
  # refuse the corpus this function exists to trial
  body <- paste(
    "CREATE OR REPLACE FUNCTION f(x integer) RETURNS integer LANGUAGE plpgsql AS $$",
    "DECLARE y integer;",
    "BEGIN",
    "  IF x > 0 THEN",
    "    y := x;",
    "  END IF;",
    "  BEGIN",
    "    y := y / 0;",
    "  EXCEPTION WHEN division_by_zero THEN",
    "    y := 0;",
    "  END;",
    "  RETURN y;",
    "END;",
    "$$;", sep = "\n")
  expect_identical(fresh:::.frs_migration_trial_sql(body), body)
  # the same words at the top level still are
  expect_error(fresh:::.frs_migration_trial_sql("SELECT 1;\nEND;"),
               "controls its own transaction")
  # and so is one in a body that is closed before it
  expect_error(fresh:::.frs_migration_trial_sql(
    paste("CREATE FUNCTION f() RETURNS void LANGUAGE plpgsql AS $$", "BEGIN", "END",
          "$$;", "COMMIT;", sep = "\n")),
    "at line 5\\b")
})

test_that("transaction control hidden in a string or a dollar body is not a false refusal", {
  pass <- function(x) expect_identical(fresh:::.frs_migration_trial_sql(x), x)
  # a COMMIT the server never executes as a statement
  pass("SELECT 'COMMIT;';")
  pass("COMMENT ON TABLE t IS 'BEGIN; COMMIT;';")
  pass("SELECT E'a\\'b; COMMIT;';")
  # inside a body the server itself answers `invalid transaction termination`
  # while the trial holds an explicit transaction block, so it is left to it
  pass(paste("CREATE PROCEDURE p() LANGUAGE plpgsql AS $_$", "BEGIN", "  COMMIT;", "END",
             "$_$;", sep = "\n"))
})

test_that("a region that never closes is refused rather than guessed at", {
  expect_error(fresh:::.frs_migration_trial_sql("SELECT 1;\n/* open\nCOMMIT;"),
               "block comment that never closes.*line 2")
  expect_error(fresh:::.frs_migration_trial_sql("SELECT 'open;\nCOMMIT;"),
               "string literal that never closes.*line 1")
  expect_error(fresh:::.frs_migration_trial_sql("CREATE FUNCTION f() AS $$\nCOMMIT;"),
               "\\$\\$ quoted body that never closes.*line 1")
})

test_that("a trial migrates its own session only, and its rollback undoes it", {
  conn <- local_fwapg()
  other <- local_fwapg()
  tbl <- paste0("frs_trial_", paste(sample(letters, 12, TRUE), collapse = ""))
  f <- withr::local_tempfile(fileext = ".sql")
  writeLines(c("BEGIN;", sprintf("CREATE TABLE public.%s (x integer);", tbl),
               sprintf("INSERT INTO public.%s VALUES (1);", tbl), "COMMIT;"), f)
  exists_in <- function(con) {
    !is.na(DBI::dbGetQuery(con, sprintf("SELECT to_regclass('public.%s')::text AS r", tbl))$r)
  }
  local({
    frs_migration_trial(conn, f)
    expect_true(exists_in(conn))
    expect_false(exists_in(other))
  })
  expect_false(exists_in(conn))
  expect_false(exists_in(other))
})

test_that("several migrations are applied in one transaction, in the order given", {
  conn <- local_fwapg()
  tbl <- paste0("frs_trial_", paste(sample(letters, 12, TRUE), collapse = ""))
  first <- withr::local_tempfile(fileext = ".sql")
  second <- withr::local_tempfile(fileext = ".sql")
  writeLines(c("BEGIN;", sprintf("CREATE TABLE public.%s (x integer);", tbl), "COMMIT;"), first)
  writeLines(c("BEGIN;", sprintf("ALTER TABLE public.%s ADD COLUMN y integer;", tbl), "COMMIT;"),
             second)
  local({
    frs_migration_trial(conn, c(first, second))
    # the second file could only have run after the first
    expect_identical(
      DBI::dbGetQuery(conn, sprintf(
        "SELECT attname FROM pg_attribute WHERE attrelid = 'public.%s'::regclass AND attnum > 0
         ORDER BY attnum", tbl))$attname,
      c("x", "y")
    )
  })
  expect_true(is.na(DBI::dbGetQuery(conn, sprintf(
    "SELECT to_regclass('public.%s')::text AS r", tbl))$r))
})

test_that("a migration that commits midway is refused before anything runs", {
  conn <- local_fwapg()
  tbl <- paste0("frs_trial_", paste(sample(letters, 12, TRUE), collapse = ""))
  f <- withr::local_tempfile(fileext = ".sql")
  writeLines(c("BEGIN;", sprintf("CREATE TABLE public.%s (x integer);", tbl), "COMMIT;",
               "SELECT 1;", "COMMIT;"), f)
  expect_error(frs_migration_trial(conn, f), "controls its own transaction")
  expect_true(is.na(DBI::dbGetQuery(conn, sprintf(
    "SELECT to_regclass('public.%s')::text AS r", tbl))$r))
})

test_that("a refusal in any file stops the whole run before the first one applies", {
  conn <- local_fwapg()
  tbl <- paste0("frs_trial_", paste(sample(letters, 12, TRUE), collapse = ""))
  good <- withr::local_tempfile(fileext = ".sql")
  bad <- withr::local_tempfile(fileext = ".sql")
  writeLines(c("BEGIN;", sprintf("CREATE TABLE public.%s (x integer);", tbl), "COMMIT;"), good)
  writeLines(c("BEGIN;", "SELECT 1;", "COMMIT;", "SELECT 2;", "COMMIT;"), bad)
  expect_error(frs_migration_trial(conn, c(good, bad)), "controls its own transaction")
  expect_true(is.na(DBI::dbGetQuery(conn, sprintf(
    "SELECT to_regclass('public.%s')::text AS r", tbl))$r))
  # no transaction was left open: dbBegin() errors on a connection already in one
  expect_silent(DBI::dbBegin(conn))
  DBI::dbRollback(conn)
})

test_that("a missing migration file is named", {
  conn <- local_fwapg()
  expect_error(frs_migration_trial(conn, "/nonexistent/202610240132__nope.sql"),
               "202610240132__nope\\.sql")
})

test_that("a file with no statements in it is refused, not reported as a success", {
  conn <- local_fwapg()
  f <- withr::local_tempfile(fileext = ".sql")
  writeLines(c("-- truncated before anything landed", ""), f)
  expect_error(frs_migration_trial(conn, f), "has no statements in it")
})

test_that("the rollback is not deferred to the end of the session", {
  conn <- local_fwapg()
  f <- withr::local_tempfile(fileext = ".sql")
  writeLines("SELECT 1;", f)
  # globalenv() exits when R does, so the trial would hold its transaction —
  # and every lock the migration's DDL took — open and unannounced until R quits
  expect_error(frs_migration_trial(conn, f, env = globalenv()),
               "will not defer its rollback to the global environment")
  # and nothing was begun before that refusal
  expect_silent(DBI::dbBegin(conn))
  DBI::dbRollback(conn)
})

test_that("the real fwapg migrations pass the screen and apply as one transaction", {
  conn <- local_fwapg()
  files <- Sys.getenv("FRESH_FWAPG_TRIAL")
  skip_if(!nzchar(files), "FRESH_FWAPG_TRIAL names no migration files")
  files <- strsplit(files, .Platform$path.sep, fixed = TRUE)[[1]]
  skip_if_not(all(file.exists(files)), "FRESH_FWAPG_TRIAL names a file that is not there")
  args <- function() {
    DBI::dbGetQuery(conn, "SELECT pg_get_function_arguments(p.oid) AS a FROM pg_proc p
                             JOIN pg_namespace n ON n.oid = p.pronamespace
                           WHERE n.nspname = 'whse_basemapping' AND p.proname = 'fwa_indexpoint'")$a
  }
  before <- args()
  skip_if(any(grepl("include_disconnected", before)),
          "this database already has the fwa_indexpoint rework")
  local({
    frs_migration_trial(conn, files)
    expect_true(any(grepl("include_disconnected", args())))
  })
  expect_identical(args(), before)
})
