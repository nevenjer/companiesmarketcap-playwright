# ============================================================
# 0. Setup
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
# 2. Baseline
# ============================================================

cat("\n========================================\n")
cat("TEST #5 - TRANSACTION ROLLBACK\n")
cat("========================================\n")

baseline <- dbGetQuery(
  con,
  "
  SELECT
      COUNT(*) AS row_count
  FROM dbo.MarketPrice
  WHERE company_id = 1
  "
)

cat(
  "Baseline rows:",
  baseline$row_count[[1]],
  "\n"
)


# ============================================================
# 3. Start Transaction
# ============================================================

cat("\nStarting transaction...\n")

dbBegin(con)

tryCatch({

  # ----------------------------------------------------------
  # 3.1 Update existing row
  # ----------------------------------------------------------

  cat("\nUpdating existing row...\n")

  dbExecute(
    con,
    "
    UPDATE dbo.MarketPrice
    SET [close] = [close] + 1
    WHERE company_id = 1
      AND price_date = '2026-09-30'
    "
  )

  cat("Update completed.\n")


  # ----------------------------------------------------------
  # 3.2 Force an error
  # ----------------------------------------------------------

  cat("\nForcing SQL error...\n")

  dbExecute(
    con,
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
        1,
        'NVDA',
        '2026-09-30',
        1,
        1,
        1,
        1,
        1,
        1
    )
    "
  )


  # ----------------------------------------------------------
  # 3.3 Commit
  # ----------------------------------------------------------

  dbCommit(con)

  cat("\nERROR: Transaction should have failed.\n")

}, error = function(e) {

  # Rollback after failure
  cat("\nExpected SQL error detected.\n")
  cat("Rolling back transaction...\n")

  dbRollback(con)

  cat("Transaction rolled back.\n")
})


# ============================================================
# 4. Validate Rollback
# ============================================================

cat("\n========================================\n")
cat("VALIDATING ROLLBACK\n")
cat("========================================\n")


# ------------------------------------------------------------
# 4.1 Check row count
# ------------------------------------------------------------

after_count <- dbGetQuery(
  con,
  "
  SELECT
      COUNT(*) AS row_count
  FROM dbo.MarketPrice
  WHERE company_id = 1
  "
)

cat(
  "Rows after rollback:",
  after_count$row_count[[1]],
  "\n"
)

if (
  after_count$row_count[[1]] !=
  baseline$row_count[[1]]
) {

  stop("FAIL: Row count changed after rollback.")

} else {

  cat("Row count rollback: PASS\n")
}


# ------------------------------------------------------------
# 4.2 Check price
# ------------------------------------------------------------

price_check <- dbGetQuery(
  con,
  "
  SELECT
      [close]
  FROM dbo.MarketPrice
  WHERE company_id = 1
    AND price_date = '2026-09-30'
  "
)

print(price_check)


# ------------------------------------------------------------
# 4.3 Check duplicate
# ------------------------------------------------------------

duplicate_check <- dbGetQuery(
  con,
  "
  SELECT
      company_id,
      price_date,
      COUNT(*) AS row_count
  FROM dbo.MarketPrice
  GROUP BY
      company_id,
      price_date
  HAVING COUNT(*) > 1
  "
)

if (nrow(duplicate_check) > 0) {

  print(duplicate_check)

  stop("FAIL: Duplicate detected after rollback.")

} else {

  cat("Duplicate validation: PASS\n")
}


# ============================================================
# 5. Final Result
# ============================================================

cat("\n========================================\n")
cat("TEST #5 RESULT\n")
cat("========================================\n")

cat("Transaction rollback: PASS\n")
cat("Database remained consistent.\n")


# ============================================================
# 6. Disconnect
# ============================================================

dbDisconnect(con)

cat("\nDatabase connection closed.\n")