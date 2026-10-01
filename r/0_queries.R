# ============================================================
# Project 18 - Database Query Reference
# ============================================================

library(DBI)
library(odbc)
library(dplyr)

# ============================================================
# 1. Database Connection
# ============================================================

connect_db <- function() {

  password <- Sys.getenv("MSSQL_SA_PASSWORD")

  if (identical(password, "")) {
    stop(
      paste(
        "MSSQL_SA_PASSWORD is not set.",
        "Set the environment variable before connecting."
      )
    )
  }

  dbConnect(
    odbc(),
    Driver = "SQL Server",
    Server = "localhost,8888",
    Database = "CompaniesMarketCapDB",
    UID = "sa",
    PWD = password
  )
}

con <- connect_db()


# ============================================================
# 2. Database Information
# ============================================================

# Check SQL Server version
dbGetQuery(
  con,
  "SELECT @@VERSION AS sql_server_version"
)

# Check current database
dbGetQuery(
  con,
  "SELECT DB_NAME() AS current_database"
)


# ============================================================
# 3. Table Information
# ============================================================

# List project tables
dbGetQuery(
  con,
  "
  SELECT
      SCHEMA_NAME(t.schema_id) AS schema_name,
      t.name AS table_name
  FROM sys.tables t
  ORDER BY t.name
  "
)


# ============================================================
# 4. Company Queries
# ============================================================

# Company count
company_count <- dbGetQuery(
  con,
  "
  SELECT
      COUNT(*) AS company_count
  FROM dbo.Company
  "
)

print(company_count)


# Preview companies
company <- dbGetQuery(
  con,
  "
  SELECT TOP 20
      company_id,
      rank,
      name,
      symbol,
      country,
      first_seen,
      last_updated
  FROM dbo.Company
  ORDER BY rank
  "
)

print(company)


# Find a company by symbol
nvda <- dbGetQuery(
  con,
  "
  SELECT
      company_id,
      rank,
      name,
      symbol,
      country,
      first_seen,
      last_updated
  FROM dbo.Company
  WHERE symbol = 'NVDA'
  "
)

print(nvda)


# Check duplicate symbols
duplicate_symbols <- dbGetQuery(
  con,
  "
  SELECT
      symbol,
      COUNT(*) AS duplicate_count
  FROM dbo.Company
  GROUP BY symbol
  HAVING COUNT(*) > 1
  ORDER BY duplicate_count DESC
  "
)

print(duplicate_symbols)


# Check NULL values in Company
company_null_check <- dbGetQuery(
  con,
  "
  SELECT
      COUNT(*) AS total_rows,
      SUM(CASE WHEN rank IS NULL THEN 1 ELSE 0 END) AS null_rank,
      SUM(CASE WHEN name IS NULL THEN 1 ELSE 0 END) AS null_name,
      SUM(CASE WHEN symbol IS NULL THEN 1 ELSE 0 END) AS null_symbol,
      SUM(CASE WHEN last_updated IS NULL THEN 1 ELSE 0 END) AS null_last_updated
  FROM dbo.Company
  "
)

print(company_null_check)


# ============================================================
# 5. Ranking History Queries
# ============================================================

# Ranking history count
ranking_history_count <- dbGetQuery(
  con,
  "
  SELECT
      COUNT(*) AS ranking_history_count
  FROM dbo.CompanyRankingHistory
  "
)

print(ranking_history_count)


# Preview ranking history
ranking_history <- dbGetQuery(
  con,
  "
  SELECT TOP 20
      ranking_history_id,
      rank,
      name,
      symbol,
      country,
      ranking_date
  FROM dbo.CompanyRankingHistory
  ORDER BY ranking_date DESC, rank
  "
)

print(ranking_history)


# Check duplicate symbol + date
ranking_duplicates <- dbGetQuery(
  con,
  "
  SELECT
      symbol,
      ranking_date,
      COUNT(*) AS duplicate_count
  FROM dbo.CompanyRankingHistory
  GROUP BY
      symbol,
      ranking_date
  HAVING COUNT(*) > 1
  ORDER BY duplicate_count DESC
  "
)

print(ranking_duplicates)


# Check NULL values in Ranking History
ranking_null_check <- dbGetQuery(
  con,
  "
  SELECT
      COUNT(*) AS total_rows,
      SUM(CASE WHEN rank IS NULL THEN 1 ELSE 0 END) AS null_rank,
      SUM(CASE WHEN name IS NULL THEN 1 ELSE 0 END) AS null_name,
      SUM(CASE WHEN symbol IS NULL THEN 1 ELSE 0 END) AS null_symbol,
      SUM(CASE WHEN ranking_date IS NULL THEN 1 ELSE 0 END) AS null_date
  FROM dbo.CompanyRankingHistory
  "
)

print(ranking_null_check)


