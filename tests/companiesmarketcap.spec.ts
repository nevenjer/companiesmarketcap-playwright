// Test 100 Companies
import { test, expect } from '@playwright/test';
import { CompaniesMarketCapPage } from '../src/pages/CompaniesMarketCapPage';
import { scrapeAllCompanies } from '../src/services/scraper';
import { saveCompanies } from '../src/services/storage';

import {
    loadCompanies,
    upsertCompanies,
    saveRankingHistory,
    saveScrapeMetadata,
} from '../src/services/storage';

import { getCurrentDateTime } from '../src/utils/dateTime';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';


test('Get companies from first page', async ({ page }) => {
    const companiesMarketCapPage = new CompaniesMarketCapPage(page);

    await companiesMarketCapPage.open();

    const isActive = await companiesMarketCapPage.isMarketCapActive();

    expect(isActive).toBe(true);

    const companies =
        await companiesMarketCapPage.getCompaniesFromCurrentPage();

    console.log('Total companies:', companies.length);

    console.log('First company:', companies[0]);
    console.log('Last company:', companies[companies.length - 1]);

    expect(companies.length).toBe(100);

    expect(companies[0]).toEqual({
        rank: 1,
        name: 'NVIDIA',
        symbol: 'NVDA',
        country: 'USA',
    });
});


test('Check Next 100 pagination', async ({ page }) => {
    const companiesMarketCapPage = new CompaniesMarketCapPage(page);

    await companiesMarketCapPage.open();

    const nextPage = companiesMarketCapPage.nextPageLink;

    console.log('Next 100 count:', await nextPage.count());

    if (await nextPage.count() > 0) {
        console.log(
            'Next 100 visible:',
            await nextPage.first().isVisible()
        );

        console.log(
            'Next 100 href:',
            await nextPage.first().getAttribute('href')
        );
    }
});


test('Go to second page', async ({ page }) => {
    const companiesMarketCapPage = new CompaniesMarketCapPage(page);

    await companiesMarketCapPage.open();

    await companiesMarketCapPage.goToNextPage();

    const companies =
        await companiesMarketCapPage.getCompaniesFromCurrentPage();

    console.log('Page 2 total companies:', companies.length);
    console.log('Page 2 first company:', companies[0]);
    console.log('Page 2 last company:', companies[companies.length - 1]);

    expect(companies.length).toBe(100);

    expect(companies[0].rank).toBe(101);
});


test('Check if next page exists', async ({ page }) => {
    const companiesMarketCapPage = new CompaniesMarketCapPage(page);

    await companiesMarketCapPage.open();

    const hasNext =
        await companiesMarketCapPage.hasNextPage();

    console.log('Has next page:', hasNext);

    expect(hasNext).toBe(true);
});


test('Scrape multiple pages with pagination loop', async ({ page }) => {
    const companiesMarketCapPage = new CompaniesMarketCapPage(page);

    await companiesMarketCapPage.open();

    const allCompanies: {
        rank: number;
        name: string;
        symbol: string;
        country: string;
    }[] = [];

    let pageNumber = 1;

    while (true) {
        const companies =
            await companiesMarketCapPage.getCompaniesFromCurrentPage();

        console.log(
            `Page ${pageNumber}: ${companies.length} companies`
        );

        console.log(
            `URL: ${page.url()}`
        );

        console.log(
            `Rank range: ${companies[0].rank} - ${companies[companies.length - 1].rank
            }`
        );

        allCompanies.push(...companies);

        const hasNext =
            await companiesMarketCapPage.hasNextPage();

        if (!hasNext) {
            break;
        }

        await companiesMarketCapPage.goToNextPage();

        pageNumber++;
    }

    console.log('Total companies:', allCompanies.length);
    console.log('Total pages:', pageNumber);

    const uniqueRanks = new Set(
        allCompanies.map(company => company.rank)
    );

    const uniqueSymbols = new Set(
        allCompanies.map(company => company.symbol)
    );

    console.log('Unique ranks:', uniqueRanks.size);
    console.log('Unique symbols:', uniqueSymbols.size);

    console.log(
        'Duplicate ranks:',
        allCompanies.length - uniqueRanks.size
    );

    console.log(
        'Duplicate symbols:',
        allCompanies.length - uniqueSymbols.size
    );

    expect(allCompanies.length).toBeGreaterThan(0);

});


test('Scrape all companies using scraper service', async ({ page }) => {
    const result =
        await scrapeAllCompanies(page);

    const companies =
        result.companies;

    console.log(
        'Scraped companies:',
        companies.length
    );

    console.log(
        'First company:',
        companies[0]
    );

    console.log(
        'Last company:',
        companies[
        companies.length - 1
        ]
    );

    expect(companies.length).toBeGreaterThan(0);

    const uniqueSymbols = new Set(
        companies.map(company => company.symbol)
    );

expect(uniqueSymbols.size).toBe(companies.length);
});


