import { Page } from '@playwright/test';

import { CompaniesMarketCapPage } from '../pages/CompaniesMarketCapPage';

import {
    Company,
    ScrapeMetadata,
} from '../types/company';

export interface ScrapeResult {
    companies: Company[];
    metadata: ScrapeMetadata;
}

export async function scrapeAllCompanies(
    page: Page
): Promise<ScrapeResult> {
    const companiesMarketCapPage =
        new CompaniesMarketCapPage(page);

    await companiesMarketCapPage.open();

    const isMarketCapActive =
        await companiesMarketCapPage.isMarketCapActive();

    if (!isMarketCapActive) {
        throw new Error(
            'Market Cap ranking is not active.'
        );
    }

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

    const lastUpdated =
        new Date().toISOString();

    const companies =
        allCompanies.map((company) => ({
            ...company,
            lastUpdated,
        }));

    const uniqueSymbols =
        new Set(
            companies.map(
                company => company.symbol
            )
        );

    const duplicates =
        companies.length -
        uniqueSymbols.size;

    const metadata: ScrapeMetadata = {
        source: 'CompaniesMarketCap',
        ranking: 'Market Cap',
        lastRun: lastUpdated,
        pagesScraped: pageNumber,
        recordsScraped: companies.length,
        uniqueCompanies: uniqueSymbols.size,
        duplicates,
        status: 'success',
    };

    return {
        companies,
        metadata,
    };
}