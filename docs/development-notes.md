# Development Notes — CompaniesMarketCap Data Collection Pipeline

## 1. Project Goal

The goal of this project was to build an automated and reusable data collection pipeline for company symbols from CompaniesMarketCap.

The project was not designed as a simple web scraper.

The main objective was to create a reliable and reusable dataset that can serve as an input for:

* SQL Server
* R
* Financial market data collection
* Data analysis
* Quantitative research

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
JSON Storage
        ↓
SQL Server
        ↓
Database Validation
        ↓
Future Market Data Pipeline
        ↓
R / Financial Data Analysis
```

The pipeline is designed so that the number of companies and historical records can change over time without requiring changes to the core validation rules.

---

# 2. Development Approach

I did not start with the final architecture.

I first investigated the website, tested assumptions, inspected the HTML structure, tried different selectors, encountered unexpected behavior, and gradually improved the implementation.

The development process was:

```text
Explore
   ↓
Inspect
   ↓
Test assumptions
   ↓
Extract one record
   ↓
Extract one page
   ↓
Handle unexpected rows
   ↓
Handle pagination
   ↓
Build reusable Page Object
   ↓
Build scraper service
   ↓
Design data model
   ↓
Store data
   ↓
Prevent duplicates
   ↓
Track historical rankings
   ↓
Add metadata
   ↓
Validate the pipeline
   ↓
Test idempotency
   ↓
Integrate SQL Server
   ↓
Final reusable dataset
```

This approach helped me understand the system before optimizing the implementation.

The project was developed incrementally so that each stage could be tested before moving to the next stage.

---

# 3. Initial Exploration

The first step was to verify that Playwright could open CompaniesMarketCap successfully.

### Initial test

```ts
import { test, expect } from '@playwright/test';

test('Open CompaniesMarketCap', async ({ page }) => {

    await page.goto('/');

    await expect(page).toHaveTitle(
        /CompaniesMarketCap/
    );

    await page.pause();
});
```

### What I learned

Before writing the scraper, I verified that:

* The website was accessible.
* Playwright could load the page.
* The expected page title was available.
* The browser could interact with the page.

This provided a working starting point for further investigation.

---

# 4. Verify the Required Ranking

The required dataset was based on the **Market Cap** ranking.

I created a Page Object and checked whether the Market Cap option was active.

```ts
import { Page, Locator } from '@playwright/test';

export class CompaniesMarketCapPage {

    readonly page: Page;

    readonly marketCapOption: Locator;

    constructor(page: Page) {

        this.page = page;

        this.marketCapOption = page
            .locator('span.option')
            .filter({ hasText: /^Market Cap$/ });
    }

    async open(): Promise<void> {

        await this.page.goto('/');
    }

