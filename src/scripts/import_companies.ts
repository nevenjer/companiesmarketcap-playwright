import sql from "mssql";
import fs from "fs/promises";
import path from "path";

interface Company {
  rank: number;
  name: string;
  symbol: string;
  country: string | null;
  lastUpdated: string;
}

const config: sql.config = {
  server: "localhost",
  port: 8888,
  database: "CompaniesMarketCapDB",
  user: "sa",
  password: "YOUR_SQL_PASSWORD",
  options: {
    encrypt: false,
    trustServerCertificate: true,
  },
};

async function main(): Promise<void> {
  // Load JSON data
  const filePath = path.resolve("data/companies.json");
  const file = await fs.readFile(filePath, "utf-8");
  const companies: Company[] = JSON.parse(file);

  console.log(`Loaded ${companies.length} companies`);

  // Connect to SQL Server
  const pool = await sql.connect(config);

  console.log("Connected to SQL Server");

  let inserted = 0;
  let updated = 0;

  // Process company records
  for (const company of companies) {
    const result = await pool
      .request()
      .input("rank", sql.Int, company.rank)
      .input("name", sql.NVarChar(255), company.name)
      .input("symbol", sql.NVarChar(100), company.symbol)
      .input("country", sql.NVarChar(100), company.country)
      .input(
        "last_updated",
        sql.DateTime2(3),
        new Date(company.lastUpdated)
      )
      .query(`
        IF EXISTS (
          SELECT 1
          FROM dbo.Company
          WHERE symbol = @symbol
        )
        BEGIN
          UPDATE dbo.Company
          SET
            rank = @rank,
            name = @name,
            country = @country,
            last_updated = @last_updated
          WHERE symbol = @symbol;

          SELECT 'updated' AS action;
        END
        ELSE
        BEGIN
          INSERT INTO dbo.Company
          (
            rank,
            name,
            symbol,
            country,
            last_updated
          )
          VALUES
          (
            @rank,
            @name,
            @symbol,
            @country,
            @last_updated
          );

          SELECT 'inserted' AS action;
        END
      `);

    const action = result.recordset[0]?.action;

    if (action === "inserted") {
      inserted++;
    } else if (action === "updated") {
      updated++;
    }
  }

  console.log(`Inserted: ${inserted}`);
  console.log(`Updated: ${updated}`);
  console.log(`Total processed: ${companies.length}`);

  // Close connection
  await pool.close();

  console.log("Database connection closed");
}

main().catch((error) => {
  console.error("Import failed:", error);
  process.exit(1);
});