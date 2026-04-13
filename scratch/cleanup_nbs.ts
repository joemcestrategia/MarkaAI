const SUPABASE_URL = 'https://uhccgcojwqvkfyzrmebv.supabase.co';
const SERVICE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Mzk2NjA0OCwiZXhwIjoyMDg5NTQyMDQ4fQ.nE4lZ0Xn-7TbSV-3qJz5mkCOi1vB9yY7dM4ZYt9VB-A';

async function cleanupConfig() {
  const shopId = '290d91b6-7519-4856-96dc-bcda3fd3b9f9';
  console.log('🧹 Limpando NBS e forçando configuração de sucesso para a loja:', shopId);
  
  const resp = await fetch(`${SUPABASE_URL}/rest/v1/nfse_config?shop_id=eq.${shopId}`, {
    method: 'PATCH',
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      codigo_nbs: null, 
      codigo_servico_lc116: '60101',
      codigo_tributacao_municipio: '960250100',
      aliquota_iss: 2.01,
      ativo: true
    })
  });

  if (resp.ok) {
    console.log('✅ Configuração limpa com sucesso! NBS removido.');
  } else {
    console.error('❌ Erro ao limpar configuração:', resp.status, await resp.text());
  }
}

cleanupConfig();
