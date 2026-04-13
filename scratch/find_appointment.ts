
const SUPABASE_URL = 'https://uhccgcojwqvkfyzrmebv.supabase.co';
const ANON_KEY = 'sb_publishable_gmX2ol9O_y3XjHt8bJ-NgQ_b2nfxFmR';
const CNPJ = "41027409000189";

async function findRecentAppointment() {
  console.log("🔍 Buscando agendamento recente para Itabirito...");
  
  // Primeiro buscamos o shop_id pelo CNPJ
  const shopResp = await fetch(`${SUPABASE_URL}/rest/v1/shops?cnpj=eq.${CNPJ}&select=id`, {
    headers: { 'apikey': ANON_KEY, 'Authorization': `Bearer ${ANON_KEY}` }
  });
  
  const shops = await shopResp.json();
  if (!shops || shops.length === 0) {
    console.error("❌ Loja não encontrada com esse CNPJ.");
    return;
  }
  
  const shopId = shops[0].id;
  console.log(`✅ Shop ID encontrado: ${shopId}`);

  // Agora buscamos o último agendamento dessa loja
  const apptResp = await fetch(`${SUPABASE_URL}/rest/v1/appointments?shop_id=eq.${shopId}&select=id,client_name,total_value,created_at&order=created_at.desc&limit=1`, {
    headers: { 'apikey': ANON_KEY, 'Authorization': `Bearer ${ANON_KEY}` }
  });
  
  const appts = await apptResp.json();
  if (!appts || appts.length === 0) {
    console.error("❌ Nenhum agendamento encontrado para esta loja.");
    return;
  }

  console.log(`\n🚀 AGENDAMENTO ENCONTRADO:`);
  console.log(`ID: ${appts[0].id}`);
  console.log(`Cliente: ${appts[0].client_name}`);
  console.log(`Valor: R$ ${appts[0].total_value}`);
  console.log(`Data: ${appts[0].created_at}`);
  console.log(`\nCopie o ID acima se quiser que eu emita a nota para este serviço.`);
}

findRecentAppointment();
