export interface Company {
    rank: number;
    name: string;
    symbol: string;
    country: string;
    lastUpdated: string;
}

export interface RankingHistory {
    rank: number;
    name: string;
    symbol: string;
    country: string;
    date: string;
}

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