const EVOLUTION_API_URL = 'http://187.127.26.94:8080';
const EVOLUTION_API_KEY = 'markaai2026';
const instanceName = 'shop_290d91b6-7519-4856-96dc-bcda3fd3b9f9';

async function run() {
  console.log("Deletando instância antiga...");
  try {
    await fetch(`${EVOLUTION_API_URL}/instance/delete/${instanceName}`, {
      method: 'DELETE',
      headers: { 'apikey': EVOLUTION_API_KEY }
    });
  } catch (e) {}

  await new Promise(r => setTimeout(r, 2000));

  console.log("Criando instância nova sem websocket config (default)...");
  const createRes = await fetch(`${EVOLUTION_API_URL}/instance/create`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'apikey': EVOLUTION_API_KEY
    },
    body: JSON.stringify({
      instanceName,
      qrcode: true,
      integration: "WHATSAPP-BAILEYS",
    })
  });
  
  const createData = await createRes.json();
  console.log("CREATE:", JSON.stringify(createData));

  // O websocket deles retornou 404. Significa que eles não suportam isso lá no servidor hospedado.
  // Vamos fazer polling diretamente no servidor Node.
  console.log("Vamos testar o polling via REST (5 tentativas) em 15 segundos");
  
  for(let i=0; i<5; i++) {
     await new Promise(r => setTimeout(r, 3000));
     console.log(`Tentativa ${i+1}`);
     
     // 1. Tentar GET /instance/connect
     const r1 = await fetch(`${EVOLUTION_API_URL}/instance/connect/${instanceName}`, {
        headers: { 'apikey': EVOLUTION_API_KEY }
     });
     const d1 = await r1.json().catch(()=>null);
     
     // 2. Tentar GET /instance/connectionState
     const r2 = await fetch(`${EVOLUTION_API_URL}/instance/connectionState/${instanceName}`, {
        headers: { 'apikey': EVOLUTION_API_KEY }
     });
     const d2 = await r2.json().catch(()=>null);

     console.log(" -> CONNECT:", JSON.stringify(d1).substring(0, 50));
     console.log(" -> STATE:", JSON.stringify(d2));
     
     if (d1 && d1.base64) console.log(" ACHOU QR CODE NO CONNECT!");
  }
}

run();
