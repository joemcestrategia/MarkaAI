
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
    const profId = '5628104f-4547-4ebf-861c-a26d51460b27'; // Edmara
    console.log(`Buscando agendamentos para Edmara no dia 2026-07-04...`);
    
    let url = `${SUPABASE_URL}/rest/v1/appointments?select=id,scheduled_at,duration_min,status`;
    url += `&professional_id=eq.${profId}`;
    url += `&scheduled_at=gte.2026-07-04T00:00:00Z`;
    url += `&scheduled_at=lte.2026-07-04T23:59:59Z`;
    url += `&status=neq.cancelado&status=neq.rejeitado&status=neq.recusado&status=neq.excluido`;

    const res = await fetch(url, {
        headers: {
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${SUPABASE_KEY}`
        }
    });
    const appointments = await res.json();
    console.log("Agendamentos Edmara:", JSON.stringify(appointments, null, 2));
}

main();
