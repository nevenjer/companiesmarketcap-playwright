# CompaniesMarketCap Playwright Automation

Automated web scraping and data validation framework built with **Playwright and TypeScript** for collecting company market-cap rankings from CompaniesMarketCap.

The project is designed as a reusable data collection pipeline rather than a simple web scraper. It extracts company information, maintains historical ranking data, stores structured JSON datasets, validates the scraping workflow through automated tests, and integrates the collected data with SQL Server.

## Project Overview

### Data Flow

```text
CompaniesMarketCap
        ↓
Playwright + TypeScript
        ↓
Company Data Extraction
        ↓
Validation & Deduplication
        ↓
JSON Data Storage
        ↓
SQL Server Database
        ↓
Future R Market Data Pipeline
        ↓
Data Analysis
```

## Key Features

* Automated browser-based data collection with Playwright
* TypeScript-based Page Object Model
* Market Cap ranking validation
* Dynamic pagination handling
* Extraction of company rank, name, symbol, and country
* Handling of dynamic website elements and privacy dialogs
* Duplicate detection and prevention
* Historical ranking snapshots by date and symbol
* Scrape metadata tracking
* Automated validation with Playwright Test
* Reusable scraper and storage services
* SQL Server database integration
* Database data quality validation
* Cross-table data integrity validation

## Tech Stack

* **TypeScript**
* **Playwright**
* **Playwright Test**
* **Node.js**
* **JSON**
* **SQL Server**
* **Docker**
* **Git / GitHub**

## Project Structure

```text
companiesmarketcap-playwright/
│
├── data/
│   ├── companies.json
│   ├── ranking_history.json
│   └── scrape_metadata.json
│
├── docs/
│   └── development-notes.md
│
├── sql/
│   ├── 0_queries.sql
│   ├── 1_create_database.sql
│   ├── 2_create_company.sql
│   └── 3_create_company_ranking_history.sql
│
├── src/
│   ├── config/
│   ├── pages/
│   ├── services/
│   ├── scripts/
│   │   ├── import_companies.ts
│   │   └── import_ranking_history.ts
│   ├── types/
│   └── utils/
│
├── tests/
│   └── companiesmarketcap.spec.ts
│
├── playwright.config.ts
├── package.json
└── tsconfig.json
```

## Data

The project maintains three main JSON datasets:

* `companies.json` — master company dataset
* `ranking_history.json` — historical market-cap ranking snapshots
* `scrape_metadata.json` — information about each scraping run

The historical ranking dataset uses **date + company symbol** as its record identity, allowing ranking changes to be tracked over time without creating duplicate records for the same date.

## Project 18.1 — SQL Database Integration

Project 18.1 extends the Playwright data collection pipeline by storing the collected company and ranking-history data in SQL Server.

### Database

```text
Database: CompaniesMarketCapDB
SQL Server: Docker
Host: localhost,8888
```

### Tables

```text
CompaniesMarketCapDB

├── dbo.Company
│   └── Company master data
│
└── dbo.CompanyRankingHistory
    └── Historical ranking snapshots
```

### Current Dataset

```text
Company Master
    11,342 companies

Ranking History
    22,683 records

Ranking Dates
    2026-09-25
    2026-09-29
```

### Data Import

Company data is imported from:

```text
data/companies.json
        ↓
src/scripts/import_companies.ts
        ↓
dbo.Company
```

Ranking history is imported from:

```text
data/ranking_history.json
        ↓
src/scripts/import_ranking_history.ts
        ↓
dbo.CompanyRankingHistory
```

### Database Validation

Project 18.1 includes SQL-based data quality checks for:

* Row count validation
* NULL value validation
* Duplicate detection
* Ranking completeness
* Missing rank detection
* Cross-table symbol integrity
* Database and table verification

The reusable verification and QA queries are stored in:

```text
sql/0_queries.sql
```

### Validation Results

The current dataset passed the following checks:

```text
Company records                         11,342
Ranking history records                 22,683
Duplicate symbol + date records             0
Missing required values                     0
Missing company symbols                     0
Missing ranking numbers                     0
```

## Running the Project

Install dependencies:

```bash
npm install
```

Run the Playwright test suite:

```bash
npx playwright test
```

Run tests with the browser visible:

```bash
npx playwright test --headed
```

Run a specific test:

```bash
npx playwright test tests/companiesmarketcap.spec.ts
```

Import company data into SQL Server:

```bash
npm run import:companies
```

Import ranking history into SQL Server:

```bash
npm run import:ranking
```

## Development Notes

The detailed development process, investigation steps, scraping challenges, architectural decisions, and validation approach are documented separately in:

`docs/development-notes.md`

## Project Goal

This project is part of a broader data engineering and QA automation workflow.

The current pipeline covers:

```text
Web Data Collection
        ↓
Playwright Automation
        ↓
Data Validation
        ↓
JSON Storage
        ↓
SQL Server Integration
        ↓
Database Quality Checks
```

Future development will extend the project with **R-based financial market data collection, database storage, and quantitative analysis**.
