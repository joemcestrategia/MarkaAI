const EVOLUTION_API_URL = 'http://187.127.26.94:8080';
const EVOLUTION_API_KEY = 'markaai2026';
const instanceName = 'shop_290d91b6-7519-4856-96dc-bcda3fd3b9f9';

async function run() {
     console.log("-> /instance/connect com base64=true");
     const r1 = await fetch(`${EVOLUTION_API_URL}/instance/connect/${instanceName}?base64=true`, {
        headers: { 'apikey': EVOLUTION_API_KEY }
     });
     console.log(await r1.text());
}

run();
