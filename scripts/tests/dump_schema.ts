import { Client } from "https://deno.land/x/postgres@v0.17.0/mod.ts";
import { load } from "https://deno.land/std@0.208.0/dotenv/mod.ts"

const env = await load({ envPath: "./scripts/tests/.env" })
const DB_URL = env["DATABASE_URL"] || Deno.env.get("DATABASE_URL")

async function run() {
  const client = new Client(DB_URL);
  await client.connect();
  
  const sql = `
    SELECT table_name, column_name, data_type 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
    ORDER BY table_name, ordinal_position;
  `;
  
  const result = await client.queryArray(sql);
  
  let output = "=== CURRENT SCHEMA SNAPSHOT ===\n\n";
  const tables = new Map();
  for (const row of result.rows) {
    const [tableName, columnName, dataType] = row;
    if (!tables.has(tableName)) {
      tables.set(tableName, []);
    }
    tables.get(tableName).push(`${columnName} (${dataType})`);
  }

  for (const [table, columns] of tables.entries()) {
    output += `Table: ${table}\n`;
    for (const col of columns) {
      output += `  - ${col}\n`;
    }
    output += "\n";
  }

  await Deno.writeTextFile("scripts/tests/current_schema_snapshot.txt", output);
  console.log("Schema dumped to scripts/tests/current_schema_snapshot.txt");
  
  await client.end();
}

run();
