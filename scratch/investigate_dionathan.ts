
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
    console.log("Buscando profissional Dionathan...");
    const employees = await query('employees', 'id, name, shop_id', { 'name': 'ilike.%Dionathan%' });
    console.log("Profissionais encontrados:", JSON.stringify(employees, null, 2));

    if (employees.length > 0) {
        const prof = employees[0];
        console.log(`Buscando agendamentos para ${prof.name} (${prof.id}) no dia 2026-07-04...`);
        
        // No Supabase REST API, filters are like column=eq.value or column=gte.value
        const appointments = await query('appointments', 'id, scheduled_at, duration_min, status, client_id, service_id', {
            'professional_id': `eq.${prof.id}`,
            'scheduled_at': 'gte.2026-07-04T00:00:00Z',
            'scheduled_at': 'lte.2026-07-04T23:59:59Z',
            'status': 'not.in.(cancelado,rejeitado,recusado,excluido)'
        });
        // Note: The object key override above is a problem. Let's fix the query logic.
    }
}

async function mainFixed() {
    console.log("Buscando profissional Dionathan...");
    const employees = await query('employees', 'id, name, shop_id', { 'name': 'ilike.%Dionathan%' });
    console.log("Profissionais encontrados:", JSON.stringify(employees, null, 2));

    if (employees.length > 0) {
        const prof = employees[0];
        console.log(`Buscando agendamentos para ${prof.name} (${prof.id}) no dia 2026-07-04...`);
        
        let url = `${SUPABASE_URL}/rest/v1/appointments?select=id,scheduled_at,duration_min,status,client_id,service_id`;
        url += `&professional_id=eq.${prof.id}`;
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
        console.log("Agendamentos encontrados:", JSON.stringify(appointments, null, 2));
        
        console.log("Buscando configuração da loja...");
        const shop = await query('shops', 'config, configured_holidays', { 'id': `eq.${prof.shop_id}` });
        console.log("Configuração da loja:", JSON.stringify(shop, null, 2));
    }
}

mainFixed();
