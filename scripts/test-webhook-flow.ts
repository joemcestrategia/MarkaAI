import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// Supabase config
const SUPABASE_URL = 'https://uhccgcojwqvkfyzrmebv.supabase.co';
const EVOLUTION_API_URL = 'http://187.127.26.94:8080';
const EVOLUTION_API_KEY = 'markaai2026';

const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjYwNDgsImV4cCI6MjA4OTU0MjA0OH0.bK3UsISxVqw5gJktnBkMwmh7Swb17eV-UgD2Ia9e_PA';
const supabase = createClient(SUPABASE_URL, anonKey);

async function run() {
  const instanceName = `shop_290d91b6-7519-4856-96dc-bcda3fd3b9f9_webhook`;
  
  await fetch(`${EVOLUTION_API_URL}/instance/delete/${instanceName}`, {
      method: 'DELETE', headers: { 'apikey': EVOLUTION_API_KEY }
  }).catch(()=>null);
  await new Promise(r => setTimeout(r, 2000));
  
  console.log("Criando instância com Webhook pre-configurado...");
  
  const webhookUrl = `${SUPABASE_URL}/functions/v1/whatsapp-webhook`;
  
  const createRes = await fetch(`${EVOLUTION_API_URL}/instance/create`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'apikey': EVOLUTION_API_KEY },
    body: JSON.stringify({
      instanceName,
      qrcode: true,
      integration: "WHATSAPP-BAILEYS",
      webhook: {
         url: webhookUrl,
         webhook_by_events: true,
         events: ["QRCODE_UPDATED"]
      }
    })
  });
  
  console.log("CREATE:", await createRes.text());
  
  console.log("Vou ficar consultando a tabela whatsapp_qr_codes na sua DB por 10 segundos com a Anon Key...");
  
  for(let i=0; i<5; i++) {
     await new Promise(r => setTimeout(r, 2000));
     
     // Para isso funcionar com a anonKey, precisamos estar logados ou RLS relaxado
     // Se falhar é pq a tabela não permite leitura publica, mas veremos o erro  
     const { data, error } = await supabase.from('whatsapp_qr_codes')
       .select('*').order('created_at', { ascending: false }).limit(1);
       
     if (error) {
        console.log("Erro ao ler tabela (RLS ou não existe):", error.message);
        break;
     } else if (data && data.length > 0) {
        console.log("-> TEMOS QR NA TABELA!", data[0].shop_id);
     } else {
        console.log("-> 0 QRCodes na tabela ainda...");
     }
  }
}
run();
