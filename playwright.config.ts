import { defineConfig } from '@playwright/test';

export default defineConfig({
    testDir: './tests',

    use: {
        baseURL: 'https://companiesmarketcap.com',
        headless: false,
    },

    timeout: 180_000,

    expect: {
        timeout: 10_000,
    },

    reporter: 'list',
});