    async isMarketCapActive(): Promise<boolean> {

        return await this.marketCapOption.evaluate((element) =>
            element.classList.contains('active')
        );
    }

}
```

### Why this check was important

The scraper should not silently collect data from the wrong ranking.

I therefore added an explicit validation step before starting the full scraping process.

This makes the scraper less dependent on assumptions about the default website state.

---

# 5. Inspect the First Company Row

Instead of immediately trying to scrape thousands of companies, I first inspected a single table row.

The first experiment was simply to print the row content.

```ts
async getFirstCompany(): Promise<void> {

    const firstRow = this.companyRows.first();

    console.log('First row text:');

    console.log(await firstRow.innerText());

}
```

### Why I started with one row

Working with one record made it easier to understand:

* The table structure
* The available fields
* The location of the company name
* The location of the symbol
* The location of the country
* The ranking information

This reduced the risk of building the scraper around incorrect assumptions.

---

# 6. Inspect the `<td>` Structure

The next step was to inspect every table cell.

```ts
async getFirstCompany(): Promise<void> {

    const firstRow = this.companyRows.first();

    const cells = firstRow.locator('td');

    console.log('Number of cells:', await cells.count());

    for (let i = 0; i < await cells.count(); i++) {

        console.log(
            `Cell ${i}:`,
            await cells.nth(i).innerText()
        );

    }

}
```

### What I discovered

The company row contained multiple `<td>` elements.

The important fields were located at specific positions:

```text
Cell 1 → Rank
Cell 2 → Company name + Symbol
Cell 7 → Country
```

Other cells contained information that was not required for this dataset.

The exact DOM structure is treated as an implementation detail and may require adjustment if the source website changes.

---

# 7. Build the First Company Object

After understanding the HTML structure, I created a structured TypeScript object.

```ts
async getFirstCompany(): Promise<{
    rank: number;
    name: string;
    symbol: string;
    country: string;
}> {

    const firstRow = this.companyRows.first();

    const cells = firstRow.locator('td');

    const rank = Number(
        (await cells.nth(1).innerText()).trim()
    );

    const nameCell = cells.nth(2);

    const name = (
        await nameCell
            .locator('div')
            .first()
            .innerText()
    ).trim();

    const symbol = (
        await nameCell
            .locator('div')
            .nth(1)
            .innerText()
    ).trim();

    const country = (
        await cells.nth(7).innerText()
    ).trim();

    return {
        rank,
        name,
        symbol,
        country,
    };
}
```

### Example result

```text
{
    rank: 1,
    name: "NVIDIA",
    symbol: "NVDA",
    country: "USA"
}
```

This was the first point where raw HTML became structured data.

---

# 8. Test the First Company

I then created an automated test to verify the extracted values.

```ts
test('Get first company', async ({ page }) => {

    const companiesMarketCapPage =
        new CompaniesMarketCapPage(page);

    await companiesMarketCapPage.open();

    const isActive =
        await companiesMarketCapPage.isMarketCapActive();

    expect(isActive).toBe(true);

    const company =
        await companiesMarketCapPage.getFirstCompany();

    expect(company.rank).toBe(1);
    expect(company.name).toBe('NVIDIA');
    expect(company.symbol).toBe('NVDA');
    expect(company.country).toBe('USA');

});
```

### Why this test mattered

Before scaling the scraper, I wanted to prove that the extraction logic was correct for a known record.

This reduced the debugging scope before introducing pagination and large-scale extraction.

---

# 9. Scale from One Company to One Page

Once the first company worked, I changed the extraction logic to process the entire page.

The initial implementation used a loop through each row.

```ts
const rows = this.companyRows;

const rowCount = await rows.count();

const companies = [];

for (let i = 0; i < rowCount; i++) {

    const row = rows.nth(i);

    const cells = row.locator('td');

    const rank = Number(
        (await cells.nth(1).innerText()).trim()
    );

    const name = (
        await cells.nth(2)
            .locator('.company-name')
            .innerText()
    ).trim();

    const symbol = (
        await cells.nth(2)
            .locator('.company-code')
            .innerText()
    ).trim();

    const country = (
        await cells.nth(7)
            .innerText()
    ).trim();

    companies.push({
        rank,
        name,
        symbol,
        country,
    });

}
```

### Validation

During development, the page-size expectation was used as an exploratory validation.

The important principle is not that every future page must contain a fixed number of records.

The important principle is that:

* Valid company rows are extracted.
* Non-company rows are ignored.
* Extracted records contain the required fields.
* The scraper detects unexpected page structures.

This makes the validation more resilient to future changes in the source dataset.

---

# 10. Unexpected DOM Rows

During investigation, I discovered that the table did not contain only company rows.

The DOM contained more rows than expected because advertisement rows were also present.

For example, an exploratory page could contain:

```text
Expected:
Company rows

Actual DOM:
Company rows + non-company rows
```

This was an important real-world scraping problem.

The solution was to validate the row structure before extracting data.

```ts
// Skip non-company rows such as advertisements.

if (cells.length < 8) {

    continue;

}
```

### Why this matters

A scraper should not assume that every DOM row represents valid data.

Real websites may contain:

* Advertisements
* Empty rows
* Promotional content
* Layout elements
* Other non-data rows

The scraper therefore checks the structure before processing each row.

This is an example of defensive scraping.

---

# 11. Use `data-sort` for Rank

Another issue appeared with the ranking column.

The visible rank cell could contain additional information, such as ranking movement.

Therefore, using:

```ts
innerText()
```

was not always the most reliable way to obtain the actual rank.

The HTML contained a `data-sort` attribute.

I changed the extraction logic to:

```ts
const rankValue =
    cells[1].getAttribute('data-sort');

