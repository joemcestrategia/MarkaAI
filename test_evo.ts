import { createClient } from 'npm:@supabase/supabase-js@2'

const EVOLUTION_API_URL = 'http://187.127.26.94:8080'
const EVOLUTION_API_KEY = 'markaai2026'
const instanceName = 'shop_290d91b6-7519-4856-96dc-bcda3fd3b9f9'

async function test() {
  console.log("Creating instance...");
  const createRes = await fetch(`${EVOLUTION_API_URL}/instance/create`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'apikey': EVOLUTION_API_KEY 
    },
    body: JSON.stringify({
      instanceName,
      qrcode: true,
      integration: "WHATSAPP-BAILEYS"
    })
  });
  console.log("Create API status:", createRes.status);
  const createData = await createRes.json();
  console.log("Create Data:");
  console.log(createData);

  console.log("Fetching connect...");
  const connectRes = await fetch(`${EVOLUTION_API_URL}/instance/connect/${instanceName}`, {
    method: 'GET',
    headers: { 'apikey': EVOLUTION_API_KEY }
  });
  const connectData = await connectRes.json();
  console.log("Connect Data:");
  console.log(connectData);
}

test();
