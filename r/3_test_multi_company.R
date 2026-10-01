# ============================================================
# TEST #6 - MULTI-COMPANY UPSERT
# ============================================================

library(DBI)
library(odbc)


# ============================================================
# 1. Database Connection
# ============================================================

# Read SQL Server password from environment
password <- Sys.getenv("MSSQL_SA_PASSWORD")

if (identical(password, "")) {
  stop(
    "MSSQL_SA_PASSWORD is not set.",
    call. = FALSE
  )
}

# Connect to SQL Server
con <- dbConnect(
  odbc(),
  Driver = "SQL Server",
  Server = "localhost,8888",
  Database = "CompaniesMarketCapDB",
  UID = "sa",
  PWD = password
)


# ============================================================
# 2. Test Setup
# ============================================================

cat("\n========================================\n")
cat("TEST #6 - MULTI-COMPANY UPSERT\n")
cat("========================================\n")


# ------------------------------------------------------------
# 2.1 Get two companies
# ------------------------------------------------------------

companies <- dbGetQuery(
  con,
  "
  SELECT TOP 2
      company_id,
      symbol,
      name
  FROM dbo.Company
  ORDER BY company_id
  "
)

if (nrow(companies) < 2) {
  stop("FAIL: At least two companies are required.")
}

print(companies)


company_1 <- companies$company_id[[1]]
company_2 <- companies$company_id[[2]]

symbol_1 <- companies$symbol[[1]]
symbol_2 <- companies$symbol[[2]]


# ============================================================
# 3. Test Date
# ============================================================

test_date <- "2099-12-31"

cat("\nTest date:", test_date, "\n")

cat(
  "Company 1:",
  company_1,
  symbol_1,
  "\n"
)

cat(
  "Company 2:",
  company_2,
  symbol_2,
  "\n"
)


# ============================================================
# 4. Start Transaction
# ============================================================

cat("\nStarting transaction...\n")

dbBegin(con)

tryCatch({

  # ----------------------------------------------------------
  # 4.1 Insert same date for Company 1
  # ----------------------------------------------------------

  cat("\nInserting Company 1...\n")

  dbExecute(
    con,
    sprintf(
      "
      INSERT INTO dbo.MarketPrice (
          company_id,
          symbol,
          price_date,
          [open],
          [high],
          [low],
          [close],
          volume,
          adjusted
      )
      VALUES (
          %d,
          '%s',
          '%s',
          100,
          110,
          90,
          105,
          1000,
          105
      )
      ",
      company_1,
      symbol_1,
      test_date
    )
  )

  cat("Company 1 insert: PASS\n")


  # ----------------------------------------------------------
  # 4.2 Insert same date for Company 2
  # ----------------------------------------------------------

  cat("\nInserting Company 2...\n")

  dbExecute(
    con,
    sprintf(
      "
      INSERT INTO dbo.MarketPrice (
          company_id,
          symbol,
          price_date,
          [open],
          [high],
          [low],
          [close],
          volume,
          adjusted
      )
      VALUES (
          %d,
          '%s',
          '%s',
          200,
          220,
          180,
          210,
          2000,
          210
      )
      ",
      company_2,
      symbol_2,
      test_date
    )
  )

  cat("Company 2 insert: PASS\n")


  # ==========================================================
  # 5. Validate Same Date
  # ==========================================================

  result <- dbGetQuery(
    con,
    sprintf(
      "
      SELECT
          company_id,
          symbol,
          price_date,
          [close]
      FROM dbo.MarketPrice
      WHERE price_date = '%s'
        AND company_id IN (%d, %d)
      ORDER BY company_id
      ",
      test_date,
      company_1,
      company_2
    )
  )

  cat("\n========================================\n")
  cat("VALIDATING MULTI-COMPANY DATA\n")
  cat("========================================\n")

  print(result)


  # ----------------------------------------------------------
  # 5.1 Validate two rows exist
  # ----------------------------------------------------------

  if (nrow(result) != 2) {
    stop(
      paste(
        "FAIL: Expected 2 rows, found",
        nrow(result)
      )
    )
  }

  cat("Same-date multi-company insert: PASS\n")


  # ----------------------------------------------------------
  # 5.2 Validate company IDs are different
  # ----------------------------------------------------------

  if (length(unique(result$company_id)) != 2) {
    stop("FAIL: Company IDs are not unique.")
  }

  cat("Different company IDs: PASS\n")


  # ==========================================================
  # 6. Test Duplicate Protection
  # ==========================================================

  cat("\nTesting duplicate key protection...\n")

  duplicate_result <- tryCatch({

    dbExecute(
      con,
      sprintf(
        "
        INSERT INTO dbo.MarketPrice (
            company_id,
            symbol,
            price_date,
            [open],
            [high],
            [low],
            [close],
            volume,
            adjusted
        )
        VALUES (
            %d,
            '%s',
            '%s',
            999,
            999,
            999,
            999,
            999,
            999
        )
        ",
        company_1,
        symbol_1,
        test_date
      )
    )

    FALSE

  }, error = function(e) {

    TRUE

  })


  if (!duplicate_result) {
    stop(
      "FAIL: Duplicate company_id + price_date was accepted."
    )
  }

  cat("Duplicate protection: PASS\n")


  # ==========================================================
  # 7. Rollback Test Data
  # ==========================================================

  cat("\nRolling back test data...\n")

  dbRollback(con)

  cat("Test data rolled back.\n")


}, error = function(e) {

  cat("\nUnexpected error:\n")
  cat(conditionMessage(e), "\n")

  cat("\nRolling back transaction...\n")

  dbRollback(con)

  stop("TEST #6 FAILED.")


})


# ============================================================
# 8. Validate Cleanup
# ============================================================

cat("\n========================================\n")
cat("VALIDATING CLEANUP\n")
cat("========================================\n")


cleanup_check <- dbGetQuery(
  con,
  sprintf(
    "
    SELECT
        COUNT(*) AS row_count
    FROM dbo.MarketPrice
    WHERE price_date = '%s'
      AND company_id IN (%d, %d)
    ",
    test_date,
    company_1,
    company_2
  )
)


cat(
  "Test rows remaining:",
  cleanup_check$row_count[[1]],
  "\n"
)


if (cleanup_check$row_count[[1]] != 0) {

  stop("FAIL: Test data was not rolled back.")

} else {

  cat("Cleanup validation: PASS\n")

}


# ============================================================
# 9. Final Result
# ============================================================

cat("\n========================================\n")
cat("TEST #6 RESULT\n")
cat("========================================\n")

cat("Multi-company same-date insert: PASS\n")
cat("Duplicate key protection: PASS\n")
cat("Transaction cleanup: PASS\n")
cat("Test #6: PASS\n")


# ============================================================
# 10. Disconnect
# ============================================================

dbDisconnect(con)

cat("\nDatabase connection closed.\n")