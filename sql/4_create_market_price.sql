USE CompaniesMarketCapDB;
GO

-- Create raw daily market price table
IF OBJECT_ID('dbo.MarketPrice', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.MarketPrice
    (
        market_price_id BIGINT IDENTITY(1,1) NOT NULL,
        company_id      INT NOT NULL,
        symbol          NVARCHAR(100) NOT NULL,
        price_date      DATE NOT NULL,

        [open]          DECIMAL(20,8) NULL,
        [high]          DECIMAL(20,8) NULL,
        [low]           DECIMAL(20,8) NULL,
        [close]         DECIMAL(20,8) NULL,
        volume          BIGINT NULL,
        adjusted        DECIMAL(20,8) NULL,

        created_at      DATETIME2(3) NOT NULL
            CONSTRAINT DF_MarketPrice_CreatedAt
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_MarketPrice
            PRIMARY KEY (market_price_id),

        CONSTRAINT FK_MarketPrice_Company
            FOREIGN KEY (company_id)
            REFERENCES dbo.Company(company_id),

        CONSTRAINT UQ_MarketPrice_CompanyDate
            UNIQUE (company_id, price_date)
    );
END;
GO

-- Create index for company and date queries
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_MarketPrice_CompanyDate'
      AND object_id = OBJECT_ID('dbo.MarketPrice')
)
BEGIN
    CREATE INDEX IX_MarketPrice_CompanyDate
        ON dbo.MarketPrice(company_id, price_date);
END;
GO

-- Create index for symbol and date queries
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = 'IX_MarketPrice_SymbolDate'
      AND object_id = OBJECT_ID('dbo.MarketPrice')
)
BEGIN
    CREATE INDEX IX_MarketPrice_SymbolDate
        ON dbo.MarketPrice(symbol, price_date);
END;
GO


-- Check table structure
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    NUMERIC_PRECISION,
    NUMERIC_SCALE,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'MarketPrice'
ORDER BY ORDINAL_POSITION;
GO

-- Check indexes and constraints
EXEC sp_help 'dbo.MarketPrice';
GO