const rank = Number(rankValue);
```

### Why this was better

The scraper now uses the underlying structured value instead of depending on presentation text.

This is an important scraping principle:

> Prefer stable machine-readable attributes when they are available instead of relying only on visible text.

This also reduces the risk of accidentally parsing ranking movement information as part of the rank value.

---

# 12. Improve Extraction Performance

The first implementation processed rows one by one through Playwright locators.

After understanding the DOM, I moved the extraction into the browser context using `evaluateAll()`.

```ts
const companies = await rows.evaluateAll((rowElements) => {

    const results = [];

    for (const row of rowElements) {

        const cells = row.querySelectorAll('td');

        // Skip non-company rows such as advertisements.

        if (cells.length < 8) {

            continue;

        }

        const rankValue =
            cells[1].getAttribute('data-sort');

        const nameElement =
            cells[2].querySelector('.company-name');

        const symbolElement =
            cells[2].querySelector('.company-code');

        const rank = Number(rankValue);

        const name =
            nameElement?.textContent?.trim() ?? '';

        const symbol =
            symbolElement?.textContent?.trim() ?? '';

        const country =
            cells[7].textContent?.trim() ?? '';

        results.push({
            rank,
            name,
            symbol,
            country,
        });

    }

    return results;

});
```

### Result

The extraction became:

* More direct
* Easier to reason about
* Less dependent on repeated Playwright locator calls
* Better suited for processing many rows

The optimization was introduced only after the DOM structure was understood.

---

# 13. Pagination

After successfully extracting one page, the next challenge was collecting all pages.

The website provided a pagination link:

```html
<a class="page-link" href="/page/2/">
    Next 100❯
</a>
```

I created a reusable locator:

```ts
this.nextPageLink = page
    .locator('a.page-link')
    .filter({
        hasText: 'Next 100'
    });
```

I then implemented pagination using the actual `href`.

```ts
async goToNextPage(): Promise<void> {

    await this.acceptPrivacy();

    const nextPageUrl =
        await this.nextPageLink.getAttribute('href');

    if (!nextPageUrl) {

        throw new Error(
            'Next page URL was not found.'
        );

    }

    const nextPageAbsoluteUrl =
        new URL(nextPageUrl, this.page.url()).href;

    await this.page.goto(
        nextPageAbsoluteUrl,
        {
            waitUntil: 'domcontentloaded',
        }
    );

}
```

Using the actual link destination makes the pagination logic less dependent on a hard-coded page count.

---

# 14. Pagination Loop

The scraper then repeatedly collected pages until there was no next page.

```ts
while (true) {

    const companies =
        await companiesMarketCapPage
            .getCompaniesFromCurrentPage();

    allCompanies.push(...companies);

    const hasNext =
        await companiesMarketCapPage.hasNextPage();

    if (!hasNext) {

        break;

    }

    await companiesMarketCapPage.goToNextPage();

    pageNumber++;

}
```

### Why this design was useful

The scraper does not depend on a fixed number of pages.

It continues until the website reports that there is no next page.

This is important because the source dataset can grow or shrink over time.

---

# 15. Browser and Privacy Interference

During testing, browser-level elements could interfere with normal page interaction.

A privacy dialog could appear:

```text
#qc-cmp2-ui
```

I therefore added explicit handling:

```ts
async acceptPrivacy(): Promise<void> {

    if (await this.privacyDialog.isVisible()) {

        await this.privacyAgreeButton.click();

        await this.privacyDialog.waitFor({
            state: 'hidden',
        });

    }

}
```

### Important lesson

Automated browser testing must account for more than the target data.

Real websites can contain:

* Privacy dialogs
* Advertising
* Interstitials
* Dynamic content
* Unexpected overlays

The automation must handle these conditions before continuing with the main workflow.

---

# 16. Page Object Model

After the extraction logic became stable, I organized the website interaction into a Page Object.

```text
tests
   ↓