test('Save scraped companies to JSON', async ({ page }) => {
    const result =
        await scrapeAllCompanies(page);

    const companies =
        result.companies;

    await saveCompanies(
        companies
    );

    console.log(
        'Saved companies:',
        companies.length
    );

    expect(
        companies.length
    ).toBeGreaterThan(0);
});


test('Check duplicate company symbols', async ({ page }) => {
    const result =
        await scrapeAllCompanies(page);

    const companies =
        result.companies;

    const uniqueSymbols = new Set(
        companies.map(
            company => company.symbol
        )
    );

    const duplicateCount =
        companies.length - uniqueSymbols.size;

    console.log('Total companies:', companies.length);
    console.log('Unique symbols:', uniqueSymbols.size);
    console.log('Duplicate symbols:', duplicateCount);

    expect(duplicateCount).toBe(0);
});


test('Upsert companies without duplicates', async () => {
    const testDirectory =
        await fs.mkdtemp(
            path.join(
                os.tmpdir(),
                'companiesmarketcap-test-'
            )
        );

    const testFilePath =
        path.join(
            testDirectory,
            'companies.json'
        );

    const existingCompanies = [
        {
            rank: 1,
            name: 'NVIDIA',
            symbol: 'NVDA',
            country: 'USA',
            lastUpdated: '2026-09-25T11:00:25.477Z',
        },
    ];

    await fs.writeFile(
        testFilePath,
        JSON.stringify(
            existingCompanies,
            null,
            4
        ),
        'utf-8'
    );

    const updatedCompany = {
        ...existingCompanies[0],
        name: 'NVIDIA Updated',
    };

    const newCompany = {
        rank: 2,
        name: 'Test Company',
        symbol: 'TEST',
        country: 'Test Country',
        lastUpdated: new Date().toISOString(),
    };

    const result = await upsertCompanies(
        [
            updatedCompany,
            newCompany,
        ],
        testFilePath
    );

    const uniqueSymbols =
        new Set(
            result.map(
                company => company.symbol
            )
        );

    console.log(
        'Companies before:',
        existingCompanies.length
    );

    console.log(
        'Companies after:',
        result.length
    );

    console.log(
        'Unique symbols:',
        uniqueSymbols.size
    );

    expect(result.length).toBe(2);

    expect(uniqueSymbols.size).toBe(2);

    expect(
        result.find(
            company =>
                company.symbol === 'NVDA'
        )?.name
    ).toBe('NVIDIA Updated');

    expect(
        result.find(
            company =>
                company.symbol === 'TEST'
        )?.name
    ).toBe('Test Company');

    await fs.rm(
        testDirectory,
        {
            recursive: true,
            force: true,
        }
    );
});


test('Save ranking history without duplicate records', async () => {
    const testDirectory =
        await fs.mkdtemp(
            path.join(
                os.tmpdir(),
                'companiesmarketcap-history-test-'
            )
        );

    const testFilePath =
        path.join(
            testDirectory,
            'ranking_history.json'
        );

    const companies = [
        {
            rank: 1,
            name: 'NVIDIA',
            symbol: 'NVDA',
            country: 'USA',
            lastUpdated: '2026-09-25T12:00:00.000Z',
        },
        {
            rank: 2,
            name: 'Apple',
            symbol: 'AAPL',
            country: 'USA',
            lastUpdated: '2026-09-25T12:00:00.000Z',
        },
    ];

    // First run
    await saveRankingHistory(
        companies,
        '2026-09-25',
        testFilePath
    );

    let history =
        JSON.parse(
            await fs.readFile(
                testFilePath,
                'utf-8'
            )
        );

    console.log(
        'After first run:',
        history.length
    );

    expect(history.length).toBe(2);

    // Same date - second run
    await saveRankingHistory(
        companies,
        '2026-09-25',
        testFilePath
    );

    history =
        JSON.parse(
            await fs.readFile(
                testFilePath,
                'utf-8'
            )
        );

    console.log(
        'After same-day rerun:',
        history.length
    );

    expect(history.length).toBe(2);

    // New date
    await saveRankingHistory(
        companies,
        '2026-09-26',
        testFilePath
    );

    history =
        JSON.parse(
            await fs.readFile(
                testFilePath,
                'utf-8'
            )
        );

    console.log(
        'After next-day run:',
        history.length
    );

    expect(history.length).toBe(4);

    const uniqueKeys =
        new Set(
            history.map(
                (record: {
                    date: string;
                    symbol: string;
                }) =>
                    `${record.date}_${record.symbol}`
            )
        );

    console.log(
        'Unique date + symbol:',
        uniqueKeys.size
    );

    expect(uniqueKeys.size).toBe(4);

    await fs.rm(
        testDirectory,
        {
            recursive: true,
            force: true,
        }
    );
});


