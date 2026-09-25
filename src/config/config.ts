export const config = {
    baseUrl: 'https://companiesmarketcap.com',
    ranking: 'Market Cap',

    paths: {
        companies: 'data/companies.json',
        rankingHistory: 'data/ranking_history.json',
        metadata: 'data/scrape_metadata.json',
    },

    scraper: {
        pageSize: 100,
        startPage: 1,
    },
};