
const SUPABASE_URL = 'https://uhccgcojwqvkfyzrmebv.supabase.co';
const SUPABASE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjYwNDgsImV4cCI6MjA4OTU0MjA0OH0.bK3UsISxVqw5gJktnBkMwmh7Swb17eV-UgD2Ia9e_PA';

async function main() {
    const profId = 'b9b34720-cd68-4a05-bb56-3236867f4e03';
    console.log(`Buscando agendamentos para Dionathan no dia 2026-07-04 para migração...`);
    
    let url = `${SUPABASE_URL}/rest/v1/appointments?select=id,scheduled_at,client_name`;
    url += `&professional_id=eq.${profId}`;
    url += `&scheduled_at=gte.2026-07-04T00:00:00Z`;
    url += `&scheduled_at=lte.2026-07-04T23:59:59Z`;

    const res = await fetch(url, {
        headers: {
            'apikey': SUPABASE_KEY,
            'Authorization': `Bearer ${SUPABASE_KEY}`
        }
    });
    const appointments = await res.json();
    console.log("Agendamentos encontrados:", appointments.length);

    for (const appt of appointments) {
        const oldTime = appt.scheduled_at;
        const date = new Date(oldTime);
        // Adiciona 3 horas
        date.setUTCHours(date.getUTCHours() + 3);
        const newTime = date.toISOString();
        
        console.log(`Atualizando ${appt.id} (${appt.client_name}): ${oldTime} -> ${newTime}`);
        
        const updateRes = await fetch(`${SUPABASE_URL}/rest/v1/appointments?id=eq.${appt.id}`, {
            method: 'PATCH',
            headers: {
                'apikey': SUPABASE_KEY,
                'Authorization': `Bearer ${SUPABASE_KEY}`,
                'Content-Type': 'application/json',
                'Prefer': 'return=minimal'
            },
            body: JSON.stringify({
                scheduled_at: newTime
            })
        });
        
        if (updateRes.ok) {
            console.log(`✅ OK`);
        } else {
            console.log(`❌ Erro: ${updateRes.statusText}`);
        }
    }
}

main();
