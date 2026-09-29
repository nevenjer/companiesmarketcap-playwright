USE CompaniesMarketCapDB;
GO

/* =========================================================
   Project 18.1
   SQL Database Verification & QA Queries
   ========================================================= */


/* 1. Check current database */
SELECT DB_NAME() AS CurrentDatabase;
GO


/* 2. List project tables */
SELECT
    SCHEMA_NAME(t.schema_id) AS SchemaName,
    t.name AS TableName
FROM sys.tables t
ORDER BY t.name;
GO


/* 3. Check Company row count */
SELECT
    COUNT(*) AS CompanyCount
FROM dbo.Company;
GO


/* 4. Check Ranking History row count */
SELECT
    COUNT(*) AS RankingHistoryCount
FROM dbo.CompanyRankingHistory;
GO


/* 5. Preview Company Master */
SELECT TOP 20
    company_id,
    rank,
    name,
    symbol,
    country,
    last_updated
FROM dbo.Company
ORDER BY rank;
GO


/* 6. Preview Ranking History */
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


/* 7. Check duplicate symbols in Company */
SELECT
    symbol,
    COUNT(*) AS DuplicateCount
FROM dbo.Company
GROUP BY symbol
HAVING COUNT(*) > 1
ORDER BY DuplicateCount DESC;
GO


/* 8. Check duplicate symbol + date */
SELECT
    symbol,
    ranking_date,
    COUNT(*) AS DuplicateCount
FROM dbo.CompanyRankingHistory
GROUP BY
    symbol,
    ranking_date
HAVING COUNT(*) > 1
ORDER BY DuplicateCount DESC;
GO


/* 9. Check NULL values in Company */
SELECT
    COUNT(*) AS TotalRows,
    SUM(CASE WHEN rank IS NULL THEN 1 ELSE 0 END) AS NullRank,
    SUM(CASE WHEN name IS NULL THEN 1 ELSE 0 END) AS NullName,
    SUM(CASE WHEN symbol IS NULL THEN 1 ELSE 0 END) AS NullSymbol,
    SUM(CASE WHEN last_updated IS NULL THEN 1 ELSE 0 END) AS NullLastUpdated
FROM dbo.Company;
GO


/* 10. Check NULL values in Ranking History */
SELECT
    COUNT(*) AS TotalRows,
    SUM(CASE WHEN rank IS NULL THEN 1 ELSE 0 END) AS NullRank,
    SUM(CASE WHEN name IS NULL THEN 1 ELSE 0 END) AS NullName,
    SUM(CASE WHEN symbol IS NULL THEN 1 ELSE 0 END) AS NullSymbol,
    SUM(CASE WHEN ranking_date IS NULL THEN 1 ELSE 0 END) AS NullDate
FROM dbo.CompanyRankingHistory;
GO


/* 11. Check ranking coverage by date */
SELECT
    ranking_date,
    COUNT(*) AS CompanyCount,
    MIN(rank) AS MinRank,
    MAX(rank) AS MaxRank
FROM dbo.CompanyRankingHistory
GROUP BY ranking_date
ORDER BY ranking_date;
GO


/* 12. Check missing ranks */
SELECT
    ranking_date,
    COUNT(*) AS CompanyCount,
    MAX(rank) AS MaxRank,
    MAX(rank) - COUNT(*) AS MissingRankCount
FROM dbo.CompanyRankingHistory
GROUP BY ranking_date
ORDER BY ranking_date;
GO


/* 13. Check Ranking History against Company Master */
SELECT
    COUNT(*) AS MissingCompanySymbols
FROM dbo.CompanyRankingHistory rh
LEFT JOIN dbo.Company c
    ON c.symbol = rh.symbol
WHERE c.symbol IS NULL;
GO


/* 14. Show missing symbols if any exist */
SELECT DISTINCT
    rh.symbol
FROM dbo.CompanyRankingHistory rh
LEFT JOIN dbo.Company c
    ON c.symbol = rh.symbol
WHERE c.symbol IS NULL
ORDER BY rh.symbol;
GO