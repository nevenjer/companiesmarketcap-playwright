// ดึงข้อมูลบริษัทอันดับ 1 ก่อน ยังไม่ทำ 100 rows และยังไม่ทำ JSON
import { Page, Locator, expect } from '@playwright/test';

export class CompaniesMarketCapPage {
    readonly page: Page;
    readonly marketCapOption: Locator;
    readonly companyRows: Locator;
    readonly nextPageLink: Locator;
    readonly privacyDialog: Locator;
    readonly privacyAgreeButton: Locator;

    constructor(page: Page) {
        this.page = page;

        this.marketCapOption = page
            .locator('span.option')
            .filter({ hasText: /^Market Cap$/ });

        this.companyRows = page.locator('table tbody tr');

        this.nextPageLink = page.locator('a.page-link').filter({
            hasText: 'Next 100'
        });

        this.privacyDialog = page.locator('#qc-cmp2-ui');

        this.privacyAgreeButton = this.privacyDialog.getByRole(
            'button',
            { name: 'AGREE', exact: true }
        );

    }

    async open(): Promise<void> {
        await this.page.goto('/');
    }

    async isMarketCapActive(): Promise<boolean> {
        return await this.marketCapOption.evaluate((element) =>
            element.classList.contains('active')
        );
    }

    // Step 5 — สร้าง Company object จาก Row แรก
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

        const name = (
            await cells.nth(2).locator('.company-name').innerText()
        ).trim();

        const symbol = (
            await cells.nth(2).locator('.company-code').innerText()
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

    async getCompaniesFromCurrentPage(): Promise<
        {
            rank: number;
            name: string;
            symbol: string;
            country: string;
        }[]
    > {
        const rows = this.companyRows;


        const companies = await rows.evaluateAll((rowElements) => {
            const results: {
                rank: number;
                name: string;
                symbol: string;
                country: string;
            }[] = [];

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
                const name = nameElement?.textContent?.trim() ?? '';
                const symbol = symbolElement?.textContent?.trim() ?? '';
                const country = cells[7].textContent?.trim() ?? '';

                results.push({
                    rank,
                    name,
                    symbol,
                    country,
                });
            }

            return results;
        });

        return companies;
    }

    async goToNextPage(): Promise<void> {
        await this.acceptPrivacy();

        const nextPageUrl =
            await this.nextPageLink.getAttribute('href');

        if (!nextPageUrl) {
            throw new Error('Next page URL was not found.');
        }

        const nextPageAbsoluteUrl =
            new URL(nextPageUrl, this.page.url()).href;

        const maxRetries = 3;

        for (let attempt = 1; attempt <= maxRetries; attempt++) {
            try {
                console.log(
                    `Navigating to next page (attempt ${attempt}/${maxRetries}):`,
                    nextPageAbsoluteUrl
                );

                await this.page.goto(nextPageAbsoluteUrl, {
                    waitUntil: 'domcontentloaded',
                    timeout: 30_000,
                });

                return;

            } catch (error) {
                const message =
                    error instanceof Error
                        ? error.message
                        : String(error);

                console.warn(
                    `Navigation failed (attempt ${attempt}/${maxRetries}): ${message}`
                );

                if (attempt === maxRetries) {
                    throw error;
                }

                const delay = attempt * 2_000;

                console.log(
                    `Retrying in ${delay / 1000} seconds...`
                );

                await this.page.waitForTimeout(delay);
            }
        }
    }

    async inspectPrivacyDialog(): Promise<void> {
        console.log(
            'Privacy dialog count:',
            await this.privacyDialog.count()
        );

        if (await this.privacyDialog.count() > 0) {
            console.log(
                'Privacy dialog visible:',
                await this.privacyDialog.first().isVisible()
            );

            const buttons = this.privacyDialog.locator('button');

            console.log(
                'Privacy buttons:',
                await buttons.count()
            );

            for (let i = 0; i < await buttons.count(); i++) {
                console.log(
                    `Privacy button ${i}:`,
                    JSON.stringify(
                        (await buttons.nth(i).innerText()).trim()
                    )
                );
            }
        }
    }

    async acceptPrivacy(): Promise<void> {
        if (await this.privacyDialog.isVisible()) {
            await this.privacyAgreeButton.click();

            await this.privacyDialog.waitFor({
                state: 'hidden',
            });
        }
    }

    async hasNextPage(): Promise<boolean> {
        await this.acceptPrivacy();

        return await this.nextPageLink.count() > 0;
    }

}



