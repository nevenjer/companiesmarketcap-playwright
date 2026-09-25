import fs from 'node:fs/promises';
import path from 'node:path';

import {
    Company,
    RankingHistory,
    ScrapeMetadata,
} from '../types/company';


const defaultCompaniesFilePath = path.resolve(
    'data',
    'companies.json'
);

export async function loadCompanies(
    filePath: string = defaultCompaniesFilePath
): Promise<Company[]> {
    try {
        const fileContent =
            await fs.readFile(
                filePath,
                'utf-8'
            );

        return JSON.parse(fileContent) as Company[];
    } catch (error: unknown) {
        if (
            error &&
            typeof error === 'object' &&
            'code' in error &&
            error.code === 'ENOENT'
        ) {
            return [];
        }

        throw error;
    }
}

export async function saveCompanies(
    companies: Company[],
    filePath: string = defaultCompaniesFilePath
): Promise<void> {
    await fs.writeFile(
        filePath,
        JSON.stringify(companies, null, 4),
        'utf-8'
    );
}

export async function upsertCompanies(
    newCompanies: Company[],
    filePath: string = defaultCompaniesFilePath
): Promise<Company[]> {
    const existingCompanies =
        await loadCompanies(filePath);

    const companiesBySymbol =
        new Map<string, Company>();

    for (const company of existingCompanies) {
        companiesBySymbol.set(
            company.symbol,
            company
        );
    }

    for (const company of newCompanies) {
        companiesBySymbol.set(
            company.symbol,
            company
        );
    }

    const mergedCompanies =
        Array.from(
            companiesBySymbol.values()
        );

    await saveCompanies(
        mergedCompanies,
        filePath
    );

    return mergedCompanies;
}


export async function saveRankingHistory(
    companies: Company[],
    date: string,
    filePath: string = path.resolve(
        'data',
        'ranking_history.json'
    )
): Promise<void> {
    let history: RankingHistory[] = [];

    try {
        const fileContent =
            await fs.readFile(
                filePath,
                'utf-8'
            );

        history =
            JSON.parse(fileContent) as RankingHistory[];
    } catch (error: unknown) {
        if (
            !(
                error &&
                typeof error === 'object' &&
                'code' in error &&
                error.code === 'ENOENT'
            )
        ) {
            throw error;
        }
    }

    const historyByKey =
        new Map<string, RankingHistory>();

    for (const record of history) {
        const key =
            `${record.date}_${record.symbol}`;

        historyByKey.set(
            key,
            record
        );
    }

    for (const company of companies) {
        const record: RankingHistory = {
            rank: company.rank,
            name: company.name,
            symbol: company.symbol,
            country: company.country,
            date,
        };

        const key =
            `${date}_${company.symbol}`;

        historyByKey.set(
            key,
            record
        );
    }

    const updatedHistory =
        Array.from(
            historyByKey.values()
        );

    await fs.writeFile(
        filePath,
        JSON.stringify(
            updatedHistory,
            null,
            4
        ),
        'utf-8'
    );
}


export async function saveScrapeMetadata(
    metadata: ScrapeMetadata,
    filePath: string = path.resolve(
        'data',
        'scrape_metadata.json'
    )
): Promise<void> {
    await fs.writeFile(
        filePath,
        JSON.stringify(
            metadata,
            null,
            4
        ),
        'utf-8'
    );
}