CompaniesMarketCapPage
   ↓
Website
```

The Page Object contains responsibilities such as:

```text
open()

isMarketCapActive()

getCompaniesFromCurrentPage()

hasNextPage()

goToNextPage()

acceptPrivacy()
```

### Why I used Page Object Model

It separates:

```text
Test logic
```

from:

```text
Website interaction logic
```

This makes the project easier to:

* Maintain
* Test
* Reuse
* Debug
* Extend

The Page Object also provides a single place to update when the website structure changes.

---

# 17. Scraper Service

After the Page Object became stable, I moved the complete scraping workflow into a service.

```ts
export interface ScrapeResult {

    companies: Company[];

    metadata: ScrapeMetadata;

}
```

The scraper service is responsible for:

1. Opening the website
2. Validating the Market Cap ranking
3. Collecting pages
4. Extracting companies
5. Handling pagination
6. Generating metadata
7. Returning the final dataset

This separates browser interaction from the overall scraping workflow.

The result is a clearer separation between:

```text
Page Object
    ↓
Website interaction

Scraper Service
    ↓
Workflow orchestration

Storage
    ↓
Data persistence
```

---

# 18. Data Model

I created explicit TypeScript interfaces.

```ts
export interface Company {

    rank: number;

    name: string;

    symbol: string;

    country: string;

    lastUpdated: string;

}
```

Historical ranking:

```ts
export interface RankingHistory {

    rank: number;

    name: string;

    symbol: string;

    country: string;

    date: string;

}
```

Scraping metadata:

```ts
export interface ScrapeMetadata {

    source: string;

    ranking: string;

    lastRun: string;

    pagesScraped: number;

    recordsScraped: number;

    uniqueCompanies: number;

    duplicates: number;

    status: 'success' | 'failed';

}
```

### Why this was important

The data structure became explicit instead of being an unstructured collection of objects.

This also allows TypeScript to detect incorrect data usage during development.

The interfaces describe the data structure, while validation determines whether the actual values are acceptable.

---

# 19. Master Company Dataset

The main dataset is stored in:

```text
data/companies.json
```

The master dataset uses the company symbol as the logical identity.

The storage logic uses a `Map`:

```ts
const companiesBySymbol =
    new Map<string, Company>();
```

Existing records are loaded first.

New records are then applied.

```ts
for (const company of newCompanies) {

    companiesBySymbol.set(
        company.symbol,
        company
    );

}
```

### Result

If a symbol already exists:

```text
Existing company → Update
```

If a symbol is new:

```text
New company → Insert
```

If an old company is not present in the current scrape:

```text
Existing historical company → Keep
```

This makes the master dataset reusable across multiple runs.

The master dataset therefore represents the latest known company information while preserving companies that were previously collected.

---

# 20. Duplicate Prevention

Duplicate symbols are explicitly checked.

```ts
const uniqueSymbols =
    new Set(
        companies.map(
            company => company.symbol
        )
    );

const duplicates =
    companies.length -
    uniqueSymbols.size;
```

### Validation Rule

The master dataset must maintain a unique company symbol for each company.

The validation therefore checks:

* Total records
* Unique symbols
* Duplicate symbols

The expected number of companies is **not hard-coded** because the dataset may grow or change over time.

The important condition is:

```text
Total records
      =
Unique symbols
      +
Duplicate records
```

A successful validation should report zero duplicate symbols in the master dataset.

---

# 21. Historical Ranking Data

The project also stores ranking snapshots separately:

```text
data/ranking_history.json
```

The logical identity of a historical ranking record is:

```text
ranking_date + symbol
```

For example:

```text
2026-09-25 + NVDA
```

This allows the same company to appear again on a future date without treating it as a duplicate historical observation.

### Example

```text
2026-09-25 | NVDA | Rank 1

