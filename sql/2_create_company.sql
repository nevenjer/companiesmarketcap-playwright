USE CompaniesMarketCapDB;
GO


-- Create Company table if it does not exist
IF OBJECT_ID('dbo.Company', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Company
    (
        company_id INT IDENTITY(1,1) NOT NULL,
        rank INT NOT NULL,
        name NVARCHAR(255) NOT NULL,
        symbol NVARCHAR(100) NOT NULL,
        country NVARCHAR(100) NULL,
        last_updated DATETIME2(3) NOT NULL,

        CONSTRAINT PK_Company
            PRIMARY KEY (company_id),

        CONSTRAINT UQ_Company_Symbol
            UNIQUE (symbol)
    );
END;
GO


-- Check Company table
SELECT
    name AS TableName
FROM sys.tables
WHERE name = 'Company';
GO


-- Check Company columns
SELECT
    c.column_id,
    c.name AS ColumnName,
    t.name AS DataType,
    c.max_length,
    c.is_nullable
FROM sys.columns c
JOIN sys.types t
    ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.Company')
ORDER BY c.column_id;
GO


-- Check Company constraints
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
WHERE kc.parent_object_id = OBJECT_ID('dbo.Company')
ORDER BY kc.type_desc, c.column_id;
GO