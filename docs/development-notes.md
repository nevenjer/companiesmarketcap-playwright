# Development Notes — CompaniesMarketCap Data Collection Pipeline

## 1. Project Goal

The goal of this project was to build an automated and reusable data collection pipeline for company symbols from CompaniesMarketCap.

The project was not designed as a simple web scraper.

The main objective was to create a reliable dataset that could later be used by:

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
Company Symbol Dataset
        ↓
JSON Storage
        ↓
Future SQL Server
        ↓
R / Financial Data Analysis
```

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
Final reusable dataset
```

This approach helped me understand the system before optimizing the implementation.

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
        await cells.nth(7).innerText()
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

The first page was expected to contain 100 companies.

```ts
expect(companies.length).toBe(100);
```

This confirmed that the scraper could scale from one record to a complete page.

---

# 10. Unexpected DOM Rows

During investigation, I discovered that the table did not contain only company rows.

The DOM contained more rows than expected because advertisement rows were also present.

For example:

```text
Expected:
100 company rows

Actual DOM:
102 rows
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

---

# 19. Master Company Dataset

The main dataset is stored in:

```text
data/companies.json
```

The master dataset uses the company symbol as the primary identity.

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

The final dataset was validated with:

```text
Total companies: 11,340
Unique symbols: 11,340
Duplicate symbols: 0
```

This confirmed that each company symbol appeared only once in the master dataset.

---

# 21. Historical Ranking Data

The project also stores ranking snapshots separately:

```text
data/ranking_history.json
```

The historical identity is:

```text
date + symbol
```

For example:

```text
2026-09-25 + NVDA
```

This allows the same company to appear again on a future date without creating duplicates for the same date.

### Example

```text
2026-09-25 | NVDA | Rank 1
2026-09-26 | NVDA | Rank 2
```

This preserves historical ranking changes.

---

# 22. Idempotency

One important requirement was that running the same workflow twice on the same day should not create duplicate historical records.

The storage logic uses:

```ts
const key =
    `${date}_${company.symbol}`;
```

The result is:

```text
First run:
11,340 records

Same-day rerun:
11,340 records

No duplicate date + symbol records
```

A future date creates a new historical snapshot.

This demonstrates idempotent data processing.

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
    "lastRun": "2026-09-25T11:59:25.248Z",
    "pagesScraped": 114,
    "recordsScraped": 11340,
    "uniqueCompanies": 11340,
    "duplicates": 0,
    "status": "success"
}
```

### Why metadata is useful

The dataset contains the business data.

The metadata describes the execution that produced the dataset.

This makes the pipeline easier to audit and validate.

---

# 24. Automated Validation

The project does not only scrape data.

It also validates the result.

Validation includes:

```text
Page count
Record count
Rank uniqueness
Symbol uniqueness
Duplicate detection
Ranking history integrity
Cross-file consistency
Metadata integrity
```

For the completed run:

```text
Pages scraped:       114
Companies scraped:   11,340
Unique companies:    11,340
Duplicate symbols:   0
Duplicate ranks:     0
```

---

# 25. Cross-File Validation

The current ranking snapshot was also compared with the master dataset.

Validation result:

```text
Today ranking records:       11,340
Missing from companies.json: 0
```

This verifies that the current ranking snapshot and master company dataset are consistent.

---

# 26. Final Dataset

The completed scraping run produced:

```text
114 pages
11,340 companies
11,340 unique symbols
0 duplicate symbols
0 duplicate ranks
```

Example record:

```json
{
    "rank": 1,
    "name": "NVIDIA",
    "symbol": "NVDA",
    "country": "USA",
    "lastUpdated": "2026-09-25T11:59:25.248Z"
}
```

The dataset can now be reused by other parts of a future data pipeline.

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
Extract 100 companies
      ↓
Test pagination
      ↓
Scrape multiple pages
      ↓
Scrape all companies
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
```

This reflects how I actually developed the solution rather than only presenting the final code.

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
* Testing 100-row extraction

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

The important engineering lesson was:

> The final solution was built through investigation and iteration, not by assuming the website structure from the beginning.

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

---

# 31. Final Project Architecture

The final project is organized as:

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
│   │   └── config.ts
│   │
│   ├── pages/
│   │   └── CompaniesMarketCapPage.ts
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
└── README.md
```

---

# 32. Technology Stack

```text
TypeScript
Playwright
Playwright Test
Node.js
HTML / DOM
CSS Selectors
JSON
Git / GitHub
```

Future integration:

```text
SQL Server
R
Financial Market Data APIs
Data Analysis
```

SQL Server and R are planned downstream integrations and are not presented as completed components of this scraper project.

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
* Idempotent processing

### Software Testing

* Automated tests
* Positive validation
* Edge-case handling
* Integration workflow testing
* Data integrity checks

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
Persistent storage
+
Duplicate prevention
+
Historical tracking
+
Metadata
+
Automated validation
+
Idempotency
```

The result is a reusable company-symbol dataset that can serve as an input for future financial-data workflows.

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
→ 100 rows
→ multiple pages
→ complete dataset
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
Data types
Utilities
Tests
```

### Lesson 7 — Idempotency matters

Running the same process again should not create duplicate historical records.

---

# 36. Future Development

Possible future extensions include:

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
R
        ↓
Technical Indicators
        ↓
Quantitative Analysis
```

Possible future improvements:

* SQL Server integration
* Automated scheduled scraping
* API-based market data collection
* Data quality monitoring
* Historical ranking analysis
* Automated reporting
* CI/CD execution
* GitHub Actions
* Database validation
* Data pipeline monitoring

These are future extensions and are intentionally not presented as completed features.

---

# 37. Portfolio Summary

This project demonstrates how I approached a real data collection problem from investigation to implementation.

I started by exploring the website and understanding its DOM structure. I then developed the solution incrementally, from extracting one company to processing the complete ranking.

During development, I encountered real-world issues such as advertisement rows, ranking presentation differences, pagination, and privacy dialogs. I handled these issues through investigation, validation, and refactoring.

The final solution uses TypeScript and Playwright with Page Object Model, reusable services, structured data models, JSON storage, duplicate prevention, historical ranking tracking, metadata, automated validation, and idempotency testing.

The main outcome is a reusable company-symbol dataset that can later provide input to SQL Server, R, and financial-data analysis workflows.

> The goal was not simply to scrape a website. The goal was to build a reliable and reusable data input for a larger data pipeline.
