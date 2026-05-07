const EVOLUTION_API_URL = "http://187.127.26.94:8080";
const EVOLUTION_API_KEY = "markaai2026";
const instanceName = "shop_test123456";

async function test() {
  console.log("Deleting old...");
  await fetch(`${EVOLUTION_API_URL}/instance/delete/${instanceName}`, { 
    method: 'DELETE', headers: { "apikey": EVOLUTION_API_KEY } 
  });

  console.log("Creating new...");
  const createRes = await fetch(`${EVOLUTION_API_URL}/instance/create`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'apikey': EVOLUTION_API_KEY },
    body: JSON.stringify({ instanceName, qrcode: true })
  });

  const createData = await createRes.json();
  console.log("Create Data:");
  console.log(createData);

  console.log("\nConnecting...");
  const connectRes = await fetch(`${EVOLUTION_API_URL}/instance/connect/${instanceName}`, { 
    headers: { "apikey": EVOLUTION_API_KEY } 
  });
  const connectData = await connectRes.json();
  console.log("Connect Data:");
  console.log(connectData);
}

test();
