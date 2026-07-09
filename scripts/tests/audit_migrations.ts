import * as fs from "fs";

const snapshotLines = fs.readFileSync("scripts/tests/current_schema_snapshot_utf8.txt", "utf-8").split("\n");
const schema = new Map<string, Set<string>>(); // table -> set of columns

for (let i = 1; i < snapshotLines.length; i++) {
    const line = snapshotLines[i].trim();
    if (!line) continue;
    const parts = line.split(",");
    const table = parts[0];
    const column = parts[1];
    if (!schema.has(table)) {
        schema.set(table, new Set());
    }
    schema.get(table).add(column);
}

const pendingFiles = fs.readFileSync("scripts/tests/pending_migrations_utf8.txt", "utf-8").split("\n").map(s => s.trim()).filter(s => s.length > 0);

const confirmed = [];
const suspicious = [];
const ambiguous = [];

for (const file of pendingFiles) {
    const content = fs.readFileSync(`supabase/migrations/${file}`, "utf-8").toLowerCase();
    
    // Extract tables created
    const createTableRegex = /create table\s+if not exists\s+([a-z0-9_]+)/g;
    let match;
    let createdTables = [];
    while ((match = createTableRegex.exec(content)) !== null) {
        createdTables.push(match[1].replace('public.', ''));
    }
    
    // Extract columns added
    const alterTableRegex = /alter table\s+(?:public\.)?([a-z0-9_]+)\s+add column\s+(?:if not exists\s+)?([a-z0-9_]+)/g;
    let addedColumns = [];
    while ((match = alterTableRegex.exec(content)) !== null) {
        addedColumns.push({ table: match[1], column: match[2] });
    }

    if (createdTables.length === 0 && addedColumns.length === 0) {
        ambiguous.push(file);
        continue;
    }

    let isConfirmed = true;
    let isSuspicious = false;

    for (const table of createdTables) {
        if (!schema.has(table)) {
            isConfirmed = false;
            isSuspicious = true;
            break;
        }
    }

    if (!isSuspicious) {
        for (const { table, column } of addedColumns) {
            if (!schema.has(table) || !schema.get(table).has(column)) {
                isConfirmed = false;
                isSuspicious = true;
                break;
            }
        }
    }

    if (isSuspicious) {
        suspicious.push(file);
    } else if (isConfirmed) {
        confirmed.push(file);
    }
}

let md = "# Resultado da Auditoria de Migrations Pendentes\n\n";

md += "## ðŸŸ¢ CONFIRMADAS\nEssas migrations tÃªm estruturas que jÃ¡ existem no banco (seguro marcar como applied).\n";
for (const f of confirmed) { md += `- ${f}\n`; }
if(confirmed.length === 0) md += "- Nenhuma\n";

md += "\n## ðŸ”´ SUSPEITAS\nEssas migrations descrevem tabelas ou colunas que NÃƒO existem no banco atual (NÃƒO marcar como applied).\n";
for (const f of suspicious) { md += `- ${f}\n`; }
if(suspicious.length === 0) md += "- Nenhuma\n";

md += "\n## ðŸŸ¡ AMBÃGUAS\nEssas migrations nÃ£o criam tabelas nem adicionam colunas explÃ­citas no formato esperado. Geralmente sÃ£o triggers, RPCs, policies ou inserts.\n";
for (const f of ambiguous) { md += `- ${f}\n`; }
if(ambiguous.length === 0) md += "- Nenhuma\n";

fs.writeFileSync("scripts/tests/audit_report.md", md);
console.log("Audit complete. See scripts/tests/audit_report.md");
