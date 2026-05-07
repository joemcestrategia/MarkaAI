import { delay } from "https://deno.land/std@0.104.0/async/delay.ts";
const EVOLUTION_API_URL = "http://187.127.26.94:8080";
const EVOLUTION_API_KEY = "markaai2026";
const instanceName = "shop_290d91b6-7519-4856-96dc-bcda3fd3b9f9";

async function test() {
  for(let i=0; i<10; i++) {
    console.log(`Attempt ${i+1}...`);
    const res = await fetch(`${EVOLUTION_API_URL}/instance/connect/${instanceName}`, { 
      headers: { "apikey": EVOLUTION_API_KEY } 
    });
    const data = await res.json();
    console.log(Object.keys(data));
    if(data.base64) {
      console.log("Got base64!");
      break;
    }
    await delay(2000);
  }
}
test();
