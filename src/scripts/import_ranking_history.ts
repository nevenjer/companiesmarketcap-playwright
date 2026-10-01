import sql from "mssql";
import fs from "fs/promises";
import path from "path";

interface RankingHistory {
  rank: number;
  name: string;
  symbol: string;
  country: string | null;
  date: string;
}

// Read SQL Server password from environment
const password = process.env.MSSQL_SA_PASSWORD;

if (!password) {
  throw new Error("MSSQL_SA_PASSWORD is not set.");
}

const config: sql.config = {
  server: "localhost",
  port: 8888,
  database: "CompaniesMarketCapDB",
  user: "sa",
  password,
  options: {
    encrypt: false,
    trustServerCertificate: true,
  },
};

async function main(): Promise<void> {
  // Load ranking history JSON
  const filePath = path.resolve("data/ranking_history.json");
  const file = await fs.readFile(filePath, "utf-8");
  const rankingHistory: RankingHistory[] = JSON.parse(file);

  console.log(`Loaded ${rankingHistory.length} ranking records`);

  // Connect to SQL Server
  const pool = await sql.connect(config);

  console.log("Connected to SQL Server");

  let inserted = 0;

  // Insert ranking history records
  for (const record of rankingHistory) {
    await pool
      .request()
      .input("rank", sql.Int, record.rank)
      .input("name", sql.NVarChar(255), record.name)
      .input("symbol", sql.NVarChar(100), record.symbol)
      .input("country", sql.NVarChar(100), record.country)
      .input("ranking_date", sql.Date, record.date)
      .query(`
        INSERT INTO dbo.CompanyRankingHistory
        (
          rank,
          name,
          symbol,
          country,
          ranking_date
        )
        VALUES
        (
          @rank,
          @name,
          @symbol,
          @country,
          @ranking_date
        );
      `);

    inserted++;
  }

  console.log(`Inserted: ${inserted}`);
  console.log(`Total processed: ${rankingHistory.length}`);

  // Close connection
  await pool.close();

  console.log("Database connection closed");
}

main().catch((error) => {
  console.error("Import failed:", error);
  process.exit(1);
});