-- Create database if it does not exist
IF DB_ID('CompaniesMarketCapDB') IS NULL
BEGIN
    CREATE DATABASE CompaniesMarketCapDB;
END;
GO


-- Switch to project database
USE CompaniesMarketCapDB;
GO


-- Check current database
SELECT DB_NAME() AS CurrentDatabase;
GO


-- Check project tables
SELECT
    SCHEMA_NAME(t.schema_id) AS SchemaName,
    t.name AS TableName
FROM sys.tables t
ORDER BY t.name;
GO