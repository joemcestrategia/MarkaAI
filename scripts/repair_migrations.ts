import { readdirSync } from "node:fs";
import { execSync } from "node:child_process";

const migrationsDir = "./supabase/migrations";
const files = readdirSync(migrationsDir).filter(f => f.endsWith(".sql"));

let count = 0;
for (const file of files) {
  const versionMatch = file.match(/^(\d+)_/);
  if (versionMatch) {
    const version = versionMatch[1];
    console.log(`Reparando migration: ${version} (${file})...`);
    try {
      execSync(`npx supabase migration repair --status applied ${version}`, { stdio: 'inherit' });
      count++;
    } catch (e) {
      console.error(`Erro ao reparar migration ${version}`);
    }
  }
}

console.log(`Total reparado: ${count} migrations`);
