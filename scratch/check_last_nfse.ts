const SUPABASE_URL = 'https://uhccgcojwqvkfyzrmebv.supabase.co';
const SERVICE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Mzk2NjA0OCwiZXhwIjoyMDg5NTQyMDQ4fQ.nE4lZ0Xn-7TbSV-3qJz5mkCOi1vB9yY7dM4ZYt9VB-A';

async function checkLastEmission() {
  const shopId = '290d91b6-7519-4856-96dc-bcda3fd3b9f9';
  console.log('🔍 Buscando a última nota emitida pela loja:', shopId);
  
  const resp = await fetch(`${SUPABASE_URL}/rest/v1/nfse_emissoes?shop_id=eq.${shopId}&status=eq.autorizada&select=*&order=created_at.desc&limit=1`, {
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`
    }
  });

  if (resp.ok) {
    const data = await resp.json();
    console.log('📄 Detalhes da última nota:', JSON.stringify(data, null, 2));
  } else {
    console.error('❌ Erro:', resp.status, await resp.text());
  }
}

checkLastEmission();
