
const SUPABASE_URL = 'https://uhccgcojwqvkfyzrmebv.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjYwNDgsImV4cCI6MjA4OTU0MjA0OH0.bK3UsISxVqw5gJktnBkMwmh7Swb17eV-UgD2Ia9e_PA';

async function query(table, select = '*', filters = {}) {
    let url = `${SUPABASE_URL}/rest/v1/${table}?select=${select}`;
    for (const [key, value] of Object.entries(filters)) {
        url += `&${key}=${encodeURIComponent(value)}`;
    }
    const res = await fetch(url, {
        headers: {
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${SUPABASE_KEY}`
        }
    });
    return res.json();
}

async function main() {
    const s1 = '3257d77d-d3be-49f8-9ac1-17263a2771f0';
    const s2 = 'e732bbf7-38f9-4eb5-8bf5-8fcb3a462b9a';
    console.log(`Buscando serviços ${s1} e ${s2}...`);
    const services = await query('services', 'id, name, duration_min', { 'id': `in.(${s1},${s2})` });
    console.log("Serviços:", JSON.stringify(services, null, 2));
}

main();
