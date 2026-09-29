USE CompaniesMarketCapDB;
GO


-- Create ranking history table if it does not exist
IF OBJECT_ID('dbo.CompanyRankingHistory', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CompanyRankingHistory
    (
        ranking_history_id BIGINT IDENTITY(1,1) NOT NULL,
        rank INT NOT NULL,
        name NVARCHAR(255) NOT NULL,
        symbol NVARCHAR(100) NOT NULL,
        country NVARCHAR(100) NULL,
        ranking_date DATE NOT NULL,

        CONSTRAINT PK_CompanyRankingHistory
            PRIMARY KEY (ranking_history_id)
    );
END;
GO


-- Check Ranking History table
SELECT
    name AS TableName
FROM sys.tables
WHERE name = 'CompanyRankingHistory';
GO


-- Check Ranking History columns
SELECT
    c.column_id,
    c.name AS ColumnName,
    t.name AS DataType,
    c.max_length,
    c.is_nullable
FROM sys.columns c
JOIN sys.types t
    ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.CompanyRankingHistory')
ORDER BY c.column_id;
GO


-- Check Ranking History constraints
SELECT
    kc.name AS ConstraintName,
    kc.type_desc AS ConstraintType,
    c.name AS ColumnName
FROM sys.key_constraints kc
JOIN sys.index_columns ic
    ON kc.parent_object_id = ic.object_id
    AND kc.unique_index_id = ic.index_id
JOIN sys.columns c
    ON ic.object_id = c.object_id
    AND ic.column_id = c.column_id
WHERE kc.parent_object_id = OBJECT_ID('dbo.CompanyRankingHistory')
ORDER BY kc.type_desc, c.column_id;
GO