2026-09-26 | NVDA | Rank 2
```

This preserves historical ranking changes.

The historical dataset therefore grows as new ranking dates are collected.

---

# 22. Idempotency

One important requirement was that processing the same logical ranking observation should not create duplicate historical observations.

The storage logic uses a logical key based on:

```ts
const key =
    `${date}_${company.symbol}`;
```

### Idempotency Rule

The logical identity of a historical record is:

```text
ranking_date + symbol
```

Therefore:

```text
Existing date + symbol
        ↓
Same logical observation

New date + symbol
        ↓
New historical snapshot
```

For example:

```text
2026-09-25 + NVDA
```

and:

```text
2026-09-26 + NVDA
```

are two different historical observations.

The same:

```text
2026-09-25 + NVDA
```

should not be represented twice in the logical historical dataset.

### Important implementation note

The current SQL Server table also has QA queries that detect duplicate `symbol + ranking_date` combinations.

The current database schema does not yet enforce this combination with a database-level unique constraint.

Therefore, uniqueness is currently treated as a **data validation rule and application-level logical identity**, rather than as a SQL constraint.

This distinction is intentional and leaves room for future database hardening.

---

# 23. Scrape Metadata

The project stores execution metadata separately:

```text
data/scrape_metadata.json
```

Example:

```json
{
    "source": "CompaniesMarketCap",
    "ranking": "Market Cap",
    "lastRun": "2026-09-29T09:09:54.071Z",
    "pagesScraped": 114,
    "recordsScraped": 11342,
    "uniqueCompanies": 11342,
    "duplicates": 0,
    "status": "success"
}
```

The values in this example are execution-specific and should be treated as a snapshot, not as permanent project requirements.

### Why metadata is useful

The dataset contains the business data.

The metadata describes the execution that produced the dataset.

This makes the pipeline easier to audit and validate.

Metadata can also be used in future monitoring and scheduled pipeline execution.

---

# 24. Automated Validation

The project does not only scrape data.

It also validates the result.

Validation includes:

```text
Page processing status

Record extraction

Required field validation

Rank validity

Symbol uniqueness

Duplicate detection

Ranking history integrity

Cross-dataset consistency

Metadata integrity

Database integrity
```

### Validation Philosophy

The validation logic does not depend on a fixed number of companies or pages.

For example, the test should verify:

```text
Company symbols are unique
```

rather than:

```text
Expected companies = fixed number
```

Similarly, pagination should verify that:

```text
All available pages were processed
```

rather than:

```text
Expected pages = fixed number
```

This allows the same validation framework to continue working as the source dataset grows or changes.

---

# 25. Cross-Dataset Validation

The current ranking snapshot is compared with the master company dataset.

For each ranking record, the pipeline verifies that the company symbol exists in the master dataset.

The validation rule is:

```text
Ranking-history symbol
        ↓
must exist in
        ↓
Company master dataset
```

The validation checks for missing symbols rather than expecting a fixed record count.

This allows the check to remain valid as:

* New companies are added
* Company information changes
* Ranking dates increase
* Historical records accumulate

The same principle is applied to the SQL Server representation of the datasets.

---

# 26. Dataset Snapshot

The datasets generated by this project are continuously updated.

Therefore, dataset size should be treated as a **snapshot of a specific execution**, not as a permanent project value.

### Current validation snapshot

As of **2026-09-29**, the SQL Server database contains:

```text
Company master:
11,342 records

Ranking history:
22,683 records
```

Ranking-history coverage currently includes:

```text
2026-09-25 → 11,341 records

2026-09-29 → 11,342 records
```

Current QA results:

```text
Duplicate company symbols:          0

Duplicate symbol + date records:    0

NULL values in Company:             0

NULL values in Ranking History:     0

Missing ranking ranks:               0

Ranking symbols missing from
Company master:                      0
```

These values represent the database state at the time of this development snapshot.

They are **not fixed requirements or maximum limits**.

Future scraping runs may produce:

* More companies
* Fewer companies
* New ranking dates
* New companies
* Updated company information
* More historical records

The project does not assume a fixed maximum dataset size.

### Example record

```json
{
    "rank": 1,
    "name": "NVIDIA",
    "symbol": "NVDA",
    "country": "USA",
    "lastUpdated": "2026-09-29T09:09:54.071Z"
}
```

The dataset can now be reused by other parts of the larger data pipeline.

---

# 27. Testing Strategy

The project evolved from simple exploratory tests into structured workflow tests.

The testing progression was:

```text
Open website
      ↓
