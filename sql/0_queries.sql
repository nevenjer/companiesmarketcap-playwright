USE CompaniesMarketCapDB;
GO

/* ============================================================
   Project 18 - Database Query Reference
   ============================================================ */


/* ============================================================
   1. Database Information
   ============================================================ */

SELECT
    DB_NAME() AS current_database;
GO

SELECT
    @@VERSION AS sql_server_version;
GO


/* ============================================================
   2. Project Tables
   ============================================================ */

SELECT
    SCHEMA_NAME(t.schema_id) AS schema_name,
    t.name AS table_name
FROM sys.tables t
ORDER BY t.name;
GO


/* ============================================================
   3. Company
   ============================================================ */

-- Company count
SELECT
    COUNT(*) AS company_count
FROM dbo.Company;
GO


-- Preview companies
SELECT TOP 20
    company_id,
    rank,
    name,
    symbol,
    country,
    first_seen,
    last_updated
FROM dbo.Company
ORDER BY rank;
GO


-- Check duplicate symbols
SELECT
    symbol,
    COUNT(*) AS duplicate_count
FROM dbo.Company
GROUP BY symbol
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;
GO


-- Check NULL values
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN rank IS NULL THEN 1 ELSE 0 END) AS null_rank,
    SUM(CASE WHEN name IS NULL THEN 1 ELSE 0 END) AS null_name,
    SUM(CASE WHEN symbol IS NULL THEN 1 ELSE 0 END) AS null_symbol,
    SUM(CASE WHEN last_updated IS NULL THEN 1 ELSE 0 END) AS null_last_updated
FROM dbo.Company;
GO


/* ============================================================
   4. Company Ranking History
   ============================================================ */

-- Row count
SELECT
    COUNT(*) AS ranking_history_count
FROM dbo.CompanyRankingHistory;
GO


-- Preview latest ranking history
SELECT TOP 20
    ranking_history_id,
    rank,
    name,
    symbol,
    country,
    ranking_date
FROM dbo.CompanyRankingHistory
ORDER BY ranking_date DESC, rank;
GO


-- Check duplicate symbol + date
SELECT
    symbol,
    ranking_date,
    COUNT(*) AS duplicate_count
FROM dbo.CompanyRankingHistory
GROUP BY
    symbol,
    ranking_date
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;
GO


-- Check NULL values
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN rank IS NULL THEN 1 ELSE 0 END) AS null_rank,
    SUM(CASE WHEN name IS NULL THEN 1 ELSE 0 END) AS null_name,
    SUM(CASE WHEN symbol IS NULL THEN 1 ELSE 0 END) AS null_symbol,
    SUM(CASE WHEN ranking_date IS NULL THEN 1 ELSE 0 END) AS null_date
FROM dbo.CompanyRankingHistory;
GO


-- Ranking coverage by date
SELECT
    ranking_date,
    COUNT(*) AS company_count,
    MIN(rank) AS min_rank,
    MAX(rank) AS max_rank
FROM dbo.CompanyRankingHistory
GROUP BY ranking_date
ORDER BY ranking_date;
GO


-- Check ranking symbols against Company
SELECT
    COUNT(*) AS missing_company_symbols
FROM dbo.CompanyRankingHistory rh
LEFT JOIN dbo.Company c
    ON c.symbol = rh.symbol
WHERE c.symbol IS NULL;
GO


-- Show missing symbols
SELECT DISTINCT
    rh.symbol
FROM dbo.CompanyRankingHistory rh
LEFT JOIN dbo.Company c
    ON c.symbol = rh.symbol
WHERE c.symbol IS NULL
ORDER BY rh.symbol;
GO


/* ============================================================
   5. Market Price Summary
   ============================================================ */

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT company_id) AS companies_with_price_data,
    MIN(price_date) AS min_date,
    MAX(price_date) AS max_date
FROM dbo.MarketPrice;
GO


/* ============================================================
   6. Market Price Preview
   ============================================================ */

-- Latest 20 rows for NVDA
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
ORDER BY price_date DESC;
GO


/* ============================================================
   7. Market Price Data Quality
   ============================================================ */

-- Check required NULL values
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
    OR [close] IS NULL;
GO


-- Check duplicate business keys
SELECT
    company_id,
    price_date,
    COUNT(*) AS row_count
FROM dbo.MarketPrice
GROUP BY
    company_id,
    price_date
HAVING COUNT(*) > 1;
GO


-- Check orphan company IDs
SELECT
    COUNT(*) AS orphan_rows
FROM dbo.MarketPrice mp
LEFT JOIN dbo.Company c
    ON mp.company_id = c.company_id
WHERE c.company_id IS NULL;
GO


-- Check invalid OHLC relationships
SELECT
    COUNT(*) AS invalid_ohlc_rows
FROM dbo.MarketPrice
WHERE
    [high] < [low]
    OR [open] < [low]
    OR [open] > [high]
    OR [close] < [low]
    OR [close] > [high];
GO


/* ============================================================
   8. Market Price Coverage
   ============================================================ */

-- Coverage by company
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
ORDER BY company_id;
GO


-- Latest price date by company
SELECT
    company_id,
    symbol,
    MAX(price_date) AS latest_price_date
FROM dbo.MarketPrice
GROUP BY
    company_id,
    symbol
ORDER BY company_id;
GO


-- Companies without market price data
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
ORDER BY c.company_id;
GO


/* ============================================================
   9. Final Project 18 Validation
   ============================================================ */

SELECT
    (SELECT COUNT(*)
     FROM dbo.Company) AS company_count,

    (SELECT COUNT(*)
     FROM dbo.CompanyRankingHistory) AS ranking_history_rows,

    (SELECT COUNT(*)
     FROM dbo.MarketPrice) AS market_price_rows,

    (SELECT COUNT(DISTINCT company_id)
     FROM dbo.MarketPrice) AS companies_with_price_data,

    (SELECT MIN(price_date)
     FROM dbo.MarketPrice) AS min_price_date,

    (SELECT MAX(price_date)
     FROM dbo.MarketPrice) AS max_price_date;
GO


/* ============================================================
   10. Final MarketPrice QA Check
   ============================================================ */

SELECT
    (SELECT COUNT(*)
     FROM dbo.MarketPrice) AS total_market_price_rows,

    (SELECT COUNT(DISTINCT company_id)
     FROM dbo.MarketPrice) AS companies_with_price_data,

    (SELECT COUNT(*)
     FROM dbo.MarketPrice
     WHERE company_id IS NULL
        OR symbol IS NULL
        OR price_date IS NULL
        OR [open] IS NULL
        OR [high] IS NULL
        OR [low] IS NULL
        OR [close] IS NULL) AS null_required_rows,

    (SELECT COUNT(*)
     FROM dbo.MarketPrice mp
     LEFT JOIN dbo.Company c
         ON mp.company_id = c.company_id
     WHERE c.company_id IS NULL) AS orphan_rows,

    (SELECT COUNT(*)
     FROM (
        SELECT
            company_id,
            price_date
        FROM dbo.MarketPrice
        GROUP BY
            company_id,
            price_date
        HAVING COUNT(*) > 1
     ) d) AS duplicate_business_keys,

    (SELECT COUNT(*)
     FROM dbo.MarketPrice
     WHERE
         [high] < [low]
         OR [open] < [low]
         OR [open] > [high]
         OR [close] < [low]
         OR [close] > [high]) AS invalid_ohlc_rows,

    (SELECT MIN(price_date)
     FROM dbo.MarketPrice) AS min_price_date,

    (SELECT MAX(price_date)
     FROM dbo.MarketPrice) AS max_price_date;
GO