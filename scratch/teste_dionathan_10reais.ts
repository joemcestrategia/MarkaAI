const SUPABASE_URL = 'https://uhccgcojwqvkfyzrmebv.supabase.co';
const SERVICE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Mzk2NjA0OCwiZXhwIjoyMDg5NTQyMDQ4fQ.nE4lZ0Xn-7TbSV-3qJz5mkCOi1vB9yY7dM4ZYt9VB-A';
const ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjYwNDgsImV4cCI6MjA4OTU0MjA0OH0.bK3UsISxVqw5gJktnBkMwmh7Swb17eV-UgD2Ia9e_PA';

async function main() {
  const shopId = '290d91b6-7519-4856-96dc-bcda3fd3b9f9';
  
  console.log('--- Iniciando Teste de R$ 10,00 para Dionathan ---');
  
  // 1. Atualizar configuração da loja para garantir o sucesso
  console.log('Atualizando configuração da loja...');
  await fetch(`${SUPABASE_URL}/rest/v1/nfse_config?shop_id=eq.${shopId}`, {
    method: 'PATCH',
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      codigo_servico_lc116: '60101',
      codigo_tributacao_municipio: '960250100',
      aliquota_iss: 2.01,
      proximo_numero_rps: 2 // Próximo após o teste manual nº 1
    })
  });

  // 2. Criar agendamento completo
  console.log('Criando agendamento de teste...');
  const appt = {
    shop_id: shopId,
    client_name: 'Dionathan Arlindo Iannini',
    client_user_cpf: '09142583624',
    total_value: 10.00,
    service_name: 'TESTE DE INTEGRACAO SISTEMA - VALOR 10 REAIS',
    status: 'completed',
    scheduled_at: new Date().toISOString()
  };

  const resp = await fetch(`${SUPABASE_URL}/rest/v1/appointments`, {
    method: 'POST',
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'return=representation'
    },
    body: JSON.stringify(appt)
  });

  if (!resp.ok) {
    console.error('Erro ao criar agendamento:', resp.status, await resp.text());
    return;
  }

  const data = await resp.json();
  const newAppt = data[0];
  console.log('Agendamento criado ID:', newAppt.id);

  // 3. Disparar a Edge Function
  console.log('Disparando emissão da NFS-e...');
  const funcResp = await fetch(`${SUPABASE_URL}/functions/v1/emitir-nfse`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${ANON_KEY}`
    },
    body: JSON.stringify({
      appointment_id: newAppt.id,
      shop_id: shopId
    })
  });

  const result = await funcResp.json();
  console.log('Resultado da emissão:');
  console.log(JSON.stringify(result, null, 2));
}

main();