Verify page
      ↓
Verify Market Cap
      ↓
Inspect first row
      ↓
Extract first company
      ↓
Extract page data
      ↓
Test pagination
      ↓
Scrape multiple pages
      ↓
Scrape complete available dataset
      ↓
Validate duplicates
      ↓
Test JSON storage
      ↓
Test upsert
      ↓
Test ranking history
      ↓
Test idempotency
      ↓
Validate metadata
      ↓
Import into SQL Server
      ↓
Validate database
```

This reflects how I actually developed the solution rather than only presenting the final code.

The test strategy focuses on behavior and data integrity rather than fixed dataset size.

---

# 28. Development Experiments vs Final Source Code

During development, I used temporary code to investigate the website.

Examples included:

* Printing the first row
* Printing every `<td>`
* Printing all DOM rows
* Testing different selectors
* Inspecting pagination
* Inspecting privacy dialogs
* Testing the first company object
* Testing page-level extraction

These experiments were useful during development, but they do not all belong in the final production source.

### Final source code principle

The final source should contain:

```text
Clean
Reusable
Testable
Maintainable
Production-oriented code
```

The development history should contain:

```text
Investigation
Experiments
Problems
Discoveries
Decisions
Solutions
```

Therefore, exploratory code was moved into this document instead of being left as large blocks of commented-out code inside the production files.

---

# 29. Why I Kept the Development History

The development history demonstrates more than the final result.

It shows how I:

* Investigated an unfamiliar website
* Inspected the DOM
* Tested assumptions
* Identified unexpected rows
* Improved selectors
* Found a more reliable ranking attribute
* Handled pagination
* Handled privacy interference
* Refactored the solution
* Designed reusable data structures
* Added duplicate prevention
* Added historical tracking
* Added validation
* Tested idempotency
* Integrated SQL Server
* Added database-level QA checks

The important engineering lesson was:

> The final solution was built through investigation and iteration, not by assuming the website structure from the beginning.

This development history is therefore part of the project's engineering documentation, not just a record of failed experiments.

---

# 30. What Was Changed from the Experimental Code

The experimental code should not remain as large commented blocks inside:

```text
src/pages/CompaniesMarketCapPage.ts

tests/companiesmarketcap.spec.ts
```

Instead:

### Keep in final source

Useful comments such as:

```ts
// Skip non-company rows such as advertisements.
```

and:

```ts
// Use the machine-readable ranking value from data-sort.
```

These comments explain important implementation decisions.

### Move to development notes

Temporary code such as:

```ts
console.log('First row text:');

console.log(await firstRow.innerText());
```

or:

```ts
console.log('Number of cells:', await cells.count());
```

or:

```ts
console.log('Total DOM rows:', rowCount);
```

should be documented here because they describe the investigation process.

The final source code should focus on the reusable solution rather than the complete history of debugging.

---

# 31. Final Project Architecture

The final project is organized as:

```text
companiesmarketcap-playwright/

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
│   │   └── config.ts
│   │
│   ├── pages/
│   │   └── CompaniesMarketCapPage.ts
│   │
│   ├── scripts/
│   │   ├── import_companies.ts
│   │   └── import_ranking_history.ts
│   │
│   ├── services/
│   │   ├── scraper.ts
│   │   └── storage.ts
│   │
│   ├── types/
│   │   └── company.ts
│   │
│   └── utils/
│       └── dateTime.ts
│
├── tests/
│   └── companiesmarketcap.spec.ts
│
├── playwright.config.ts
├── tsconfig.json
├── package.json
├── package-lock.json
├── README.md
└── Structure_Project_18.txt
```

The architecture separates:

```text
Data
Documentation
Database scripts
Browser interaction
Scraping workflow
Import scripts
Data types
Utilities
Tests
```

This separation makes the project easier to maintain and extend.

---

# 32. Technology Stack

### Current Technology Stack

```text
TypeScript
Playwright
Playwright Test
Node.js
HTML / DOM
CSS Selectors
JSON
SQL Server
Docker
Git / GitHub
```

### Current Data Pipeline

```text
CompaniesMarketCap
        ↓
