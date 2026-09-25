# CompaniesMarketCap Playwright Automation

Automated web scraping and data validation framework built with **Playwright and TypeScript** for collecting company market-cap rankings from CompaniesMarketCap.

The project is designed as a reusable data collection pipeline rather than a simple web scraper. It extracts company information, maintains historical ranking data, stores structured JSON datasets, and validates the scraping workflow through automated tests.

## Project Overview

**Data Flow**

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
Future SQL Server / R / Data Analysis
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

## Tech Stack

* **TypeScript**
* **Playwright**
* **Playwright Test**
* **Node.js**
* **JSON**
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
├── src/
│   ├── config/
│   ├── pages/
│   ├── services/
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

The project maintains three main datasets:

* `companies.json` — master company dataset
* `ranking_history.json` — historical market-cap ranking snapshots
* `scrape_metadata.json` — information about each scraping run

The historical ranking dataset uses **date + company symbol** as its record identity, allowing ranking changes to be tracked over time without creating duplicate records for the same date.

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

## Development Notes

The detailed development process, investigation steps, scraping challenges, architectural decisions, and validation approach are documented separately in:

`docs/development-notes.md`

## Project Goal

This project is part of a broader data engineering and QA automation workflow, with the collected company data intended for future integration with **SQL Server, R, financial market data collection, and quantitative analysis**.
