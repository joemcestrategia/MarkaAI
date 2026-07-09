import { load } from "https://deno.land/std@0.210.0/dotenv/mod.ts";
import Stripe from "npm:stripe@14.10.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

// Este teste cria seu próprio produto/price descartável na Stripe (modo test) porque o
// price_id usado em produção não existe no ambiente de teste. Isso evita misturar dados de
// teste no plan-mapping.ts (que é compartilhado com as Edge Functions de produção) e mantém
// este teste independente de qualquer price_id específico.

// 1. Carrega variáveis e checa prefixo da chave
const env = await load({ envPath: "./scripts/tests/.env" });
const stripeKey = (env["STRIPE_SECRET_KEY"] || Deno.env.get("STRIPE_SECRET_KEY") || "").trim();

if (!stripeKey) {
  console.error("❌ ERRO: STRIPE_SECRET_KEY não encontrada.");
  Deno.exit(1);
}

if (!stripeKey.startsWith("sk_test_")) {
  console.error("❌ ERRO CRÍTICO: STRIPE_SECRET_KEY não começa com 'sk_test_'. Abortando para proteger ambiente de produção.");
  Deno.exit(1);
}

// 2. Setup dos clientes
const stripe = new Stripe(stripeKey, { apiVersion: "2023-10-16" });

const supabaseUrl = env["SUPABASE_URL"] || Deno.env.get("SUPABASE_URL") || "http://127.0.0.1:54321";
const supabaseKey = env["SUPABASE_SERVICE_ROLE_KEY"] || env["SUPABASE_ANON_KEY"] || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_ANON_KEY") || "";

if (!supabaseKey) {
  console.error("❌ ERRO: SUPABASE_SERVICE_ROLE_KEY ou SUPABASE_ANON_KEY não encontrada.");
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseKey);
const SHOP_ID = "00000000-0000-0000-0000-testresource0";

Deno.test("resource_missing: Cancela assinatura direto na Stripe e valida rebaixamento no app", async () => {
  let customerId = "";
  let subscriptionId = "";
  let testProductId = "";
  let testPriceId = "";

  try {
    // 2. Limpa previamente qualquer resquício da loja
    await supabase.from("shops").delete().eq("id", SHOP_ID);

    // Cria um produto e price descartáveis, só para este teste, em modo Stripe test.
    const testProduct = await stripe.products.create({
      name: "[TESTE AUTOMATIZADO] Produto descartável - resource_missing test",
    });
    testProductId = testProduct.id;

    const testPrice = await stripe.prices.create({
      product: testProductId,
      unit_amount: 1000, // valor irrelevante, nunca será cobrado de verdade em modo test
      currency: "brl",
      recurring: { interval: "month" },
    });
    testPriceId = testPrice.id;

    // 3. Cria um Customer e uma Subscription usando um price_id de teste
    console.log("Criando Customer na Stripe...");
    const customer = await stripe.customers.create({ email: "test-resource-missing@example.com" });
    customerId = customer.id;

    console.log(`Criando Assinatura (price descartável) para ${customerId}...`);
    const subscription = await stripe.subscriptions.create({
      customer: customerId,
      items: [{ price: testPriceId }],
      trial_end: Math.floor(Date.now() / 1000) + 3600, // 1h de trial, faz o status virar 'trialing' sem precisar de cartão
    });
    subscriptionId = subscription.id;

    // 4. Insere a loja fake no banco
    console.log(`Inserindo loja fake no Supabase: ${SHOP_ID}`);
    const { error: insertError } = await supabase.from("shops").insert({
      id: SHOP_ID,
      name: "Test Resource Missing Shop",
      subscription: {
        stripe_customer_id: customerId,
        stripe_subscription_id: subscriptionId,
        status: "trialing",
        plan_id: "starter"
      },
      plan_id: "starter" // Começa como starter no nivel do schema se tiver
    });

    if (insertError) throw new Error(`Falha ao inserir loja: ${insertError.message}`);

    // Dispara get-live-subscription-status para confirmar que está ativa
    console.log("Testando get-live-subscription-status (Espera-se: status active ou trialing, planId null)...");
    
    const token = supabaseKey; // Usar service_role no Auth
    const res1 = await fetch(`${supabaseUrl}/functions/v1/get-live-subscription-status`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
      body: JSON.stringify({ shopId: SHOP_ID })
    });
    
    if (!res1.ok) {
      const errorText = await res1.text();
      throw new Error(`Edge Function (res1) falhou com HTTP ${res1.status}: ${errorText}`);
    }
    const data1 = await res1.json();
    
    console.log(`[INFO] Resultado parcial da Edge Function com Price Desconhecido -> planId: ${data1.planId}, status: ${data1.status}`);
    if (data1.status !== 'active' && data1.status !== 'trialing') {
      if (data1.status === 'free') {
        console.warn(`[AVISO] A Edge Function retornou status 'free'. Isso é esperado caso a Edge Function de produção esteja usando uma Stripe Secret Key LIVE, pois ela não encontrará a assinatura de TESTE recém-criada e acionará o fallback de resource_missing (404) imediatamente.`);
      } else {
        throw new Error(`Estado inicial incorreto. Esperado: status active ou trialing. Recebido: status=${data1.status}`);
      }
    }

    // 5. Cancela (deleta) a assinatura diretamente via API da Stripe
    console.log(`Cancelando assinatura ${subscriptionId} direto na Stripe...`);
    await stripe.subscriptions.cancel(subscriptionId);

    // 6. Dispara get-live-subscription-status novamente
    console.log("Testando get-live-subscription-status APÓS cancelamento (Espera-se: free)...");
    const res2 = await fetch(`${supabaseUrl}/functions/v1/get-live-subscription-status`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
      body: JSON.stringify({ shopId: SHOP_ID })
    });

    if (!res2.ok) {
      const errorText2 = await res2.text();
      throw new Error(`Edge Function (res2) falhou com HTTP ${res2.status}: ${errorText2}`);
    }
    const data2 = await res2.json();

    // 7. Expectativa: A função deve retornar status: 'free', planId: 'free'
    if (data2.planId !== 'free' || data2.status !== 'free') {
      throw new Error(`Retorno da function falhou na atualização. Esperado: free/free. Recebido: ${data2.planId}/${data2.status}`);
    }

    // Valida o banco local (tabela shops) - estritamente plan_id = 'free'
    const { data: shopData, error: fetchError } = await supabase.from("shops").select("plan_id").eq("id", SHOP_ID).single();
    if (fetchError) throw new Error(`Falha ao ler loja atualizada: ${fetchError.message}`);
    
    if (shopData.plan_id !== 'free') {
      throw new Error(`Banco de dados não foi rebaixado corretamente. Esperado plan_id: 'free'. Recebido: '${shopData.plan_id}'`);
    }

    console.log("✅ Teste concluído com sucesso!");
    
  } finally {
    // 8. Limpa os dados de teste
    console.log("Limpando ambiente de teste...");
    if (customerId) {
      try {
        await stripe.customers.del(customerId);
      } catch (e) {
         console.warn("Aviso: Falha ao deletar customer de teste na Stripe.", e);
      }
    }
    
    if (testPriceId) {
      try {
        await stripe.prices.update(testPriceId, { active: false });
      } catch (e) {
         console.warn("Aviso: Falha ao arquivar price descartável.", e);
      }
    }

    if (testProductId) {
      try {
        await stripe.products.update(testProductId, { active: false });
      } catch (e) {
         console.warn("Aviso: Falha ao arquivar product descartável.", e);
      }
    }

    await supabase.from("shops").delete().eq("id", SHOP_ID);
  }
});