Playwright
        ↓
Company Data Extraction
        ↓
JSON Storage
        ↓
SQL Server
        ↓
Database QA Validation
```

### Current Database

```text
CompaniesMarketCapDB

├── dbo.Company
│   └── Current company master data
│
└── dbo.CompanyRankingHistory
    └── Historical ranking snapshots
```

### Future Data Pipeline

```text
SQL Server
      ↓
Market Data Collection
      ↓
Historical Market Data
      ↓
R
      ↓
Technical Indicators
      ↓
Quantitative Analysis
```

SQL Server is already implemented in the current project.

R-based market-data processing and quantitative analysis are planned extensions.

---

# 33. What This Project Demonstrates

This project demonstrates practical experience with:

### Web Automation

* Playwright
* Browser automation
* Page Object Model
* Locator design
* DOM inspection
* Pagination
* Dynamic page handling
* Privacy-dialog handling

### Programming

* TypeScript
* Interfaces
* Functions
* Modules
* Error handling
* Maps and Sets
* Reusable services

### Data Engineering

* Data extraction
* Data transformation
* Data validation
* Duplicate prevention
* Upsert logic
* Historical snapshots
* Metadata
* Logical idempotency
* SQL Server integration

### Software Testing

* Automated tests
* Positive validation
* Edge-case handling
* Integration workflow testing
* Data integrity checks
* Database validation

### Problem Solving

The project also demonstrates the ability to:

```text
Identify a problem
      ↓
Investigate
      ↓
Test assumptions
      ↓
Find the root cause
      ↓
Design a solution
      ↓
Implement
      ↓
Validate
      ↓
Refactor
```

---

# 34. Final Engineering Result

The final solution is more than a scraper.

It is a small automated data collection pipeline with:

```text
Source validation
        +
DOM extraction
        +
Pagination
        +
Edge-case handling
        +
Reusable architecture
        +
Structured data models
        +
JSON storage
        +
SQL Server storage
        +
Duplicate prevention
        +
Historical tracking
        +
Metadata
        +
Automated validation
        +
Database QA
        +
Idempotency logic
```

The result is a reusable company-symbol dataset that can serve as an input for future financial-data workflows.

The project also provides a foundation for expanding from company ranking data into larger market-data pipelines.

---

# 35. Key Lessons Learned

### Lesson 1 — Understand the source before automating it

I first inspected the page structure instead of immediately writing a large scraper.

### Lesson 2 — Do not trust visible text blindly

The ranking value was more reliable when extracted from `data-sort`.

### Lesson 3 — Real websites contain unexpected elements

Advertisement rows and privacy dialogs had to be handled explicitly.

### Lesson 4 — Start small, then scale

The extraction process evolved from:

```text
1 row
   ↓
Page data
   ↓
Multiple pages
   ↓
Complete available dataset
```

### Lesson 5 — Data quality is part of automation

Scraping data is only part of the problem.

The result must also be:

```text
validated

consistent

deduplicated

reusable
```

### Lesson 6 — Separate responsibilities

The project became easier to maintain after separating:

```text
Page interaction

Scraping workflow

Data storage

Database scripts

Data types

Utilities