# Ranking coverage by date
ranking_coverage <- dbGetQuery(
  con,
  "
  SELECT
      ranking_date,
      COUNT(*) AS company_count,
      MIN(rank) AS min_rank,
      MAX(rank) AS max_rank
  FROM dbo.CompanyRankingHistory
  GROUP BY ranking_date
  ORDER BY ranking_date
  "
)

print(ranking_coverage)


# Check missing company symbols
missing_company_symbols <- dbGetQuery(
  con,
  "
  SELECT DISTINCT
      rh.symbol
  FROM dbo.CompanyRankingHistory rh
  LEFT JOIN dbo.Company c
      ON c.symbol = rh.symbol
  WHERE c.symbol IS NULL
  ORDER BY rh.symbol
  "
)

print(missing_company_symbols)


# ============================================================
# 6. Market Price Summary
# ============================================================

market_summary <- dbGetQuery(
  con,
  "
  SELECT
      COUNT(*) AS total_rows,
      COUNT(DISTINCT company_id) AS companies_with_price_data,
      MIN(price_date) AS min_date,
      MAX(price_date) AS max_date
  FROM dbo.MarketPrice
  "
)

print(market_summary)


# ============================================================
# 7. Market Price Preview
# ============================================================

# Latest prices for NVDA
nvda_price <- dbGetQuery(
  con,
  "
  SELECT TOP 20
      company_id,
      symbol,
      price_date,
      [open],
      [high],
      [low],
      [close],
      volume,
      adjusted
  FROM dbo.MarketPrice
  WHERE symbol = 'NVDA'
  ORDER BY price_date DESC
  "
)

print(nvda_price)


# ============================================================
# 8. Market Price Data Quality
# ============================================================

# Check required NULL values
market_null_check <- dbGetQuery(
  con,
  "
  SELECT
      COUNT(*) AS invalid_rows
  FROM dbo.MarketPrice
  WHERE
      company_id IS NULL
      OR symbol IS NULL
      OR price_date IS NULL
      OR [open] IS NULL
      OR [high] IS NULL
      OR [low] IS NULL
      OR [close] IS NULL
  "
)

print(market_null_check)


# Check duplicate business keys
market_duplicates <- dbGetQuery(
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

print(market_duplicates)


# Check orphan company IDs
orphan_company_rows <- dbGetQuery(
  con,
  "
  SELECT
      COUNT(*) AS orphan_rows
  FROM dbo.MarketPrice mp
  LEFT JOIN dbo.Company c
      ON mp.company_id = c.company_id
  WHERE c.company_id IS NULL
  "
)

print(orphan_company_rows)


# Check invalid OHLC relationships
invalid_ohlc <- dbGetQuery(
  con,
  "
  SELECT
      COUNT(*) AS invalid_ohlc_rows
  FROM dbo.MarketPrice
  WHERE
      [high] < [low]
      OR [open] < [low]
      OR [open] > [high]
      OR [close] < [low]
      OR [close] > [high]
  "
)

print(invalid_ohlc)


# ============================================================
# 9. Market Price Coverage
# ============================================================

# Coverage by company
price_coverage <- dbGetQuery(
  con,
  "
  SELECT
      company_id,
      symbol,
      COUNT(*) AS row_count,
      MIN(price_date) AS min_date,
      MAX(price_date) AS max_date
  FROM dbo.MarketPrice
  GROUP BY
      company_id,
      symbol
  ORDER BY company_id
  "
)

print(price_coverage)


# Latest price date by company
latest_data <- dbGetQuery(
  con,
  "
  SELECT
      company_id,
      symbol,
      MAX(price_date) AS latest_price_date
  FROM dbo.MarketPrice
  GROUP BY
      company_id,
      symbol
  ORDER BY company_id
  "
)

print(latest_data)


# Find companies without market price data
companies_without_price <- dbGetQuery(
  con,
  "
  SELECT
      c.company_id,
      c.symbol,
      c.name
  FROM dbo.Company c
  LEFT JOIN (
      SELECT DISTINCT company_id
      FROM dbo.MarketPrice
  ) mp
      ON c.company_id = mp.company_id
  WHERE mp.company_id IS NULL
  ORDER BY c.company_id
  "
)

print(companies_without_price)


# ============================================================
# 10. Database-Level Validation Summary
# ============================================================

validation_summary <- dbGetQuery(
  con,
  "
  SELECT
      (SELECT COUNT(*) FROM dbo.Company) AS company_count,

      (SELECT COUNT(*)
       FROM dbo.CompanyRankingHistory) AS ranking_history_rows,

      (SELECT COUNT(*)
       FROM dbo.MarketPrice) AS market_price_rows,

      (SELECT COUNT(DISTINCT company_id)
       FROM dbo.MarketPrice) AS companies_with_price_data,

      (SELECT MIN(price_date)
       FROM dbo.MarketPrice) AS min_price_date,

      (SELECT MAX(price_date)
       FROM dbo.MarketPrice) AS max_price_date
  "
)

print(validation_summary)


# ============================================================
# 11. Disconnect
# ============================================================

dbDisconnect(con)
print("Database connection closed.")