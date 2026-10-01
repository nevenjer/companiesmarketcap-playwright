# Project 18 - Market Price Ingestion Pipeline

## 1. Overview

Project 18 collects public company and market data and stores it in SQL Server for structured analysis.

The project has two main data-collection layers:

1. CompaniesMarketCap collection
   - Company master data
   - Company ranking history

2. Market-price ingestion
   - Historical daily OHLCV data
   - Yahoo Finance
   - R
   - SQL Server

The market-price pipeline is designed around:

- Data validation
- Database integrity
- Idempotent ingestion
- Incremental upsert
- Transaction safety
- Multi-company processing
- Future scalability

The Playwright scraping layer and R market-price ingestion layer are intentionally separated.

---

## 2. Project Architecture

```text
CompaniesMarketCap
        |
        v
Playwright + TypeScript
        |
        +--------------------+
        |                    |
        v                    v
Company Master        Ranking History
        |                    |
        +---------+----------+
                  |
                  v
              SQL Server
                  |
                  v
          Company Reference
                  |
                  v
       R Market Price Ingestion
                  |
                  v
            Yahoo Finance
                  |
                  v
          Data Validation
                  |
                  v
           MarketPrice_Stage
                  |
                  v
          Transactional Upsert
             /          \
          UPDATE        INSERT
             \          /
                  v
             MarketPrice
                  |
                  v
          Future Analytics