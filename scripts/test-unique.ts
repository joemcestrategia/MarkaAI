const EVOLUTION_API_URL = 'http://187.127.26.94:8080';
const EVOLUTION_API_KEY = 'markaai2026';
const ts = Date.now();
const instanceName = `test_shop_${ts}`;

async function run() {
  console.log(`Criando nova instancia: ${instanceName}`);
  const createRes = await fetch(`${EVOLUTION_API_URL}/instance/create`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'apikey': EVOLUTION_API_KEY },
    body: JSON.stringify({
      instanceName,
      qrcode: true,
      integration: "WHATSAPP-BAILEYS"
    })
  });
  
  const createData = await createRes.json();
  console.log("CREATE:", JSON.stringify(createData).substring(0, 50));

  console.log("Polling fetchInstances...");
  for(let i=0; i<6; i++) {
     await new Promise(r => setTimeout(r, 3000));
     const r1 = await fetch(`${EVOLUTION_API_URL}/instance/fetchInstances?instanceName=${instanceName}&fetchQrcode=true`, {
        headers: { 'apikey': EVOLUTION_API_KEY }
     });
     
     const text = await r1.text();
     const obj = JSON.parse(text)[0];
     
     if (obj && obj.qrcode) {
         if (obj.qrcode.base64) {
              console.log(` Tentativa ${i}: ACHOU BASE64! Tam: ${obj.qrcode.base64.length}`);
         } else {
             console.log(` Tentativa ${i}: QRCODE OBJ:`, JSON.stringify(obj.qrcode));
         }
     } else {
          console.log(` Tentativa ${i}: Sem qrcode. Status:`, obj?.connectionStatus);
     }
  }
}
run();