Tests
```

### Lesson 7 — Idempotency matters

The same logical historical observation should not create duplicate historical records.

### Lesson 8 — Do not hard-code changing business data

The number of companies, pages, and historical records can change over time.

Therefore, validation should focus on data-quality rules rather than fixed dataset sizes.

### Lesson 9 — Separate current state from historical state

The master dataset represents current company information.

The ranking-history dataset preserves observations over time.

This allows the dataset to grow without losing historical information.

### Lesson 10 — Database validation is part of the pipeline

Moving data into SQL Server is not the end of the process.

The database must also be checked for:

* Row counts
* Duplicate symbols
* Duplicate historical keys
* NULL values
* Ranking coverage
* Cross-table consistency

---

# 36. Dataset Growth Strategy

The project is designed for continuous data growth.

The number of companies and historical records is expected to change over time as new scraping runs are performed.

The system therefore separates current state from historical state.

### Master Dataset

```text
data/companies.json
```

The master dataset represents the latest known company information.

The logical identity is:

```text
symbol
```

A symbol should appear only once in the master dataset.

If the company already exists:

```text
Existing symbol
      ↓
Update current information
```

If a new company appears:

```text
New symbol
      ↓
Add to master dataset
```

If a previously known company does not appear in the latest ranking:

```text
Historical company
      ↓
Keep existing master record
```

The exact storage behavior may evolve as the data model becomes more sophisticated, but the core principle is to avoid losing previously collected information unnecessarily.

### Historical Dataset

```text
data/ranking_history.json
```

The historical dataset preserves ranking observations over time.

The logical identity is:

```text
ranking_date + symbol
```

The same company can therefore appear many times across different dates.

Example:

```text
Date         Symbol    Rank

2026-09-25   NVDA      1
2026-09-26   NVDA      2
2026-09-27   NVDA      1
```

### Growth Model

```text
New company
    ↓
Add to master dataset
    ↓
Add historical snapshot
```

```text
Existing company
    ↓
Update master information
    ↓
Add new historical snapshot for a new date
```

```text
Company no longer appears
    ↓
Keep historical records
    ↓
Do not automatically delete history
```

This design allows the dataset to grow without losing historical information.

### Validation Philosophy

The project avoids hard-coded dataset-size expectations.

Instead of:

```text
Expected companies = 11,342
```

the validation focuses on:

```text
Symbols are unique
Required fields are valid
Ranks are valid
Historical keys are unique
Ranking snapshots are complete
Cross-dataset relationships are valid
```

This allows the same validation framework to remain useful as the dataset grows.

---

# 37. Future Development

The current project provides the foundation for a larger financial data pipeline.

The current implementation already includes:

```text
CompaniesMarketCap
        ↓
Playwright
        ↓
Company Symbol Dataset
        ↓
JSON
        ↓
SQL Server
        ↓
Database Validation
```

The planned development direction is:

```text
CompaniesMarketCap
        ↓
Playwright
        ↓
Company Symbol Dataset
        ↓
SQL Server
        ↓
Market Data Collection
        ↓
Historical Market Data
        ↓
R
        ↓
Technical Indicators
        ↓
Quantitative Analysis
```

Possible future improvements include:

* Automated scheduled scraping
* API-based market data collection
* Historical ranking analysis
* Market data storage
* Data quality monitoring
* Automated reporting
* CI/CD execution
* GitHub Actions
* Pipeline monitoring
* Performance optimization
* Large-scale historical data processing
* Database constraints for stronger data integrity
* More efficient bulk database loading

These are future extensions and are intentionally not presented as completed features.

---

# 38. Portfolio Summary

This project demonstrates how I approached a real data collection problem from investigation to implementation.

I started by exploring the website and understanding its DOM structure. I then developed the solution incrementally, from extracting one company to processing the complete available ranking.

During development, I encountered real-world issues such as advertisement rows, ranking presentation differences, pagination, privacy dialogs, and changing source data. I handled these issues through investigation, validation, and refactoring.

The final solution uses TypeScript and Playwright with Page Object Model, reusable services, structured data models, JSON storage, duplicate prevention, historical ranking tracking, metadata, automated validation, SQL Server integration, database QA, and logical idempotency.

The project is designed so that the number of companies and historical records can increase over time without requiring fixed record-count assumptions in the validation logic.

The main outcome is a reusable company-symbol dataset that provides an input layer for SQL Server and future R-based financial-data analysis workflows.

> The goal was not simply to scrape a website. The goal was to build a reliable, reusable, and extensible data input layer for a larger data pipeline.
