const EVOLUTION_API_URL = 'http://187.127.26.94:8080';
const EVOLUTION_API_KEY = 'markaai2026';
const instanceName = 'shop_290d91b6-7519-4856-96dc-bcda3fd3b9f9';

async function run() {
  console.log("Deletando...");
  await fetch(`${EVOLUTION_API_URL}/instance/delete/${instanceName}`, {
      method: 'DELETE', headers: { 'apikey': EVOLUTION_API_KEY }
  }).catch(()=>null);
  
  await new Promise(r => setTimeout(r, 1000));
  
  console.log("Criando...");
  await fetch(`${EVOLUTION_API_URL}/instance/create`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'apikey': EVOLUTION_API_KEY },
    body: JSON.stringify({ instanceName })
  });

  console.log("Connecting...");
  const rWait = await fetch(`${EVOLUTION_API_URL}/instance/connect/${instanceName}`, {
      method: 'GET', headers: { 'apikey': EVOLUTION_API_KEY }
  });
  console.log(await rWait.text());
}
run();