test('Save scraped companies to master and ranking history', async ({ page }) => {
    const result =
        await scrapeAllCompanies(page);

    const companies =
        result.companies;

    const metadata =
        result.metadata;

    const mergedCompanies =
        await upsertCompanies(
            companies
        );

    const currentDate =
        getCurrentDateTime().slice(0, 10);

    await saveRankingHistory(
        companies,
        currentDate
    );

    await saveScrapeMetadata(
        metadata
    );

    console.log(
        'Scraped companies:',
        companies.length
    );

    console.log(
        'Master companies:',
        mergedCompanies.length
    );

    console.log(
        'Ranking history date:',
        currentDate
    );

    // Dynamic validation
    expect(companies.length).toBeGreaterThan(0);

    expect(
        mergedCompanies.length
    ).toBeGreaterThanOrEqual(
        companies.length
    );
});


test('Validate ranking history JSON', async () => {
    const historyFilePath =
        path.resolve(
            'data',
            'ranking_history.json'
        );

    const fileContent =
        await fs.readFile(
            historyFilePath,
            'utf-8'
        );

    const history = JSON.parse(
        fileContent
    ) as {
        date: string;
        rank: number;
        name: string;
        symbol: string;
        country: string;
    }[];

    expect(history.length).toBeGreaterThan(0);

    const uniqueKeys =
        new Set(
            history.map(
                record =>
                    `${record.date}_${record.symbol}`
            )
        );

    console.log(
        'Ranking history records:',
        history.length
    );

    console.log(
        'Unique date + symbol:',
        uniqueKeys.size
    );

    console.log(
        'First record:',
        history[0]
    );

    console.log(
        'Last record:',
        history[history.length - 1]
    );

    // No duplicate date + symbol
    expect(uniqueKeys.size).toBe(
        history.length
    );

    // Get latest ranking date dynamically
    const latestDate =
        history
            .map(record => record.date)
            .sort()
            .at(-1);

    expect(latestDate).toBeDefined();

    // All records for latest ranking date
    const latestRecords =
        history.filter(
            record =>
                record.date === latestDate
        );

    console.log(
        'Latest ranking date:',
        latestDate
    );

    console.log(
        'Latest ranking records:',
        latestRecords.length
    );

    // Latest scrape must contain data
    expect(
        latestRecords.length
    ).toBeGreaterThan(0);

    // Validate required fields
    expect(
        latestRecords.every(
            record =>
                record.rank > 0 &&
                record.name.trim().length > 0 &&
                record.symbol.trim().length > 0
        )
    ).toBe(true);
});


test('Save scrape metadata', async () => {
    const testDirectory =
        await fs.mkdtemp(
            path.join(
                os.tmpdir(),
                'companiesmarketcap-metadata-test-'
            )
        );

    const testFilePath =
        path.join(
            testDirectory,
            'scrape_metadata.json'
        );

    const metadata = {
        source: 'CompaniesMarketCap',
        ranking: 'Market Cap',
        lastRun: new Date().toISOString(),
        pagesScraped: 114,
        recordsScraped: 11340,
        uniqueCompanies: 11340,
        duplicates: 0,
        status: 'success' as const,
    };

    await saveScrapeMetadata(
        metadata,
        testFilePath
    );

    const fileContent =
        await fs.readFile(
            testFilePath,
            'utf-8'
        );

    const savedMetadata =
        JSON.parse(
            fileContent
        );

    console.log(
        'Saved metadata:',
        savedMetadata
    );

    expect(
        savedMetadata.source
    ).toBe('CompaniesMarketCap');

    expect(
        savedMetadata.ranking
    ).toBe('Market Cap');

    expect(
        savedMetadata.lastRun
    ).toBe(metadata.lastRun);

    expect(
        savedMetadata.pagesScraped
    ).toBe(metadata.pagesScraped);

    expect(
        savedMetadata.recordsScraped
    ).toBe(metadata.recordsScraped);

    expect(
        savedMetadata.uniqueCompanies
    ).toBe(metadata.uniqueCompanies);

    expect(
        savedMetadata.duplicates
    ).toBe(metadata.duplicates);

    expect(
        savedMetadata.status
    ).toBe('success');

    await fs.rm(
        testDirectory,
        {
            recursive: true,
            force: true,
        }
    );
});