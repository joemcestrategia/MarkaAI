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

  console.log("Criando instância nova com websockets ativos...");
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
      websocket: {
        enabled: true,
        events: ["QRCODE_UPDATED", "CONNECTION_UPDATE", "MESSAGES_UPSERT"]
      }
    })
  });
  
  const createData = await createRes.json();
  console.log("CREATE:", JSON.stringify(createData));

  console.log("Conectando ao websocket...");
  const wsUrl = `ws://187.127.26.94:8080/${instanceName}/socketchannel`;
  
  const ws = new WebSocket(wsUrl);

  ws.onopen = () => console.log("WebSocket Aberto!");
  ws.onmessage = (msg) => {
    try {
      const data = JSON.parse(msg.data);
      console.log(" EVENTO WSS CHEGOU:", data.event);
      if (data.event === "qrcode.updated") {
         console.log(" TEMOS QRCODE DA EVOLUTION!");
         ws.close();
      }
    } catch(e) {
      console.log("WS Data BRUTO:", msg.data);
    }
  };
  ws.onerror = (e) => console.log("WS Error:", e);
  ws.onclose = () => console.log("WS Fechado");

  // Mantém script rodando por 20 segundos para ver se cai mensagem
  await new Promise(r => setTimeout(r, 20000));
  ws.close();
}

run();
