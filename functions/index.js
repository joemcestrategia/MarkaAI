/* getInstallments HTTP endpoint removed (duplicate). Use the onCall getInstallments defined later in this file.
   The later implementation will be adapted to handle HTTP if needed. */

const functions = require("firebase-functions");
const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require("firebase-functions/v2/firestore");
const { onRequest, onCall } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");

const { defineString, defineSecret } = require("firebase-functions/params");

const admin = require("firebase-admin");
const axios = require("axios");
const fs = require("fs");
const path = require("path");
const cors = require("cors")({ origin: true });
const stripe = require("stripe")("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");

// Importando serviço de e-mail (SMTP)
const emailService = require("./emailService");

const PRICE_IDS = {
  // TODO: INSERIR OS IDs DE PREÇO (price_...) REAIS DE PRODUÇÃO DOS PLANOS ABAIXO:
  'start': 'price_1T98YSFzh8r5AMGzkMdAH2eq', // Live - R$ 29,90/mês
  'plus': 'price_1T98ZPFzh8r5AMGzUHfVZRfC',  // Live - R$ 59,90/mês
  'pro': 'price_1T98aHFzh8r5AMGzlgvM6eSZ',   // Live - R$ 99,90/mês

  // Boosts (manter IDs antigos - podem ser Live, testar separadamente ou substituir)
  'boost_24h': 'price_1T98cJFzh8r5AMGzFOigUfSM',
  'boost_3d': 'price_1T98d6Fzh8r5AMGznhujEh4J',
  'boost_7d': 'price_1T98e3Fzh8r5AMGz4FJhXU3C',

  // Plano test_plan legado
  'test_plan': 'price_1T98SZFzh8r5AMGzPrzLG4c8'
};

const GOOGLE_PLACES_API_KEY = defineString("GOOGLE_PLACES_API_KEY");
const MP_WEBHOOK_SECRET = defineSecret("MP_WEBHOOK_SECRET");
const MP_CLIENT_ID = defineSecret("MP_CLIENT_ID");
const MP_CLIENT_SECRET = defineSecret("MP_CLIENT_SECRET");

// Validação de disponibilidade para evitar double-booking
exports.checkAvailability = onCall(async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Usuário não autenticado');
  }

  const { professionalId, startTime, duration } = request.data;
  if (!professionalId || !startTime || !duration) {
    throw new functions.https.HttpsError('invalid-argument', 'Dados incompletos para validação');
  }

  const startTimeObj = new Date(startTime);
  const start = admin.firestore.Timestamp.fromDate(startTimeObj);
  const end = admin.firestore.Timestamp.fromDate(new Date(startTimeObj.getTime() + duration * 60000));

  const appointments = await admin.firestore()
    .collection('appointments')
    .where('profissionalId', '==', professionalId)
    .where('status', 'not-in', ['cancelado', 'rejeitado', 'excluido'])
    .get();

  const conflicting = appointments.docs.filter(doc => {
    const data = doc.data();
    const apptStart = data.data_agendamento.toDate();
    const apptDuration = data.duracao_min || 30;
    const apptEnd = new Date(apptStart.getTime() + apptDuration * 60000);

    const reqStart = new Date(startTime);
    const reqEnd = new Date(reqStart.getTime() + duration * 60000);

    return (reqStart < apptEnd && reqEnd > apptStart);
  });

  return {
    available: conflicting.length === 0,
    conflicts: conflicting.length
  };
});

// Página HTML do checkout transparente (servida via HTTPS para tokenização)
const checkoutHtmlPath = path.join(__dirname, "checkout_transparente.html");
let checkoutHtmlCache = "";
try {
  checkoutHtmlCache = fs.readFileSync(checkoutHtmlPath, "utf8");
} catch (e) {
  console.error("Erro ao carregar checkout_transparente.html:", e.message);
}

exports.checkoutTransparentePage = onRequest({ cors: true }, (req, res) => {
  if (!checkoutHtmlCache) {
    return res.status(500).send("Checkout HTML indisponível");
  }
  res.set("Content-Type", "text/html; charset=utf-8");
  res.set("Cache-Control", "no-store");
  return res.status(200).send(checkoutHtmlCache);
});

// Helpers for safety
function escapeHtml(unsafe) {
  if (!unsafe) return '';
  return unsafe
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function escapeJs(unsafe) {
  if (!unsafe) return '';
  return unsafe.replace(/'/g, "\\'").replace(/"/g, '\\"');
}

// Public shop preview page (provides OG meta tags for WhatsApp/social previews)
exports.publicShopPreview = onRequest({ cors: true }, async (req, res) => {
  try {
    // Extract slug from URL path (e.g. /afroed) or query param
    const slug = (req.path.replace(/^\//, '').replace(/\/$/, '') || req.query.slug || '').trim();
    if (!slug) {
      return res.status(400).send("Slug não fornecido");
    }
    // ... rest of the function ...
  } catch (e) {
    // ... error handling ...
  }
});

/**
 * Cria uma Assinatura no Stripe e retorna o segredo para o App (Stripe Native)
 */
exports.createStripeSubscription = onCall(async (request) => {
  const { planId, email, shopId } = request.data;

  if (!planId || !email || !shopId) {
    throw new functions.https.HttpsError('invalid-argument', 'Dados incompletos');
  }

  const priceId = PRICE_IDS[planId];
  if (!priceId || priceId.includes('TODO')) {
    throw new functions.https.HttpsError('not-found', 'ID de Preço não configurado para este plano');
  }

  try {
    // 1. Buscar ou Criar Cliente
    let customer;
    const customers = await stripe.customers.list({ email: email, limit: 1 });
    if (customers.data.length > 0) {
      customer = customers.data[0];
    } else {
      customer = await stripe.customers.create({
        email: email,
        metadata: { shopId: shopId }
      });
    }

    // 2. Criar Chave Efêmera (para o Payment Sheet)
    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customer.id },
      { apiVersion: '2024-06-20' }
    );

    // 4. Salvar IDs no Firestore imediatamente
    await admin.firestore().collection('shops').doc(shopId).update({
      'subscription.stripe_subscription_id': subscription.id,
      'subscription.stripe_customer_id': customer.id,
      'subscription.status': 'pending_payment',
      'subscription.plan_id': planId,
      'stripe_customer_id': customer.id, // redundancy for easy lookup
    });

    return {
      subscriptionId: subscription.id,
      paymentIntentClientSecret: subscription.latest_invoice.payment_intent.client_secret,
      customer: customer.id,
      ephemeralKey: ephemeralKey.secret,
      publishableKey: "pk_live_51T97xzFzh8r5AMGzlcuoTt9mxupvYn3fD9UznF7pdPNxxZI4W0Jn6xb36tYKlSvtUnb7544CeIXtDX84XshUk6dF00d10axLwi"
    };
  } catch (error) {
    console.error("Stripe Subscription Error:", error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

/**
 * Webhook do Stripe para sincronização Assíncrona (SaaS)
 */
exports.stripeWebhook = onRequest({ cors: true }, async (req, res) => {
  const sig = req.headers['stripe-signature'];
  let event;

  try {
    // Nota: Em produção, valide o sig usando stripe.webhooks.constructEvent se tiver o endpoint secret
    event = req.body;
  } catch (err) {
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  const db = admin.firestore();

  switch (event.type) {
    case 'invoice.payment_succeeded': {
      const invoice = event.data.object;
      const subscriptionId = invoice.subscription;
      const customerId = invoice.customer;

      if (subscriptionId) {
        // Encontrar a loja vinculada a este cliente ou assinatura
        const shops = await db.collection('shops')
          .where('subscription.stripe_subscription_id', '==', subscriptionId)
          .limit(1)
          .get();

        if (!shops.empty) {
          const shopDoc = shops.docs[0];
          const subscription = await stripe.subscriptions.retrieve(subscriptionId);

          await shopDoc.ref.update({
            'subscription.status': 'active',
            'subscription.current_period_end': admin.firestore.Timestamp.fromMillis(subscription.current_period_end * 1000),
            'subscription.updated_at': admin.firestore.FieldValue.serverTimestamp(),
          });
          console.log(`✅ Webhook: Assinatura renovada para loja ${shopDoc.id}`);
        }
      }
      break;
    }

    case 'customer.subscription.deleted': {
      const subscription = event.data.object;
      const shops = await db.collection('shops')
        .where('subscription.stripe_subscription_id', '==', subscription.id)
        .limit(1)
        .get();

      if (!shops.empty) {
        await shops.docs[0].ref.update({
          'subscription.status': 'expired',
          'subscription.updated_at': admin.firestore.FieldValue.serverTimestamp(),
          'plan': 'free',
          'plan_id': 'free'
        });
        console.log(`❌ Webhook: Assinatura expirada/excluída para loja ${shops.docs[0].id}`);
      }
      break;
    }
  }

  res.json({ received: true });
});
exports.createStripePaymentIntent = onCall(async (request) => {
  const { amount, currency, description } = request.data;

  try {
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amount,
      currency: currency || 'brl',
      description: description,
      automatic_payment_methods: { enabled: true },
    });

    return {
      clientSecret: paymentIntent.client_secret,
    };
  } catch (error) {
    console.error("Stripe PaymentIntent Error:", error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

// Public shop preview page (provides OG meta tags for WhatsApp/social previews)
exports.publicShopPreview = onRequest({ cors: true }, async (req, res) => {
  try {
    // Extract slug from URL path (e.g. /afroed) or query param
    const slug = (req.path.replace(/^\//, '').replace(/\/$/, '') || req.query.slug || '').trim();
    if (!slug) {
      return res.status(400).send('Missing slug');
    }

    const siteUrl = 'https://markaai.com.br';
    const shopUrl = `${siteUrl}/${slug}`;

    // Detect social media crawlers / bots by User-Agent
    const ua = req.headers['user-agent'] || '';
    const isBot = /whatsapp|facebookexternalhit|twitterbot|googlebot|linkedinbot|slackbot|discordbot|telegrambot|applebot|bingbot|yandex/i.test(ua);

    console.log(`publicShopPreview: slug=${slug} isBot=${isBot} ua=${ua.substring(0, 80)}`);

    // Fetch shop data from Firestore
    const snap = await admin.firestore().collection('shops').where('slug', '==', slug).limit(1).get();

    if (snap.empty) {
      console.warn(`publicShopPreview: shop not found for slug=${slug}`);
      // Fallback OG for bots when shop not found, allowing human users to hit the Flutter router natively to see "Loja não encontrada" rather than forcing a 302 to root which triggers the login gate.
      if (isBot) {
        const fallbackHtml = `<!doctype html><html lang="pt-BR"><head>
          <meta charset="utf-8">
          <title>Marka AI - Não Encontrada</title>
          <meta property="og:title" content="Marka AI" />
          <meta property="og:description" content="Desculpe, a loja solicitada não foi encontrada." />
          <meta property="og:image" content="${siteUrl}/icons/Icon-512.png" />
          <meta property="og:url" content="${siteUrl}" />
          <meta property="og:site_name" content="Marka AI" />
          <meta property="og:type" content="website" />
        </head><body></body></html>`;
        return res.status(200).send(fallbackHtml);
      }

      // Se não for bot, ignoramos o preenchimento de OG tags e apenas enviamos o HTML base normal vazio. 
      // Isso força o roteador do flutter a montar e renderizar a rota e consequentemente dar 404 visual.
      const ogHtmlTags = `
        <title>Marka AI - Não Encontrada</title>
        <meta property="og:title" content="Loja não encontrada" />
      `;
      const name = "Página não encontrada";
      const ogDescription = "A loja não existe.";
      const shopUrl = siteUrl;

      const fullHtml = `<!doctype html>
<html lang="pt-BR">
<!-- Version: 1.0.1-not-found-fallback -->
<head>
  <base href="/">
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  
  ${ogHtmlTags}
  
  <meta name="google-signin-client_id" content="170942564821-s8doqh3tcqe4rs7muauefgkdqehcf1l9.apps.googleusercontent.com">
  <link rel="icon" type="image/png" href="favicon.png"/>
  <link rel="manifest" href="manifest.json">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/croppie/2.6.5/croppie.css" />
  <script defer src="https://cdnjs.cloudflare.com/ajax/libs/croppie/2.6.5/croppie.min.js"></script>
</head>
<body style="margin: 0; padding: 0; background: #5B2DB6;">
  <!-- Splash / Loading state -->
  <div id="splash" style="position: fixed; inset: 0; background: linear-gradient(180deg, #5B2DB6, #4A1F8A); display: flex; align-items: center; justify-content: center; flex-direction: column; z-index: 9999; color: #fff; font-family: sans-serif;">
    <div style="font-size: 24px; font-weight: bold; margin-bottom: 20px;">Marka AI</div>
    <div style="font-size: 14px; opacity: 0.8;">Carregando...</div>
  </div>

  <!-- Flutter Loader -->
  <script src="flutter_bootstrap.js" async></script>
  <script>
    function hideSplash() {
      var s = document.getElementById('splash');
      if (s) s.style.display = 'none';
    }
    window.addEventListener('flutter-first-frame', hideSplash);
    setTimeout(hideSplash, 10000);
  </script>
</body>
</html>`;
      return res.status(200).send(fullHtml);
    }

    const shop = snap.docs[0].data() || {};

    // Map Firestore fields (matching field names used in the Flutter app)
    const name = shop.nome || 'Loja MarkaAI';
    const category = shop.categoria || shop.segmento || shop.tipo || '';
    const descricao = shop.descricao || '';
    const address = shop.endereco || shop.cidade || '';
    const imageUrl = shop.logoUrl || shop.coverUrl || shop.imageUrl || `${siteUrl}/icons/Icon-512.png`;

    // Title: "Nome | Categoria [ Reserve agora ]" (similar ao Setmore)
    const ogTitle = category
      ? `${name} | ${category} [ Reserve agora ]`
      : `${name} [ Reserve agora ]`;

    // Description: compelling call to action with address
    let ogDescription = `Agende sua consulta com ${name}`;
    if (address) ogDescription += ` • ${address}`;
    if (descricao && descricao.length > 0) ogDescription = descricao;

    res.set('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.set('Pragma', 'no-cache');
    res.set('Expires', '0');

    // 1. Basic path validation to avoid asset interception
    // If it looks like a file or system path, don't treat it as a slug
    if (slug.includes('.') || slug.startsWith('_') || slug === 'index.html') {
      return res.status(404).send('Not a shop');
    }

    // Build common OG meta tags
    const ogHtmlTags = `
  <title>${escapeHtml(ogTitle)}</title>
  <meta name="description"        content="${escapeHtml(ogDescription)}" />
  <meta property="og:type"        content="website" />
  <meta property="og:site_name"   content="Marka AI" />
  <meta property="og:url"         content="${escapeHtml(shopUrl)}" />
  <meta property="og:title"       content="${escapeHtml(ogTitle)}" />
  <meta property="og:description" content="${escapeHtml(ogDescription)}" />
  <meta property="og:image"       content="${escapeHtml(imageUrl)}" />
  <meta property="og:image:width"  content="1200" />
  <meta property="og:image:height" content="630" />
  <meta property="og:image:type"   content="image/jpeg" />
  <meta name="twitter:card"        content="summary_large_image" />
  <meta name="twitter:title"       content="${escapeHtml(ogTitle)}" />
  <meta name="twitter:description" content="${escapeHtml(ogDescription)}" />
  <meta name="twitter:image"       content="${escapeHtml(imageUrl)}" />
  <link rel="canonical" href="${escapeHtml(shopUrl)}" />`;

    // Serve HTML (Common for Bots OR Human)
    // We no longer redirect to ?_loaded=1 to avoid loops and flickering.
    // Instead, we serve the bootstrap HTML with OG tags immediately.
    const fullHtml = `<!doctype html>
<html lang="pt-BR">
<!-- Version: 1.0.1-no-redirect -->
<head>
  <base href="/">
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta content="IE=Edge" http-equiv="X-UA-Compatible">
  
  ${ogHtmlTags}
  
  <meta name="google-signin-client_id" content="170942564821-s8doqh3tcqe4rs7muauefgkdqehcf1l9.apps.googleusercontent.com">
  <link rel="icon" type="image/png" href="favicon.png"/>
  <link rel="manifest" href="manifest.json">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/croppie/2.6.5/croppie.css" />
  <script defer src="https://cdnjs.cloudflare.com/ajax/libs/croppie/2.6.5/croppie.min.js"></script>
</head>
<body style="margin: 0; padding: 0; background: #5B2DB6;">
  <!-- Splash / Loading state -->
  <div id="splash" style="position: fixed; inset: 0; background: linear-gradient(180deg, #5B2DB6, #4A1F8A); display: flex; align-items: center; justify-content: center; flex-direction: column; z-index: 9999; color: #fff; font-family: sans-serif;">
    <div style="font-size: 24px; font-weight: bold; margin-bottom: 20px;">Marka AI</div>
    <div style="font-size: 14px; opacity: 0.8;">Carregando ${escapeHtml(name)}...</div>
  </div>

  <!-- Bot Content (Hidden for humans, visible for crawlers) -->
  <div style="display: none;">
    <h1>${escapeHtml(name)}</h1>
    <p>${escapeHtml(ogDescription)}</p>
    <a href="${escapeHtml(shopUrl)}">Agendar agora</a>
  </div>

  <!-- Flutter Loader -->
  <script src="flutter_bootstrap.js" async></script>
  <script>
    function hideSplash() {
      var s = document.getElementById('splash');
      if (s) s.style.display = 'none';
    }
    window.addEventListener('flutter-first-frame', hideSplash);
    setTimeout(hideSplash, 10000);
  </script>
</body>
</html>`;

    return res.status(200).send(fullHtml);

  } catch (err) {
    console.error('publicShopPreview error:', err);
    return res.status(500).send('Internal error');
  }
});

// (escapeHtml and escapeJs already declared above — no duplicate)

exports.mercadopagoCallback = onRequest({ cors: true, secrets: ['MP_CLIENT_ID', 'MP_CLIENT_SECRET'] }, async (req, res) => {
  const code = req.query.code;
  const state = req.query.state;
  const error = req.query.error;
  const errorDescription = req.query.error_description || 'Erro desconhecido';

  console.log('Callback Mercado Pago recebido:', {
    query: req.query,
    fullUrl: req.url,
    ip: req.ip,
  });

  const appUrl = 'https://markaai.com.br';
  const buildResultPage = (title, message, isError = false) => `
    <!doctype html>
    <html lang="pt-BR">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>${title}</title>
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; background:#f6f7fb; margin:0; }
        .wrap { max-width:640px; margin:10vh auto; padding:0 16px; }
        .card { background:#fff; padding:24px; border-radius:16px; box-shadow:0 10px 30px rgba(0,0,0,.08); border:1px solid ${isError ? '#ffcdd2' : '#c8e6c9'}; }
        h1 { font-size:22px; margin:0 0 10px; color:${isError ? '#c62828' : '#2e7d32'}; }
        p { color:#444; line-height:1.6; margin:8px 0; }
        .badge { display:inline-block; font-size:12px; padding:4px 8px; border-radius:999px; background:${isError ? '#ffebee' : '#e8f5e9'}; color:${isError ? '#c62828' : '#2e7d32'}; }
        .steps { margin-top:12px; padding:12px; background:#f9fafc; border-radius:12px; border:1px dashed #dce2f0; }
        .steps li { margin:6px 0; }
        .footer { margin-top:14px; font-size:12px; color:#666; }
      </style>
    </head>
    <body>
      <div class="wrap">
        <div class="card">
          <span class="badge">${isError ? 'Falha' : 'Sucesso'}</span>
          <h1>${title}</h1>
          <p>${message}</p>
          <div class="steps">
            <strong>Próximos passos</strong>
            <ul>
    <li>Volte para o app MarkaAI.</li>
              <li>Se a tela não atualizar, feche e abra o app.</li>
            </ul>
          </div>
          <div style="margin-top:12px;">
            <a class="btn" href="markaai://mercadopago">Voltar para o app</a>
          </div>
          <div class="footer">Você pode fechar esta página com segurança.</div>
        </div>
      </div>
    </body>
    </html>
  `;

  if (error) {
    console.error('Erro retornado pelo Mercado Pago:', { error, errorDescription, state });
    return res.status(200).send(buildResultPage(
      'Conexão não concluída',
      `Não foi possível conectar com o Mercado Pago. Detalhe: ${errorDescription}`,
      true
    ));
  }

  if (!code) {
    console.error('Nenhum code recebido no callback');
    return res.status(200).send(buildResultPage(
      'Conexão não concluída',
      'Código de autorização ausente.',
      true
    ));
  }

  const clientId = MP_CLIENT_ID.value();
  const clientSecret = MP_CLIENT_SECRET.value();
  const redirectUri = "https://us-central1-wismart-118c3.cloudfunctions.net/mercadopagoCallback";


  try {
    console.log('Tentando trocar code por token...');

    const response = await axios.post(
      "https://api.mercadopago.com/oauth/token",
      `client_id=${clientId}&client_secret=${clientSecret}&code=${code}&grant_type=authorization_code&redirect_uri=${encodeURIComponent(redirectUri)}`,
      {
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "Accept": "application/json",
        },
      }
    );

    const tokens = response.data;
    console.log('Tokens obtidos com sucesso:', { user_id: tokens.user_id });

    const accessToken = tokens.access_token;
    const refreshToken = tokens.refresh_token;
    const userIdMP = tokens.user_id;
    const publicKey = tokens.public_key;

    let shopId = 'anon';
    if (state && state.startsWith('shop-')) {
      const parts = state.split('-');
      shopId = parts[1] || 'anon';
    }

    await admin.firestore().collection('shops').doc(shopId).set(
      {
        mercadopago: {
          access_token: accessToken,
          refresh_token: refreshToken,
          user_id: userIdMP,
          public_key: publicKey,
          connected: true,
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        payment_provider: 'mercadopago',
        payment_configured: true,
        payment_configured_at: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    console.log(`Tokens salvos com sucesso para shopId: ${shopId}`);

    return res.status(200).send(buildResultPage(
      'Conectado com sucesso',
      'Sua conta Mercado Pago foi conectada. Agora você já pode voltar para o app.',
      false
    ));
  } catch (err) {
    console.error('Erro ao trocar code por token:', {
      message: err.message,
      response: err.response ? err.response.data : null,
      status: err.response ? err.response.status : null,
    });

    return res.status(200).send(buildResultPage(
      'Conexão não concluída',
      err.response?.data?.message || 'Falha ao obter tokens.',
      true
    ));
  }
});

// ===================================================================
// FUNÇÕES DE PAGAMENTO
// ===================================================================

// 1. GERAR PIX
exports.createPixPayment = onCall(async (request) => {
  const data = request.data;
  const auth = request.auth;

  // CORREÇÃO DE SEGURANÇA: não aceitar accessToken no payload (risco de token injection)
  // O token deve sempre ser lido do Firestore usando o shopId
  if (!auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Autenticação necessária para gerar PIX.');
  }

  const shopId = data.shopId;
  const amount = parseFloat(data.amount);
  const email = data.email || data.emailCliente || 'cliente@app.com';
  const description = data.description || 'Pagamento App';

  if (!shopId) {
    throw new functions.https.HttpsError('invalid-argument', 'shopId é obrigatório para gerar PIX.');
  }
  if (!amount || isNaN(amount) || amount <= 0) {
    throw new functions.https.HttpsError('invalid-argument', 'Valor inválido para o pagamento PIX.');
  }

  // Busca o access_token da loja no Firestore (nunca aceito do client)
  let accessToken = null;
  try {
    const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
    if (!shopDoc.exists) {
      throw new functions.https.HttpsError('not-found', 'Loja não encontrada.');
    }
    accessToken = shopDoc.data()?.mercadopago?.access_token || null;
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    throw new functions.https.HttpsError('internal', 'Erro ao acessar configuração da loja.');
  }

  if (!accessToken) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Mercado Pago não configurado nesta loja. O dono precisa conectar a conta.'
    );
  }

  const idempotencyKey = `pix-${auth.uid}-${Date.now()}`;
  console.log("🔑 Chave Idempotencia:", idempotencyKey);

  try {
    const paymentData = {
      transaction_amount: amount,
      description: description,
      payment_method_id: 'pix',
      payer: {
        email: email
      },
    };

    const baseUrl = (accessToken && accessToken.startsWith && accessToken.startsWith('TEST-'))
      ? 'https://api.sandbox.mercadopago.com'
      : 'https://api.mercadopago.com';
    const response = await axios.post(
      `${baseUrl}/v1/payments`,
      paymentData,
      {
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'X-Idempotency-Key': idempotencyKey,
          'Content-Type': 'application/json'
        }
      }
    );

    return response.data;

  } catch (error) {
    const mpError = error.response?.data?.message || error.message;
    const mpCause = error.response?.data?.cause || error.response?.data || {};
    const mpDetails = JSON.stringify(mpCause);
    console.error("❌ ERRO MP DETALHADO:", mpError, mpDetails);

    // Detect common Mercado Pago causes and return specific errors for client UX
    try {
      const causeStr = JSON.stringify(mpCause).toLowerCase();

      // collector not enabled for QR rendering
      if (causeStr.includes('collector user') && causeStr.includes('qr')) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'collector_not_enabled_for_qr',
          { original: mpError, details: mpCause }
        );
      }

      // collector has no PIX keys registered (mensagem do suporte Mercado Pago)
      if (
        causeStr.includes('pix key') ||
        causeStr.includes('pix_keys') ||
        causeStr.includes('no pix') ||
        causeStr.includes('collector without pix') ||
        causeStr.includes('collector has no pix') ||
        causeStr.includes('collector without keys') ||
        causeStr.includes('chave pix') ||
        causeStr.includes('chaves pix') ||
        causeStr.includes('pix não') ||
        causeStr.includes('pix nao') ||
        causeStr.includes('pix is not enabled')
      ) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'collector_no_pix_keys',
          { original: mpError, details: mpCause }
        );
      }
    } catch (e) {
      // if we threw an HttpsError above, rethrow to be handled by outer catch
      if (e instanceof functions.https.HttpsError) throw e;
      // otherwise ignore parsing errors and continue to generic throw
    }

    throw new functions.https.HttpsError('aborted', `MP Recusou: ${mpError}`, mpDetails);
  }
});


// 2. VERIFICAR STATUS
exports.getPaymentStatus = onCall(async (request) => {
  const { accessToken, paymentId } = request.data;

  try {
    const baseUrl = (accessToken && accessToken.startsWith && accessToken.startsWith('TEST-'))
      ? 'https://api.sandbox.mercadopago.com'
      : 'https://api.mercadopago.com';
    const response = await axios.get(
      `${baseUrl}/v1/payments/${paymentId}`,
      {
        headers: { 'Authorization': `Bearer ${accessToken}` }
      }
    );
    return response.data;
  } catch (error) {
    console.error("Erro ao consultar status:", {
      message: error.message,
      responseData: error.response ? error.response.data : null,
      status: error.response ? error.response.status : null,
    });
    throw new functions.https.HttpsError('internal', 'Erro ao consultar status', error.response ? error.response.data : error.message);
  }
});

// 2.1 COBRAR CARTÃO (LEGADO - manter para não quebrar deploy)
exports.cobrarCartao = onCall(async (request) => {
  try {
    if (!request.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'Usuário não autenticado');
    }

    const {
      accessToken,
      shopId,
      cardNumber,
      cardHolder,
      expirationMonth,
      expirationYear,
      securityCode,
      amount,
      installments,
      description,
      emailCliente,
    } = request.data;

    let tokenToUse = accessToken;
    if (!tokenToUse && shopId) {
      const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
      tokenToUse = shopDoc.data()?.mercadopago?.access_token;
    }

    if (!tokenToUse || !cardNumber || !cardHolder || !expirationMonth ||
      !expirationYear || !securityCode || !amount || !description) {
      throw new functions.https.HttpsError('invalid-argument', 'Dados incompletos');
    }

    const emailFinal = emailCliente && emailCliente.includes('@')
      ? emailCliente
      : 'cliente_sem_email@markaai.com';

    // 1) Token do cartão
    const tokenResponse = await axios.post(
      'https://api.mercadopago.com/v1/card_tokens',
      {
        card_number: cardNumber,
        cardholder: { name: cardHolder },
        expiration_month: expirationMonth,
        expiration_year: expirationYear,
        security_code: securityCode,
      },
      { headers: { 'Authorization': `Bearer ${tokenToUse}`, 'Content-Type': 'application/json' } }
    );

    const cardToken = tokenResponse.data.id;

    // 2) Pagamento
    const paymentPayload = {
      token: cardToken,
      transaction_amount: parseFloat(amount),
      installments: parseInt(installments || 1),
      description: description,
      payer: { email: emailFinal },
    };

    const paymentResponse = await axios.post(
      'https://api.mercadopago.com/v1/payments',
      paymentPayload,
      {
        headers: {
          'Authorization': `Bearer ${tokenToUse}`,
          'Content-Type': 'application/json',
          'X-Idempotency-Key': request.auth.uid + Date.now(),
        },
      }
    );

    return paymentResponse.data;
  } catch (error) {
    const mpError = error.response?.data?.message || error.message;
    throw new functions.https.HttpsError('internal', `Erro ao cobrar cartão: ${mpError}`);
  }
});

// 3. COBRAR CARTÃO SALVO
exports.cobrarCartaoSalvo = onCall(async (request) => {
  // CORREÇÃO 5: extrair shopId para buscar public_key da loja (variável data era indefinida antes)
  const { accessToken, amount, customerId, cardId, shopId, installments, description, email, securityCode } = request.data;

  try {
    // Busca a public_key da loja no Firestore (NUNCA usa fallback hardcoded)
    if (!shopId) {
      throw new functions.https.HttpsError('invalid-argument', 'shopId é obrigatório para cobrar cartão salvo.');
    }
    const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
    const shopPublicKey = shopDoc.exists ? shopDoc.data()?.mercadopago?.public_key : null;
    if (!shopPublicKey) {
      throw new functions.https.HttpsError('failed-precondition', 'Loja não possui public_key do Mercado Pago configurada.');
    }

    const tokenResponse = await axios.post(
      `https://api.mercadopago.com/v1/card_tokens?public_key=${shopPublicKey}`,
      {
        security_code: securityCode,
        card_id: cardId
      },
      { headers: { 'Authorization': `Bearer ${accessToken}` } }
    );

    const token = tokenResponse.data.id;

    const paymentData = {
      transaction_amount: parseFloat(amount),
      token: token,
      installments: parseInt(installments),
      payer: {
        type: 'customer',
        id: customerId,
        email: email
      },
      description: description || 'Serviço Agendado'
    };

    console.log("Cobrando cartão salvo...", { customerId, cardId });

    const response = await axios.post(
      'https://api.mercadopago.com/v1/payments',
      paymentData,
      {
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
          'X-Idempotency-Key': request.auth ? request.auth.uid + Date.now() : Date.now().toString()
        }
      }
    );

    return response.data;

  } catch (error) {
    console.error("Erro ao cobrar cartão salvo:", error.response?.data || error.message);
    throw new functions.https.HttpsError('internal', 'Erro no pagamento recorrente', error.response?.data);
  }
});

// 4. BUSCAR PARCELAS
// Expose an HTTP endpoint to fetch installments using bin + amount.
// This wraps the existing callable implementation to support direct HTTP POST.
exports.getInstallments = onRequest({ cors: true }, async (req, res) => {
  return cors(req, res, async () => {
    try {
      if (req.method !== 'POST') return res.status(405).json({ success: false, error: 'Method not allowed' });
      const body = req.body || {};
      const { bin, amount, shopId } = body;
      // Try to read shop config to compute tax_percent if present
      let accessToken = body.accessToken;
      let amountNum = Number(amount) || 0;
      if (!bin || !amount) return res.status(400).json({ success: false, error: 'bin and amount are required' });
      // Read shop config if shopId provided to compute tax_percent
      if (shopId) {
        try {
          const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
          const shop = shopDoc.exists ? shopDoc.data() : {};
          const cfg = (shop && shop.config) ? shop.config : (shop && shop.payment_options && shop.payment_options.credito_config) ? shop.payment_options.credito_config : {};
          const taxPercent = Number(cfg?.tax_percent ?? cfg?.porcentagem_a_vista ?? 0) || 0;
          if (taxPercent > 0) amountNum = amountNum * (1 + taxPercent / 100.0);
          // If access token not provided, try to get from shop mercadopago config
          if (!accessToken) accessToken = shop?.mercadopago?.access_token || null;
        } catch (e) {
          console.warn('Failed to read shop config for installments:', e.message || e);
        }
      }

      // Call Mercado Pago API
      // FASE 3 FIX: usar public_key como fallback quando access_token não disponível
      const shopPublicKey = (!accessToken && shopId) ? (() => {
        try { return shop?.mercadopago?.public_key || null; } catch { return null; }
      })() : null;

      const baseUrl = accessToken && accessToken.startsWith && accessToken.startsWith('TEST-') ? 'https://api.sandbox.mercadopago.com' : 'https://api.mercadopago.com';
      const params = { bin: bin.toString().substring(0, 6), amount: amountNum };

      let installmentsUrl;
      let headers;
      if (accessToken) {
        // Autenticado via access_token (preferível)
        installmentsUrl = `${baseUrl}/v1/payment_methods/installments`;
        headers = { Authorization: `Bearer ${accessToken}` };
      } else if (shopPublicKey) {
        // Fallback: public_key como query param (não precisa de Authorization)
        installmentsUrl = `${baseUrl}/v1/payment_methods/installments?public_key=${shopPublicKey}`;
        headers = {};
        console.log('getInstallments: usando public_key como fallback (sem access_token)');
      } else {
        // Sem credenciais — apenas tenta sem autenticação (pode falhar com 401)
        installmentsUrl = `${baseUrl}/v1/payment_methods/installments`;
        headers = {};
        console.warn('getInstallments: sem access_token nem public_key — chamada pode ser rejeitada pela API MP');
      }

      const response = await axios.get(installmentsUrl, { params, headers });
      const result = response.data && response.data.length ? response.data[0] : null;
      return res.json({ success: true, data: result });
    } catch (err) {
      console.error('getInstallments http error:', err.message || err, err.response ? err.response.data : null);
      return res.status(500).json({ success: false, error: err.message || 'internal' });
    }
  });
});

// 5. CRIAR PAGAMENTO COM CARDTOKEN (NOVA FUNÇÃO)
exports.criarPagamento = onRequest({ cors: true }, async (req, res) => {
  // Configurar CORS para permitir chamadas do app
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(204).send('');
  }

  try {
    console.log('📝 Iniciando criarPagamento...');

    const data = req.body.data || req.body;

    // CORREÇÃO 8: Autenticação obrigatória — bloqueia se token inválido ou ausente
    let uid = null;
    if (!data?.idToken) {
      return res.status(401).json({
        success: false,
        error: 'Autenticação necessária para realizar pagamentos. Faça login novamente.'
      });
    }
    try {
      const decoded = await admin.auth().verifyIdToken(data.idToken, true);
      uid = decoded.uid;
      console.log('🔐 UID validado:', uid);
    } catch (err) {
      console.error('❌ Token inválido ou expirado:', err.message);
      return res.status(401).json({
        success: false,
        error: 'Sessão inválida. Faça login novamente para continuar.'
      });
    }

    // CORREÇÃO 7: Rate limiting — máximo 5 tentativas por usuário por minuto
    try {
      const rateLimitRef = admin.firestore().collection('rate_limits').doc(`payment_${uid}`);
      const rateLimitDoc = await rateLimitRef.get();
      const now = Date.now();
      const windowMs = 60 * 1000;
      const maxRequests = 5;
      if (rateLimitDoc.exists) {
        const rlData = rateLimitDoc.data();
        const windowStart = rlData.windowStart || 0;
        const count = rlData.count || 0;
        if (now - windowStart < windowMs) {
          if (count >= maxRequests) {
            return res.status(429).json({
              success: false,
              error: 'Muitas tentativas de pagamento. Aguarde 1 minuto e tente novamente.'
            });
          }
          await rateLimitRef.update({ count: admin.firestore.FieldValue.increment(1) });
        } else {
          await rateLimitRef.set({ windowStart: now, count: 1 });
        }
      } else {
        await rateLimitRef.set({ windowStart: now, count: 1 });
      }
    } catch (rlErr) {
      console.warn('Rate limit check failed (non-critical):', rlErr.message);
      // Não bloqueia por falha no rate limit
    }

    // Extrair dados
    const cardToken = data.cardToken;
    const email = data.email;
    const installments = data.installments;
    const valor = data.valor;
    const shopId = data.shopId;
    const orderId = data.orderId;
    const descricao = data.descricao;
    const paymentMethodId = data.paymentMethodId;
    const issuerId = data.issuerId;
    // CORREÇÃO 1: extrair CPF enviado pelo Flutter (via postMessage do HTML)
    const cpf = (data.cpf || '').replace(/\D/g, '');

    // Enforce plan restrictions: shops on free plan cannot process online card payments.
    // Reads subscription.plan_id (the field written by the Flutter SubscriptionService).
    if (shopId) {
      try {
        const shopDocCheck = await admin.firestore().collection('shops').doc(shopId).get();
        if (shopDocCheck.exists) {
          const shopData = shopDocCheck.data() || {};
          const sub = shopData.subscription || {};
          // Planos que NÃO SUPORTAM pagamento online (apenas o gratuito 'start')
          let planId = (sub.plan_id || shopData.plan || shopData.plan_id || '').toLowerCase();

          let isTrial = false;

          // Trial ativo (novo sistema)
          if (shopData.trial_active === true) {
            const trialEndsAt = shopData.trial_end_date?.toDate ? shopData.trial_end_date.toDate() : null;
            if (trialEndsAt && trialEndsAt > new Date()) {
              isTrial = true;
            }
          }

          // Trial ativo (legado)
          if (sub.status === 'trial') {
            const trialEndsAt = sub.trial_ends_at?.toDate ? sub.trial_ends_at.toDate() : null;
            if (trialEndsAt && trialEndsAt > new Date()) {
              isTrial = true;
            }
          }

          if (isTrial) {
            planId = 'flex'; // Trial dá acesso total
          }

          // Se o plano for explicitamente 'start' e não estiver em trial, bloqueia.
          if (planId === 'start' && !isTrial) {
            console.warn(`Pagamento bloqueado: loja ${shopId} está no plano '${planId}' (pagamento online não permitido)`);
            return res.status(403).json({
              success: false,
              error: 'Esta loja está no plano Start, que não permite pagamentos online. Solicite o agendamento via WhatsApp ou pagamento presencial.'
            });
          }
        }
      } catch (e) {
        console.error('Erro ao verificar plano da loja antes do pagamento:', e);
      }
    }

    console.log('📊 Dados recebidos:');
    console.log('   Token:', cardToken?.substring(0, 20) + '...');
    console.log('   Email:', email);
    console.log('   Valor:', valor);
    console.log('   Parcelas:', installments);

    // Validar dados
    if (!cardToken || !email || !shopId || !valor) {
      return res.status(400).json({
        success: false,
        error: 'Dados incompletos'
      });
    }

    // Obter Access Token da loja
    console.log('🔑 Buscando Access Token...');
    const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();

    if (!shopDoc.exists) {
      return res.status(404).json({
        success: false,
        error: 'Loja não encontrada'
      });
    }

    const shopData = shopDoc.data();
    const accessToken = shopData?.mercadopago?.access_token;

    if (!accessToken) {
      console.error('❌ Access Token não encontrado em Firebase');
      return res.status(400).json({
        success: false,
        error: 'Access Token não configurado na loja'
      });
    }

    console.log('✅ Access Token encontrado');

    // Chamar API Mercado Pago
    console.log('💳 Chamando API Mercado Pago...');

    // CORREÇÃO 1: payer.identification (CPF) incluído no payload para evitar rejeição antifraude do MP
    const payerObj = { email: email };
    if (cpf && cpf.length === 11) {
      payerObj.identification = { type: 'CPF', number: cpf };
      console.log('💳 CPF incluído no payload:', cpf.substring(0, 3) + '****' + cpf.substring(9));
    } else {
      console.warn('⚠️ CPF ausente ou inválido no payload. Pagamento pode ser rejeitado por antifraude.');
    }

    const mpPayload = {
      token: cardToken,
      transaction_amount: Number(valor),
      installments: Number(installments) || 1,
      payer: payerObj,
      description: descricao,
      capture: true,
      statement_descriptor: 'MarkaAI',
      external_reference: orderId,
    };
    if (paymentMethodId) {
      mpPayload.payment_method_id = paymentMethodId;
    }
    if (issuerId) {
      mpPayload.issuer_id = issuerId;
    }

    // Gerar chave de idempotência única para evitar pagamentos duplicados
    const idempotencyKey = `payment-${orderId}-${Date.now()}`;

    const mpResponse = await axios.post(
      'https://api.mercadopago.com/v1/payments',
      mpPayload,
      {
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
          'X-Idempotency-Key': idempotencyKey,
        },
      }
    );

    const mpData = mpResponse.data;
    console.log('✅ Resposta Mercado Pago:');
    console.log('   Status:', mpData.status);
    console.log('   ID:', mpData.id);

    // Processar resultado
    if (mpData.status === 'approved') {
      console.log('✅ PAGAMENTO APROVADO!');

      // Salvar em Firestore
      await admin.firestore().collection('approved_payments').doc(orderId).set({
        paymentId: mpData.id,
        status: mpData.status,
        statusDetail: mpData.status_detail,
        amount: valor,
        installments: installments,
        email: email,
        shopId: shopId,
        userId: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return res.status(200).json({
        success: true,
        paymentId: mpData.id,
        status: mpData.status,
        message: 'Pagamento aprovado com sucesso!',
      });

    } else if (mpData.status === 'pending') {
      console.log('⏳ PAGAMENTO PENDENTE');

      await admin.firestore().collection('pending_payments').doc(orderId).set({
        paymentId: mpData.id,
        status: mpData.status,
        statusDetail: mpData.status_detail,
        amount: valor,
        installments: installments,
        email: email,
        shopId: shopId,
        userId: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return res.status(200).json({
        success: true,
        paymentId: mpData.id,
        status: mpData.status,
        message: 'Pagamento pendente. Aguardando confirmação.',
      });

    } else {
      console.log('❌ PAGAMENTO RECUSADO:', mpData.status_detail);

      return res.status(200).json({
        success: false,
        status: mpData.status,
        error: traduzirErro(mpData.status_detail),
        message: 'Pagamento não foi aprovado',
      });
    }

  } catch (error) {
    console.error('❌ ERRO NA FUNÇÃO:', error.message);

    // Se for erro do Mercado Pago
    if (error.response?.data) {
      const mpError = error.response.data;
      console.error('Detalhes MP:', mpError);

      return res.status(400).json({
        success: false,
        error: mpError.message || 'Erro ao processar',
        details: mpError.cause,
      });
    }

    // Erro genérico
    return res.status(500).json({
      success: false,
      error: 'Erro ao processar pagamento: ' + error.message
    });
  }
});

// Função auxiliar para traduzir erros
function traduzirErro(statusDetail) {
  const erros = {
    'cc_rejected_insufficient_amount': 'Saldo insuficiente',
    'cc_rejected_bad_filled_security_code': 'CVV incorreto',
    'cc_rejected_bad_filled_date': 'Data de validade incorreta',
    'cc_rejected_other_reason': 'Recusado pelo banco',
    'cc_rejected_call_for_authorize': 'Ligue para seu banco',
    'cc_rejected_card_error': 'Erro no cartão',
    'cc_rejected_duplicated_payment': 'Pagamento duplicado',
    'cc_rejected_fraud': 'Transação suspeita de fraude',
  };

  return erros[statusDetail] || 'Pagamento recusado';
}

// ============================================================
// CORREÇÃO 3: WEBHOOK MERCADO PAGO
// Endpoint: POST /mercadoPagoWebhook
// Registrar no painel MP: https://www.mercadopago.com.br/developers/panel/app
// URL: https://us-central1-wismart-118c3.cloudfunctions.net/mercadoPagoWebhook
// ============================================================
exports.mercadoPagoWebhook = onRequest({ cors: false, secrets: ['MP_WEBHOOK_SECRET'] }, async (req, res) => {
  // Responde 200 IMEDIATAMENTE para evitar timeout/retry do Mercado Pago
  res.status(200).send('OK');

  try {
    if (req.method !== 'POST') return;

    // 1. Verificar assinatura X-Signature (segurança crítica em produção)
    const xSignature = req.headers['x-signature'];
    const xRequestId = req.headers['x-request-id'];
    let webhookSecret = null;
    try {
      webhookSecret = MP_WEBHOOK_SECRET.value() || null;
    } catch (e) { webhookSecret = null; }


    if (xSignature && webhookSecret) {
      try {
        const crypto = require('crypto');
        const parts = xSignature.split(',');
        let ts = null; let v1 = null;
        parts.forEach(part => {
          const [k, v] = part.trim().split('=');
          if (k === 'ts') ts = v;
          if (k === 'v1') v1 = v;
        });
        const dataId = req.body?.data?.id;
        if (ts && v1 && dataId) {
          const manifest = `id:${dataId};request-id:${xRequestId || ''};ts:${ts};`;
          const hmac = crypto.createHmac('sha256', webhookSecret);
          hmac.update(manifest);
          const expected = hmac.digest('hex');
          if (expected !== v1) {
            console.error('Webhook MP: assinatura X-Signature inválida. Evento ignorado.');
            await admin.firestore().collection('webhook_logs').add({
              source: 'mercadopago', event_type: req.body?.type || 'unknown',
              resource_id: String(req.body?.data?.id || ''), payload: req.body,
              processed: false, processed_at: null,
              error_message: 'Assinatura X-Signature inválida',
              created_at: admin.firestore.FieldValue.serverTimestamp()
            });
            return;
          }
        }
      } catch (sigErr) {
        console.warn('Webhook MP: erro ao verificar assinatura (continuando):', sigErr.message);
      }
    }

    const eventType = req.body?.type;
    const resourceId = req.body?.data?.id;

    if (!eventType || !resourceId) {
      console.warn('Webhook MP: payload inválido recebido', JSON.stringify(req.body));
      return;
    }

    console.log(`Webhook MP recebido: type=${eventType} id=${resourceId}`);

    // 2. Verificar idempotência — não processar evento duplicado
    const logsRef = admin.firestore().collection('webhook_logs');
    const existing = await logsRef
      .where('resource_id', '==', String(resourceId))
      .where('event_type', '==', eventType)
      .where('processed', '==', true)
      .limit(1)
      .get();

    if (!existing.empty) {
      console.log(`Webhook MP: evento duplicado ignorado. type=${eventType} id=${resourceId}`);
      return;
    }

    // 3. Registrar evento como recebido
    const logRef = await logsRef.add({
      source: 'mercadopago', event_type: eventType,
      resource_id: String(resourceId), payload: req.body,
      processed: false, processed_at: null, error_message: null,
      created_at: admin.firestore.FieldValue.serverTimestamp()
    });

    // 4. Processar conforme tipo de evento
    if (eventType === 'payment') {
      await _webhookProcessarPagamento(String(resourceId), logRef);
    } else if (eventType === 'subscription_authorized_payment' || eventType === 'preapproval') {
      await _webhookProcessarPreapproval(String(resourceId), logRef);
    } else {
      console.log(`Webhook MP: tipo não tratado: ${eventType}`);
      await logRef.update({
        processed: true, processed_at: admin.firestore.FieldValue.serverTimestamp(),
        error_message: `Tipo de evento não tratado: ${eventType}`
      });
    }

  } catch (error) {
    console.error('Webhook MP: erro ao processar evento:', error.message || error);
  }
});

// Processa evento de pagamento recebido via webhook
async function _webhookProcessarPagamento(paymentId, logRef) {
  try {
    // Buscar o pagamento nos registros locais para identificar a loja
    let accessToken = null;
    let shopId = null;

    // Procurar em pending_payments (coleção raiz)
    const pendingSnap = await admin.firestore()
      .collection('pending_payments')
      .where('paymentId', '==', paymentId)
      .limit(1)
      .get();

    if (!pendingSnap.empty) {
      const pendingData = pendingSnap.docs[0].data();
      shopId = pendingData.shopId;
    }

    // Procurar em approved_payments se não encontrou
    if (!shopId) {
      const approvedSnap = await admin.firestore()
        .collection('approved_payments')
        .where('paymentId', '==', paymentId)
        .limit(1)
        .get();
      if (!approvedSnap.empty) {
        shopId = approvedSnap.docs[0].data().shopId;
      }
    }

    if (shopId) {
      const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
      accessToken = shopDoc.exists ? shopDoc.data()?.mercadopago?.access_token : null;
    }

    if (!accessToken) {
      throw new Error(`Não foi possível encontrar access_token para o pagamento ${paymentId}`);
    }

    // Busca detalhes do pagamento na API do MP
    const mpResp = await axios.get(
      `https://api.mercadopago.com/v1/payments/${paymentId}`,
      { headers: { Authorization: `Bearer ${accessToken}` } }
    );
    const payment = mpResp.data;
    const status = payment.status;
    const orderId = payment.external_reference;

    console.log(`Webhook MP: pagamento ${paymentId} status=${status} orderId=${orderId}`);

    if (status === 'approved' && orderId) {
      // Mover de pending_payments para approved_payments
      const pendingRef = admin.firestore().collection('pending_payments').doc(orderId);
      const pendingDoc = await pendingRef.get();
      if (pendingDoc.exists) {
        const pd = pendingDoc.data();
        await admin.firestore().collection('approved_payments').doc(orderId).set({
          ...pd, status: 'approved', approvedAt: admin.firestore.FieldValue.serverTimestamp(),
          webhookConfirmed: true
        });
        await pendingRef.delete();

        // Atualizar agendamento associado se existir
        if (orderId) {
          const apptSnap = await admin.firestore()
            .collection('appointments')
            .where('payment_id', '==', orderId)
            .limit(1).get();
          if (!apptSnap.empty) {
            await apptSnap.docs[0].ref.update({
              status: 'confirmado', paymentStatus: 'approved',
              confirmedAt: admin.firestore.FieldValue.serverTimestamp()
            });
            console.log(`Webhook MP: agendamento ${apptSnap.docs[0].id} confirmado via PIX.`);
          }
        }
      }
    } else if (status === 'rejected' && orderId) {
      const pendingRef = admin.firestore().collection('pending_payments').doc(orderId);
      await pendingRef.update({
        status: 'rejected', statusDetail: payment.status_detail,
        rejectedAt: admin.firestore.FieldValue.serverTimestamp()
      }).catch(() => { });
    }

    await logRef.update({ processed: true, processed_at: admin.firestore.FieldValue.serverTimestamp() });
  } catch (error) {
    console.error(`Webhook MP: erro ao processar pagamento ${paymentId}:`, error.message);
    await logRef.update({ processed: false, error_message: error.message }).catch(() => { });
  }
}

// Processa eventos de preapproval/assinatura
async function _webhookProcessarPreapproval(resourceId, logRef) {
  try {
    console.log(`Webhook MP: processando preapproval ${resourceId}`);
    const subsSnap = await admin.firestore()
      .collection('subscriptions')
      .where('mp_subscription_id', '==', resourceId)
      .limit(1).get();
    if (!subsSnap.empty) {
      await subsSnap.docs[0].ref.update({
        webhookLastEvent: 'preapproval',
        webhookLastEventAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }
    await logRef.update({ processed: true, processed_at: admin.firestore.FieldValue.serverTimestamp() });
  } catch (error) {
    console.error(`Webhook MP: erro ao processar preapproval ${resourceId}:`, error.message);
    await logRef.update({ processed: false, error_message: error.message }).catch(() => { });
  }
}



// ============================================================
// CORREÇÃO 4: CRIAR ASSINATURA (chamado por subscription_service.dart)
// Registra a intenção de assinatura no Firestore e retorna status.
// O checkout real é feito via checkout_transparente via CheckoutTransparentePage.
// ============================================================
exports.createSubscription = onRequest({ cors: true }, async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(204).send('');

  try {
    const data = req.body.data || req.body;
    const { shopId, planId, planName, planPrice, billingCycle, idToken } = data;

    // Autenticação obrigatória
    if (!idToken) {
      return res.status(401).json({ success: false, error: 'Autenticação necessária.' });
    }
    let uid;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken, true);
      uid = decoded.uid;
    } catch (authErr) {
      return res.status(401).json({ success: false, error: 'Sessão inválida. Faça login novamente.' });
    }

    if (!shopId || !planId || !planPrice) {
      return res.status(400).json({ success: false, error: 'shopId, planId e planPrice são obrigatórios.' });
    }

    // Verifica se a loja existe e tem MP configurado
    const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
    if (!shopDoc.exists) {
      return res.status(404).json({ success: false, error: 'Loja não encontrada.' });
    }
    const shopData = shopDoc.data();
    const mpAccessToken = shopData?.mercadopago?.access_token;
    if (!mpAccessToken) {
      return res.status(400).json({ success: false, error: 'Loja não possui Mercado Pago configurado.' });
    }

    // Registra a assinatura pendente no Firestore
    const now = admin.firestore.FieldValue.serverTimestamp();
    const subscriptionData = {
      plan_id: planId,
      plan_name: planName,
      plan_price: Number(planPrice),
      billing_cycle: billingCycle || 'monthly',
      status: 'pending_payment',
      uid: uid,
      shop_id: shopId,
      created_at: now,
      updated_at: now,
    };

    await admin.firestore()
      .collection('shops').doc(shopId)
      .update({ subscription: { ...subscriptionData, status: 'pending_payment' } });

    // Log de assinatura
    await admin.firestore().collection('subscription_events').add({
      shop_id: shopId,
      uid: uid,
      plan_id: planId,
      event: 'subscription_initiated',
      created_at: now,
    });

    console.log(`createSubscription: loja ${shopId} iniciou assinatura plano ${planId}`);

    return res.status(200).json({
      success: true,
      message: `Assinatura do plano ${planName} iniciada. Aguardando pagamento.`,
      subscriptionData,
    });
  } catch (error) {
    console.error('createSubscription error:', error.message);
    return res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================
// 🔍 GOOGLE PLACES API - AVALIAÇÕES
// ============================================


// Função para pesquisar estabelecimentos no Google
exports.searchGoogleBusiness = onRequest({ cors: true }, async (req, res) => {
  // CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(204).send('');
  }

  try {
    const { query } = req.body;

    if (!query) {
      return res.status(400).json({ error: 'Query de pesquisa é obrigatória' });
    }

    // A API key deve estar definida como variável de ambiente
    // Configure no .env.local: GOOGLE_PLACES_API_KEY="SUA_KEY_AQUI"
    const apiKey = GOOGLE_PLACES_API_KEY.value();

    if (!apiKey) {
      console.error('❌ Google Places API Key não configurada');
      return res.status(500).json({
        error: 'Google Places API não está configurada. Configure a variável de ambiente GOOGLE_PLACES_API_KEY'
      });
    }

    // Buscar estabelecimentos usando Text Search
    const searchUrl = `https://maps.googleapis.com/maps/api/place/textsearch/json`;
    const searchResponse = await axios.get(searchUrl, {
      params: {
        query: query,
        key: apiKey,
        language: 'pt-BR',
      }
    });

    if (searchResponse.data.status !== 'OK' && searchResponse.data.status !== 'ZERO_RESULTS') {
      console.error('Erro Google Places API:', searchResponse.data);
      return res.status(400).json({
        error: 'Erro na busca: ' + searchResponse.data.status,
        details: searchResponse.data.error_message
      });
    }

    const results = searchResponse.data.results.map(place => ({
      place_id: place.place_id,
      name: place.name,
      address: place.formatted_address,
      rating: place.rating || 0,
      user_ratings_total: place.user_ratings_total || 0,
      types: place.types || [],
      photos: place.photos ? place.photos.slice(0, 1).map(photo => ({
        reference: photo.photo_reference
      })) : []
    }));

    return res.status(200).json({
      success: true,
      results: results
    });

  } catch (error) {
    console.error('❌ Erro ao buscar estabelecimentos:', error.message);
    return res.status(500).json({
      error: 'Erro ao buscar: ' + error.message
    });
  }
});

// Função para buscar detalhes e avaliações de um estabelecimento
exports.getGoogleReviews = onRequest({ cors: true }, async (req, res) => {
  // CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(204).send('');
  }

  try {
    const { place_id } = req.body;

    if (!place_id) {
      return res.status(400).json({ error: 'place_id é obrigatório' });
    }

    const apiKey = GOOGLE_PLACES_API_KEY.value();

    if (!apiKey) {
      console.error('❌ Google Places API Key não configurada');
      return res.status(500).json({
        error: 'Google Places API não está configurada. Configure a variável de ambiente GOOGLE_PLACES_API_KEY'
      });
    }

    // Buscar detalhes do estabelecimento
    const detailsUrl = `https://maps.googleapis.com/maps/api/place/details/json`;
    const detailsResponse = await axios.get(detailsUrl, {
      params: {
        place_id: place_id,
        fields: 'name,rating,user_ratings_total,reviews,formatted_address,photos',
        key: apiKey,
        language: 'pt-BR',
      }
    });

    if (detailsResponse.data.status !== 'OK') {
      console.error('Erro ao buscar detalhes:', detailsResponse.data);
      return res.status(400).json({
        error: 'Erro ao buscar detalhes: ' + detailsResponse.data.status
      });
    }

    const place = detailsResponse.data.result;

    // Formatar avaliações
    const reviews = (place.reviews || []).map(review => ({
      author_name: review.author_name,
      author_url: review.author_url,
      profile_photo_url: review.profile_photo_url,
      rating: review.rating,
      relative_time_description: review.relative_time_description,
      text: review.text,
      time: review.time
    }));

    return res.status(200).json({
      success: true,
      place_id: place_id,
      name: place.name,
      rating: place.rating || 0,
      user_ratings_total: place.user_ratings_total || 0,
      address: place.formatted_address,
      reviews: reviews,
      photos: place.photos ? place.photos.slice(0, 3).map(photo => ({
        reference: photo.photo_reference
      })) : []
    });

  } catch (error) {
    console.error('❌ Erro ao buscar avaliações:', error.message);
    return res.status(500).json({
      error: 'Erro ao buscar avaliações: ' + error.message
    });
  }
});

// Função HTTP para enviar notificações de teste a partir do painel admin
exports.sendTestNotification = onRequest({ cors: true }, async (req, res) => {
  // CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') return res.status(204).send('');

  try {
    if (!req.body || !req.body.appointmentId || !req.body.type) {
      return res.status(400).json({ error: 'appointmentId and type are required' });
    }

    // Verify Firebase ID token from Authorization header (Bearer ...)
    const authHeader = (req.get('Authorization') || '');
    const match = authHeader.match(/Bearer\s+(.*)/i);
    if (!match) return res.status(401).json({ error: 'Missing or invalid Authorization header' });
    const idToken = match[1];
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(idToken);
    } catch (e) {
      return res.status(401).json({ error: 'Invalid token' });
    }
    const claims = decoded || {};
    if (!claims.admin && !claims.admin_dev) {
      return res.status(403).json({ error: 'Forbidden: admin only' });
    }

    const { appointmentId, type } = req.body;

    const apptRef = await admin.firestore().collection('appointments').doc(appointmentId).get();
    if (!apptRef.exists) return res.status(404).json({ error: 'Appointment not found' });
    const appt = apptRef.data();

    // Compose message
    const appointmentDate = appt.data_agendamento ? (appt.data_agendamento.toDate ? appt.data_agendamento.toDate() : new Date()) : null;
    const dateStr = appointmentDate ? appointmentDate.toLocaleString('pt-BR') : '';
    let title = 'Notificação de teste';
    let body = 'Teste de notificação';
    let targetTokens = [];

    if (type === 'new' || type === 'agendamento') {
      title = '🎉 Novo Agendamento (Teste)';
      body = `${appt.client_nome || 'Cliente'} agendou ${appt.servico_nome || 'serviço'} para ${dateStr}`;
      // send to shop
      const shopDoc = await admin.firestore().collection('shops').doc(appt.shopId).get();
      if (shopDoc.exists) targetTokens = shopDoc.data().fcm_tokens || [];
    } else if (type === 'cancel' || type === 'cancelamento') {
      title = '❌ Agendamento Cancelado (Teste)';
      body = `Agendamento de ${appt.client_nome || 'Cliente'} em ${dateStr} foi cancelado (teste)`;
      const shopDoc = await admin.firestore().collection('shops').doc(appt.shopId).get();
      if (shopDoc.exists) targetTokens = shopDoc.data().fcm_tokens || [];
    } else if (type === 'reminder' || type === 'lembrete') {
      title = '⏰ Lembrete de Agendamento (Teste)';
      body = `Lembrete: ${appt.client_nome || 'Cliente'} tem agendamento em ${dateStr}`;
      // send to client and shop
      const userDoc = await admin.firestore().collection('users').doc(appt.clientId).get();
      if (userDoc.exists) targetTokens = (userDoc.data().fcmTokens || []);
      const shopDoc = await admin.firestore().collection('shops').doc(appt.shopId).get();
      if (shopDoc.exists) targetTokens = targetTokens.concat(shopDoc.data().fcm_tokens || []);
    } else {
      return res.status(400).json({ error: 'Unknown type' });
    }

    // Deduplicate tokens
    targetTokens = Array.isArray(targetTokens) ? [...new Set(targetTokens.filter(Boolean))] : [];

    if (targetTokens.length === 0) {
      return res.status(200).json({ success: true, message: 'No tokens found to send' });
    }

    const data = {
      type: type,
      appointmentId,
      shopId: appt.shopId,
      clientId: appt.clientId,
    };

    const message = {
      notification: { title, body },
      data,
      tokens: targetTokens,
    };

    const resp = await admin.messaging().sendEachForMulticast(message);
    return res.status(200).json({ success: true, sent: resp.successCount, failed: resp.failureCount });

  } catch (error) {
    console.error('sendTestNotification error:', error);
    return res.status(500).json({ error: 'Internal error' });
  }
});

// Função HTTP para adicionar uma tag a um usuário para uma loja específica e notificar
exports.addTagToUser = onRequest({ cors: true }, async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(204).send('');

  try {
    const authHeader = (req.get('Authorization') || '');
    const match = authHeader.match(/Bearer\s+(.*)/i);
    if (!match) return res.status(401).json({ error: 'Missing Authorization header' });
    const idToken = match[1];
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(idToken);
    } catch (e) {
      return res.status(401).json({ error: 'Invalid token' });
    }
    const claims = decoded || {};
    if (!claims.admin && !claims.admin_dev) {
      return res.status(403).json({ error: 'Forbidden: admin only' });
    }

    const body = req.body || {};
    const userId = body.userId;
    const shopId = body.shopId;
    const tag = (body.tag || '').toString().trim();
    if (!userId || !shopId || !tag) return res.status(400).json({ error: 'userId, shopId and tag are required' });

    // Update user's shop_tags map
    const userRef = admin.firestore().collection('users').doc(userId);
    const userDoc = await userRef.get();
    if (!userDoc.exists) return res.status(404).json({ error: 'User not found' });

    // Structure: shop_tags: { [shopId]: ['VIP', ...] }
    const userData = userDoc.data() || {};
    const shopTags = userData.shop_tags || {};
    const tagsForShop = Array.isArray(shopTags[shopId]) ? shopTags[shopId] : [];
    if (!tagsForShop.includes(tag)) {
      // add tag
      tagsForShop.push(tag);
      shopTags[shopId] = tagsForShop;
      await userRef.set({ shop_tags: shopTags }, { merge: true });
    }

    // Log audit
    await admin.firestore().collection('admin_audit').add({
      adminUid: decoded.uid,
      action: 'add_tag',
      targetId: userId,
      shopId,
      tag,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Try to notify the user
    const tokens = userData.fcmTokens || [];
    if (Array.isArray(tokens) && tokens.length > 0) {
      const title = '🎖️ Você recebeu uma nova classificação';
      const bodyMsg = `Você foi marcado como "${tag}" na loja ${shopId}.`;
      const message = {
        notification: { title, body: bodyMsg },
        data: { type: 'tag_added', tag, shopId, userId },
        tokens: tokens,
      };
      try {
        const resp = await admin.messaging().sendEachForMulticast(message);
        console.log('Tag notification sent:', resp.successCount, 'failed:', resp.failureCount);
      } catch (e) {
        console.error('Error sending tag notification:', e);
      }
    }

    return res.status(200).json({ success: true, tagAdded: true });
  } catch (e) {
    console.error('addTagToUser error:', e);
    return res.status(500).json({ error: 'Internal error' });
  }
});

// Função HTTP para deletar a conta do usuário autenticado (usa Admin SDK para evitar necessidade de re-autenticação)
exports.deleteUserAccount = onRequest({ cors: true }, async (req, res) => {
  // CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  if (req.method === 'OPTIONS') return res.status(204).send('');

  try {
    const authHeader = (req.get('Authorization') || '');
    const match = authHeader.match(/Bearer\s+(.*)/i);
    if (!match) return res.status(401).json({ error: 'Missing Authorization header' });
    const idToken = match[1];
    let decoded;
    try {
      decoded = await admin.auth().verifyIdToken(idToken);
    } catch (e) {
      return res.status(401).json({ error: 'Invalid token' });
    }

    const uid = decoded.uid;
    if (!uid) return res.status(400).json({ error: 'Invalid token payload' });

    // Optional: require explicit confirmation in body
    const body = req.body || {};
    if (!body.confirm) {
      return res.status(400).json({ error: 'Missing confirm flag in body' });
    }

    // Delete the user from Firebase Auth using Admin SDK (no recent login required)
    try {
      await admin.auth().deleteUser(uid);
    } catch (e) {
      console.error('Error deleting auth user:', e);
      return res.status(500).json({ error: 'Failed to delete auth user', details: e.message });
    }

    // Mark Firestore user doc as deleted (audit) but do not remove it
    try {
      await admin.firestore().collection('users').doc(uid).set({
        deleted: true,
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        nome: 'Conta excluída',
      }, { merge: true });
    } catch (e) {
      console.error('Failed to mark user as deleted in Firestore:', e);
    }

    return res.status(200).json({ success: true });
  } catch (e) {
    console.error('deleteUserAccount error:', e);
    return res.status(500).json({ error: 'Internal error' });
  }
});

// Subscriptions: create subscription (with optional trial) - callable by authenticated client/admin
exports.createSubscription = onCall(async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Usuário não autenticado');
  }
  const { userId, shopId, planId, wantTrial } = request.data;
  if (!userId || !planId) {
    throw new functions.https.HttpsError('invalid-argument', 'userId and planId required');
  }

  // Basic plan price map (can be moved to config)
  const planPrices = {
    start: 0,
    flex: 29.90,
    plus: 69.90,
    prime: 149.90
  };
  const price = planPrices[planId] || 0;

  const now = admin.firestore.Timestamp.now();
  let trialEnd = null;
  let status = 'active';
  let nextBilling = null;
  if (wantTrial === true) {
    // 1 month trial
    const trialDate = new Date();
    trialDate.setDate(trialDate.getDate() + 30);
    trialEnd = admin.firestore.Timestamp.fromDate(trialDate);
    status = 'trialing';
    nextBilling = admin.firestore.Timestamp.fromDate(new Date(trialDate.getTime() + 0)); // placeholder
  } else {
    // immediate active, set next billing in 30 days
    const nb = new Date();
    nb.setDate(nb.getDate() + 30);
    nextBilling = admin.firestore.Timestamp.fromDate(nb);
    status = price > 0 ? 'active' : 'active';
  }

  const subDoc = {
    userId,
    shopId: shopId || null,
    planId,
    price,
    status,
    trial_end: trialEnd,
    next_billing: nextBilling,
    createdAt: now,
    updatedAt: now,
  };

  const ref = await admin.firestore().collection('subscriptions').add(subDoc);

  // audit
  await admin.firestore().collection('admin_audit').add({
    adminUid: request.auth.uid,
    action: 'create_subscription',
    targetId: ref.id,
    subscription: subDoc,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // If subscription is for a shop, update shop document plan immediately
  try {
    if (shopId) {
      await admin.firestore().collection('shops').doc(shopId).set({ plan: planId }, { merge: true });
    }
  } catch (e) {
    console.error('Erro ao atualizar plan da shop após criar subscription:', e);
  }

  return { success: true, subscriptionId: ref.id };
});

// Scheduled worker: runs daily to process trials and billing
// Scheduled via Cloud Scheduler: every day at 06:00 BRT
// URL: https://us-central1-wismart-118c3.cloudfunctions.net/checkSubscriptionsDaily
exports.checkSubscriptionsDaily = onRequest({ cors: true }, async (req, res) => {
  // Opcional: proteger com segredo para evitar chamadas externas indesejadas
  const authKey = req.headers['x-cron-key'] || req.query.key;
  const cronSecret = process.env.CRON_SECRET || 'markaai-cron-2026';
  if (authKey !== cronSecret) {
    console.warn('checkSubscriptionsDaily: chave inválida');
    return res.status(403).json({ error: 'Forbidden' });
  }

  const results = { trials_expired: 0, renewals_ok: 0, renewals_failed: 0, downgrades: 0, errors: 0 };

  try {
    console.log('checkSubscriptionsDaily starting…');

    const now = admin.firestore.Timestamp.now();

    // ─── Helper: cobrar cartão salvo ───────────────────────────────────────
    async function chargeCard(sub, shopAccessToken, userEmail) {
      if (!sub.paymentMethod?.token) return null;
      const payload = {
        token: sub.paymentMethod.token,
        transaction_amount: Number(sub.price) || 0,
        installments: 1,
        payer: { email: userEmail || 'cliente@markaai.com' },
        capture: true,
        description: `Assinatura ${sub.planId} - MarkaAI`,
        external_reference: `sub-${sub._id}`,
      };
      const resp = await axios.post('https://api.mercadopago.com/v1/payments', payload, {
        headers: { Authorization: `Bearer ${shopAccessToken}`, 'Content-Type': 'application/json' },
      });
      return resp.data;
    }

    // ─── Helper: notificar usuário via FCM ────────────────────────────────
    async function notifyUser(userId, title, body) {
      try {
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        const tokens = userDoc.exists ? (userDoc.data().fcmTokens || userDoc.data().fcm_tokens || []) : [];
        if (!tokens.length) return;
        await admin.messaging().sendEachForMulticast({
          notification: { title, body },
          data: { type: 'subscription_update' },
          tokens,
        });
      } catch (e) { console.warn('notifyUser error:', e.message); }
    }

    // ─── Helper: downgrade da loja para free ─────────────────────────────
    async function downgradeShop(shopId, userId, subRef, reason) {
      if (shopId) {
        await admin.firestore().collection('shops').doc(shopId).set(
          { plan: 'free', plan_expires_at: null, subscription_status: 'cancelled' }, { merge: true }
        );
      }
      if (userId) {
        await admin.firestore().collection('users').doc(userId).set({ plan: 'free' }, { merge: true });
      }
      await subRef.update({
        status: 'cancelled',
        cancelled_reason: reason,
        cancelled_at: admin.firestore.Timestamp.now(),
        updatedAt: admin.firestore.Timestamp.now(),
      });
      await admin.firestore().collection('admin_audit').add({
        adminUid: 'system', action: 'auto_downgrade', shopId, userId, reason,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      results.downgrades++;
    }

    // ─── 1. TRIALS EXPIRADOS ────────────────────────────────────────────

    const trialSnap = await admin.firestore().collection('subscriptions')
      .where('status', '==', 'trialing')
      .where('trial_end', '<=', now)
      .get();

    for (const doc of trialSnap.docs) {
      const s = { ...doc.data(), _id: doc.id };
      try {
        const userId = s.userId;
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        const user = userDoc.exists ? userDoc.data() : {};
        const paymentMethod = user?.paymentMethod || s?.paymentMethod || null;

        if (paymentMethod?.type === 'card' && s.shopId) {
          const shopDoc = await admin.firestore().collection('shops').doc(s.shopId).get();
          const accessToken = shopDoc.exists ? shopDoc.data()?.mercadopago?.access_token : null;
          if (accessToken) {
            try {
              const charge = await chargeCard({ ...s, paymentMethod }, accessToken, user?.email);
              if (charge && (charge.status === 'approved' || charge.status === 'pending')) {
                const nb = new Date(); nb.setDate(nb.getDate() + 30);
                await doc.ref.update({
                  status: 'active', next_billing: admin.firestore.Timestamp.fromDate(nb),
                  retry_count: 0, last_payment_id: charge.id, updatedAt: admin.firestore.Timestamp.now(),
                });
                await admin.firestore().collection('shops').doc(s.shopId).set(
                  { plan: s.planId, plan_expires_at: admin.firestore.Timestamp.fromDate(nb) }, { merge: true }
                );
                await notifyUser(userId, '✅ Assinatura Ativa', `Plano ${s.planId.toUpperCase()} renovado com sucesso!`);
                results.renewals_ok++;
                continue;
              }
            } catch (e) { console.error('Trial charge failed:', e.message); }
          }
        }

        // Sem cartão ou cobrança falhou → downgrade
        await downgradeShop(s.shopId, userId, doc.ref, 'trial_expired_no_payment');
        await notifyUser(userId, '⚠️ Trial Expirado', 'Atualize seu plano para continuar usando recursos premium.');
        results.trials_expired++;
      } catch (err) {
        console.error('Error processing trial:', doc.id, err);
        results.errors++;
      }
    }

    // 2) process recurring billing due today or past due
    const billingSnap = await admin.firestore().collection('subscriptions')
      .where('status', 'in', ['active', 'past_due'])
      .where('next_billing', '<=', now)
      .get();

    for (const doc of billingSnap.docs) {
      const s = { ...doc.data(), _id: doc.id };
      try {
        const userId = s.userId;
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        const user = userDoc.exists ? userDoc.data() : {};
        const paymentMethod = user?.paymentMethod || s?.paymentMethod || null;
        const retryCount = s.retry_count || 0;

        // Após 3 falhas → downgrade automático
        if (retryCount >= 3) {
          await downgradeShop(s.shopId, userId, doc.ref, 'max_retries_exceeded');
          await notifyUser(userId, '❌ Assinatura Cancelada', `Após ${retryCount} tentativas falhadas, seu plano foi revertido para o gratuito.`);
          continue;
        }

        if (paymentMethod?.type === 'card' && s.shopId) {
          const shopDoc = await admin.firestore().collection('shops').doc(s.shopId).get();
          const accessToken = shopDoc.exists ? shopDoc.data()?.mercadopago?.access_token : null;
          if (accessToken) {
            try {
              const charge = await chargeCard({ ...s, paymentMethod }, accessToken, user?.email);
              if (charge && charge.status === 'approved') {
                const nb = new Date(); nb.setDate(nb.getDate() + 30);
                await doc.ref.update({
                  status: 'active', next_billing: admin.firestore.Timestamp.fromDate(nb),
                  retry_count: 0, last_payment_id: charge.id, updatedAt: admin.firestore.Timestamp.now(),
                });
                await admin.firestore().collection('shops').doc(s.shopId).set(
                  { plan: s.planId, plan_expires_at: admin.firestore.Timestamp.fromDate(nb) }, { merge: true }
                );
                await notifyUser(userId, '✅ Renovação OK', `Plano ${s.planId.toUpperCase()} renovado. Próxima cobrança em 30 dias.`);
                await admin.firestore().collection('admin_audit').add({
                  adminUid: 'system', action: 'recurring_charge_success',
                  targetId: doc.id, paymentId: charge.id, createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });
                results.renewals_ok++;
                continue;
              } else {
                await doc.ref.update({
                  status: 'past_due', retry_count: retryCount + 1,
                  last_charge_status: charge?.status, updatedAt: admin.firestore.Timestamp.now(),
                });
                await notifyUser(userId, '⚠️ Falha na Renovação', `Não conseguimos cobrar seu cartão. Tentativa ${retryCount + 1} de 3.`);
                results.renewals_failed++;
                continue;
              }
            } catch (e) {
              console.error('Recurring charge error:', e.message);
              await doc.ref.update({
                status: 'past_due', retry_count: retryCount + 1, updatedAt: admin.firestore.Timestamp.now(),
              });
              results.renewals_failed++;
              continue;
            }
          }
        }

        // Sem cartão → past_due + notifica
        await doc.ref.update({
          status: 'past_due', retry_count: retryCount + 1, updatedAt: admin.firestore.Timestamp.now(),
        });
        await admin.firestore().collection('admin_notifications').add({
          level: 'warning',
          message: `Subscription ${doc.id} past due — sem método de pagamento`,
          subscriptionId: doc.id, shopId: s.shopId, createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await notifyUser(userId, '⚠️ Pagamento Pendente', 'Adicione um cartão ao seu perfil para renovar seu plano.');
        results.renewals_failed++;
      } catch (err) {
        console.error('Error processing recurring subscription:', doc.id, err);
        results.errors++;
      }
    }

    console.log('checkSubscriptionsDaily finished:', results);
    return res.status(200).json({ success: true, results });
  } catch (err) {
    console.error('checkSubscriptionsDaily fatal error:', err);
    return res.status(500).json({ error: String(err) });
  }
});

// ============================================================
// CRON: Cloud Scheduler automático — criado pelo Firebase no deploy
// Roda todos os dias às 06:00 BRT (09:00 UTC)
// Chama a lógica de renovação de assinaturas sem precisar de gcloud
// ============================================================
exports.checkSubscriptionsScheduled = onSchedule(
  { schedule: '0 9 * * *', timeZone: 'America/Sao_Paulo', region: 'us-central1' },
  async (event) => {
    console.log('checkSubscriptionsScheduled: triggered by Cloud Scheduler', event?.scheduleTime);

    // Reutiliza o mesmo endpoint HTTP internamente para não duplicar código
    try {
      const axios = require('axios');
      const resp = await axios.post(
        'https://checksubscriptionsdaily-jvae5gyh3q-uc.a.run.app',
        {},
        { headers: { 'x-cron-key': process.env.CRON_SECRET || 'markaai-cron-2026' } }
      );
      console.log('checkSubscriptionsScheduled: result', resp.data);
    } catch (err) {
      console.error('checkSubscriptionsScheduled: falha ao chamar endpoint HTTP', err.message);
    }
  }
);

// Função administrativa para popular planos (executar uma vez)
exports.seedPlans = onRequest({ cors: true }, async (req, res) => {
  try {
    const plans = [
      {
        id: 'start',
        name: 'START',
        price_month: 0,
        features: ['agendamentos', 'link_personalizado', 'pagamento_presencial'],
        description: 'Plano gratuito básico: apenas agenda, link personalizado e pagamento presencial.'
      },
      {
        id: 'flex',
        name: 'FLEX',
        price_month: 29.9,
        features: ['agendamentos', 'link_personalizado', 'pagamento_online', 'relatorios_basicos'],
        description: 'Recursos adicionais, pagamentos online e relatórios básicos.'
      },
      {
        id: 'plus',
        name: 'PLUS',
        price_month: 69.9,
        features: ['agendamentos', 'pagamento_online', 'relatorios_avancados', 'tags', 'categorias', 'api_admin'],
        description: 'Segmentação, tags VIP, categorias e relatórios avançados.'
      },
      {
        id: 'prime',
        name: 'PRIME',
        price_month: 149.9,
        features: ['tudo', 'prioridade_suporte', 'white_label', 'integracoes'],
        description: 'Plano empresarial completo.'
      },
    ];

    for (const p of plans) {
      await admin.firestore().collection('plans').doc(p.id).set(p, { merge: true });
    }

    return res.status(200).json({ success: true, created: plans.map(p => p.id) });
  } catch (e) {
    console.error('seedPlans error:', e);
    return res.status(500).json({ error: 'seed failed' });
  }
});

// ============================================
// 🔔 SISTEMA DE NOTIFICAÇÕES PUSH
// ============================================

// Função auxiliar para enviar notificação
async function sendPushNotification(tokens, title, body, data = {}) {
  if (!tokens || tokens.length === 0) {
    console.log('⚠️ Nenhum token FCM disponível');
    return;
  }

  const message = {
    notification: {
      title: title,
      body: body,
    },
    data: data,
    tokens: Array.isArray(tokens) ? tokens : [tokens],
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`✅ Notificações enviadas: ${response.successCount} sucesso, ${response.failureCount} falhas`);

    // Remover tokens inválidos
    if (response.failureCount > 0) {
      const failedTokens = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          failedTokens.push(tokens[idx]);
          console.log(`❌ Token falhou: ${tokens[idx].substring(0, 20)}... - ${resp.error}`);
        }
      });
      return failedTokens;
    }
    return [];
  } catch (error) {
    console.error('❌ Erro ao enviar notificação:', error);
    return [];
  }
}

// ─────────────────────────────────────────────────────────
// FASE 1 — Ambiente de Testes: usuário, loja, serviços, agenda, pagamento
// Protegido por x-admin-key. Usar apenas em ambiente de TEST.
// ─────────────────────────────────────────────────────────
exports.seedTestEnvironment = onRequest({ cors: true }, async (req, res) => {
  const adminKey = req.headers['x-admin-key'] || req.query.key;
  if (adminKey !== (process.env.CRON_SECRET || 'markaai-cron-2026')) {
    return res.status(403).json({ error: 'Forbidden' });
  }

  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const results = {};

  try {
    // ─── 1.1 Usuário CLIENTE de teste ────────────────────
    const clienteId = 'test_cliente_001';
    await db.collection('users').doc(clienteId).set({
      nome: 'Cliente Teste',
      email: 'cliente.teste@markaai.com.br',
      tipo: 'cliente',
      cpf: '111.444.777-35', // CPF válido para testes MP
      telefone: '11999998888',
      createdAt: now,
      _test: true,
    }, { merge: true });
    results['1.1_cliente'] = `✅ users/${clienteId}`;

    // ─── 1.2 Usuário LOJISTA de teste ────────────────────
    const lojistaNome = 'Lojista Teste';
    const lojistaId = 'test_lojista_001';
    await db.collection('users').doc(lojistaId).set({
      nome: lojistaNome,
      email: 'lojista.teste@markaai.com.br',
      tipo: 'lojista',
      shopId: 'test_shop_001',
      createdAt: now,
      _test: true,
    }, { merge: true });
    results['1.2_lojista'] = `✅ users/${lojistaId}`;

    // ─── 1.3 Loja de teste ───────────────────────────────
    const shopId = 'test_shop_001';
    await db.collection('shops').doc(shopId).set({
      nome: 'Salão Teste MarkaAI',
      slug: 'markaai-teste',
      email: 'lojista.teste@markaai.com.br',
      ownerId: lojistaId,
      telefone: '11999990000',
      descricao: 'Loja criada automaticamente para testes de pagamento.',
      plan: 'flex',
      plan_expires_at: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)),
      config: {
        agendamento_online_ativo: true,
        pagamento_pix: true,
        pagamento_cartao: true,
        pagamento_dinheiro: true,
        exigir_sinal: false,
        aceitar_parcelas: true,
        max_parcelas: 6,
        tax_percent: 0,
        intervalo_agenda_min: 60,
        janela_agendamento_dias: 30,
        limite_minimo_agendamento_horas: 1,
        tempo_cancelamento_horas: 2,
      },
      createdAt: now,
      _test: true,
    }, { merge: true });
    results['1.3_loja'] = `✅ shops/${shopId} (slug: markaai-teste)`;

    // ─── 1.4 Serviços de teste ───────────────────────────
    const servicos = [
      { nome: 'Corte Simples', preco: 50.00, duracao: 60, descricao: 'Corte masculino ou feminino simples' },
      { nome: 'Coloração', preco: 150.00, duracao: 120, descricao: 'Coloração completa com tinta' },
      { nome: 'Manicure', preco: 35.00, duracao: 45, descricao: 'Esmaltação completa' },
    ];
    for (const s of servicos) {
      const ref = db.collection('shops').doc(shopId).collection('services').doc();
      await ref.set({ ...s, shopId, ativo: true, createdAt: now, _test: true });
    }
    results['1.4_servicos'] = `✅ ${servicos.length} serviços criados em shops/${shopId}/services`;

    // ─── 1.5 Horários disponíveis ────────────────────────
    // Profissional de teste
    const profId = 'test_prof_001';
    await db.collection('shops').doc(shopId).collection('professionals').doc(profId).set({
      nome: lojistaNome,
      email: 'lojista.teste@markaai.com.br',
      ativo: true,
      shopId,
      createdAt: now,
      _test: true,
    }, { merge: true });

    // Grade de horários: Seg-Sex 08:00–18:00
    const days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday'];
    const schedule = {};
    days.forEach(d => {
      schedule[d] = { active: true, start: '08:00', end: '18:00' };
    });
    schedule['saturday'] = { active: false };
    schedule['sunday'] = { active: false };

    await db.collection('shops').doc(shopId).collection('professionals').doc(profId)
      .collection('schedule').doc('weekly').set({ schedule, updatedAt: now });
    results['1.5_horarios'] = `✅ Grade Seg-Sex 08:00–18:00 para professionals/${profId}`;

    // ─── 1.6 Configuração de pagamento (mercadopago) ─────
    // Usa token de TESTE público do Mercado Pago (sandbox)
    // O lojista deve conectar sua conta TEST via OAuth, mas popula estrutura mínima
    await db.collection('shops').doc(shopId).update({
      'mercadopago.connected': false, // Será true após OAuth com conta TEST
      'mercadopago.ambiente': 'sandbox',
      'mercadopago.instrucoes': 'Acesse Configurações → Pagamentos → Conectar Mercado Pago com conta de TESTE',
      'payment_options': {
        pix: true,
        credito: true,
        presencial: true,
        credito_config: {
          aceitar_parcelas: true,
          max_parcelas: 6,
          repasse_ao_cliente: false,
          porcentagem_a_vista: 0,
        }
      }
    });
    results['1.6_pagamento'] = '✅ Estrutura de pagamento configurada. Conecte conta TEST MP via OAuth para ativar.';

    console.log('seedTestEnvironment: concluído', results);
    return res.status(200).json({ success: true, shopId, results });
  } catch (err) {
    console.error('seedTestEnvironment error:', err);
    return res.status(500).json({ error: String(err) });
  }
});

// Trigger: Novo agendamento criado
exports.onNewAppointment = onDocumentCreated('appointments/{appointmentId}', async (event) => {
  const snap = event.data;
  if (!snap) {
    console.log('No data associated with the event');
    return;
  }

  const appointment = snap.data();
  const appointmentId = event.params.appointmentId;

  console.log('📅 Novo agendamento criado:', appointmentId);

  try {
    // Buscar dados da loja
    const shopDoc = await admin.firestore().collection('shops').doc(appointment.shopId).get();
    if (!shopDoc.exists) {
      console.log('⚠️ Loja não encontrada');
      return;
    }

    const shopData = shopDoc.data();
    const fcmTokens = shopData.fcm_tokens || [];

    if (fcmTokens.length === 0) {
      console.log('⚠️ Loja não tem tokens FCM');
      return;
    }

    // Buscar nome do cliente
    const clientDoc = await admin.firestore().collection('users').doc(appointment.clientId).get();
    const clientName = clientDoc.exists ? (clientDoc.data().nome || clientDoc.data().name || 'Cliente') : 'Cliente';

    // Formatar data e hora com fuso de Brasília
    const appointmentDate = appointment.data_agendamento.toDate();
    const dateStr = appointmentDate.toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      timeZone: 'America/Sao_Paulo'
    });
    const timeStr = appointmentDate.toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: 'America/Sao_Paulo'
    });

    // Enviar notificação
    const title = '🎉 Novo Agendamento!';
    const body = `${clientName} agendou ${appointment.servico_nome || 'um serviço'} para ${dateStr} às ${timeStr}`;
    const data = {
      type: 'new_appointment',
      appointmentId: appointmentId,
      shopId: appointment.shopId,
      clientId: appointment.clientId,
    };

    await sendPushNotification(fcmTokens, title, body, data);

  } catch (error) {
    console.error('❌ Erro ao processar novo agendamento:', error);
  }
});

// Trigger: Agendamento cancelado
exports.onAppointmentCancelled = onDocumentUpdated('appointments/{appointmentId}', async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  const appointmentId = event.params.appointmentId;

  // Verificar se foi cancelamento
  if (before.status !== 'cancelado' && after.status === 'cancelado') {
    console.log('🚫 Agendamento cancelado:', appointmentId);

    try {
      // Buscar dados da loja
      const shopDoc = await admin.firestore().collection('shops').doc(after.shopId).get();
      if (!shopDoc.exists) return;

      const shopData = shopDoc.data();
      const fcmTokens = shopData.fcm_tokens || [];

      if (fcmTokens.length === 0) return;

      // Buscar nome do cliente
      const clientDoc = await admin.firestore().collection('users').doc(after.clientId).get();
      const clientName = clientDoc.exists ? (clientDoc.data().nome || clientDoc.data().name || 'Cliente') : 'Cliente';

      // Formatar data e hora com fuso de Brasília
      const appointmentDate = after.data_agendamento.toDate();
      const dateStr = appointmentDate.toLocaleDateString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        timeZone: 'America/Sao_Paulo'
      });
      const timeStr = appointmentDate.toLocaleTimeString('pt-BR', {
        hour: '2-digit',
        minute: '2-digit',
        timeZone: 'America/Sao_Paulo'
      });

      // Identificar quem cancelou
      const canceladoPor = after.cancelado_por || 'desconhecido';
      const bodyText = canceladoPor === 'cliente'
        ? `${clientName} cancelou o agendamento de ${after.servico_nome || 'serviço'} marcado para ${dateStr} às ${timeStr}`
        : `Agendamento de ${clientName} para ${dateStr} às ${timeStr} foi cancelado`;

      // Enviar notificação
      const title = '❌ Agendamento Cancelado';
      const body = bodyText;
      const data = {
        type: 'appointment_cancelled',
        appointmentId: appointmentId,
        shopId: after.shopId,
        clientId: after.clientId,
      };

      await sendPushNotification(fcmTokens, title, body, data);

    } catch (error) {
      console.error('❌ Erro ao processar cancelamento:', error);
    }
  }

  // Verificar se houve pagamento
  if ((!before.valor_pago || before.valor_pago === 0) && after.valor_pago > 0) {
    console.log('💰 Pagamento recebido:', appointmentId);

    try {
      const shopDoc = await admin.firestore().collection('shops').doc(after.shopId).get();
      if (!shopDoc.exists) return;

      const shopData = shopDoc.data();
      const fcmTokens = shopData.fcm_tokens || [];

      if (fcmTokens.length === 0) return;

      // Buscar nome do cliente
      const clientDoc = await admin.firestore().collection('users').doc(after.clientId).get();
      const clientName = clientDoc.exists ? (clientDoc.data().nome || clientDoc.data().name || 'Cliente') : 'Cliente';

      // Formatar valor
      const valor = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(after.valor_pago);

      // Enviar notificação
      const title = '💰 Pagamento Recebido!';
      const body = `${clientName} pagou ${valor} pelo agendamento de ${after.servico_nome || 'serviço'}`;
      const data = {
        type: 'payment_received',
        appointmentId: appointmentId,
        shopId: after.shopId,
        clientId: after.clientId,
        amount: after.valor_pago.toString(),
      };

      await sendPushNotification(fcmTokens, title, body, data);

    } catch (error) {
      console.error('❌ Erro ao processar pagamento:', error);
    }
  }
});

// Trigger: Cliente atualiza dados do perfil
exports.onClientProfileUpdate = onDocumentUpdated('users/{userId}', async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  const userId = event.params.userId;

  // Verificar se houve mudanças significativas
  const changedFields = [];
  if (before.nome !== after.nome) changedFields.push('nome');
  if (before.telefone !== after.telefone) changedFields.push('telefone');
  if (before.email !== after.email) changedFields.push('email');

  if (changedFields.length === 0) return; // Sem mudanças relevantes

  console.log('👤 Cliente atualizou perfil:', userId, '- Campos:', changedFields);

  try {
    // Buscar agendamentos futuros deste cliente
    const appointmentsSnapshot = await admin.firestore()
      .collection('appointments')
      .where('clientId', '==', userId)
      .where('data_agendamento', '>', admin.firestore.Timestamp.now())
      .where('status', 'in', ['agendado', 'confirmado', 'pendente'])
      .get();

    if (appointmentsSnapshot.empty) {
      console.log('⚠️ Cliente não tem agendamentos futuros');
      return;
    }

    // Buscar lojas únicas dos agendamentos
    const shopIds = [...new Set(appointmentsSnapshot.docs.map(doc => doc.data().shopId))];

    // Enviar notificação para cada loja
    for (const shopId of shopIds) {
      const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
      if (!shopDoc.exists) continue;

      const shopData = shopDoc.data();
      const fcmTokens = shopData.fcm_tokens || [];

      if (fcmTokens.length === 0) continue;

      const clientName = after.nome || after.name || 'Cliente';
      const title = '📝 Cliente Atualizou Dados';
      const body = `${clientName} atualizou: ${changedFields.join(', ')}`;
      const data = {
        type: 'client_profile_update',
        userId: userId,
        shopId: shopId,
        changedFields: changedFields.join(','),
      };

      await sendPushNotification(fcmTokens, title, body, data);
    }

  } catch (error) {
    console.error('❌ Erro ao processar atualização de perfil:', error);
  }
});

// ============================================================================
// 🔄 GOOGLE CALENDAR BACKUP - SINCRONIZAÇÃO AUTOMÁTICA
// ============================================================================




/**
 * Sincroniza um agendamento com o Google Calendar do dono da loja
 * e do funcionário (se tiver backup configurado)
 */
async function syncAppointmentToGoogleCalendar(appointmentId, appointmentData) {
  try {
    // Busca dados do shop
    if (!appointmentData.shopId) return;

    const shopDoc = await admin.firestore()
      .collection('shops')
      .doc(appointmentData.shopId)
      .get();

    if (!shopDoc.exists) return;

    const shopData = shopDoc.data();
    const shopOwnerUid = shopData.owner_uid || shopData.ownerId;

    // Sincroniza para o dono da loja (se conectado)
    if (shopOwnerUid) {
      await syncToUserCalendar(shopOwnerUid, appointmentId, appointmentData);
    }

    // Sincroniza para o funcionário (se conectado e tem backup configurado)
    if (appointmentData.profissionalId) {
      const employeeDoc = await admin.firestore()
        .collection('employees')
        .doc(appointmentData.profissionalId)
        .get();

      if (employeeDoc.exists) {
        const employeeData = employeeDoc.data();
        const employeeEmail = employeeData.backup_email;

        // Busca usuário pelo email de backup
        if (employeeEmail) {
          const usersSnapshot = await admin.firestore()
            .collection('users')
            .where('email', '==', employeeEmail)
            .limit(1)
            .get();

          if (!usersSnapshot.empty) {
            const userDoc = usersSnapshot.docs[0];
            await syncToUserCalendar(userDoc.id, appointmentId, appointmentData);
          }
        }
      }
    }

  } catch (error) {
    console.error('Erro ao sincronizar com Google Calendar:', error);
  }
}

/**
 * Sincroniza para o calendário de um usuário específico
 */
async function syncToUserCalendar(userId, appointmentId, appointmentData) {
  try {
    const userDoc = await admin.firestore()
      .collection('users')
      .doc(userId)
      .get();

    if (!userDoc.exists) return;

    const userData = userDoc.data();
    const calendarData = userData.googleCalendar;

    // Verifica se está conectado
    if (!calendarData || !calendarData.connected) return;

    // Carregar googleapis de forma tardia (lazy loading)
    const { google } = require('googleapis');

    // Configura OAuth2
    const oauth2Client = new google.auth.OAuth2(
      process.env.GOOGLE_CLIENT_ID,
      process.env.GOOGLE_CLIENT_SECRET,
      process.env.GOOGLE_REDIRECT_URI
    );

    oauth2Client.setCredentials({
      access_token: calendarData.accessToken,
      refresh_token: calendarData.refreshToken,
      expiry_date: new Date(calendarData.expiry).getTime(),
    });

    const calendar = google.calendar({ version: 'v3', auth: oauth2Client });

    // Busca ou cria calendário "MarkaAI - Agendamentos"
    let calendarId = await findOrCreateBackupCalendar(calendar);
    if (!calendarId) return;

    // Busca dados do serviço e cliente
    const [serviceDoc, clientDoc] = await Promise.all([
      appointmentData.servicoId
        ? admin.firestore().collection('services').doc(appointmentData.servicoId).get()
        : null,
      appointmentData.clientId
        ? admin.firestore().collection('clients').doc(appointmentData.clientId).get()
        : null,
    ]);

    const servicoNome = serviceDoc?.exists ? serviceDoc.data().nome : 'Serviço';
    const duracaoMinutos = serviceDoc?.exists ? (serviceDoc.data().duracao || 60) : 60;
    const clienteNome = clientDoc?.exists ? clientDoc.data().nome : 'Cliente';

    const dataAgendamento = appointmentData.data_agendamento.toDate();
    const dataFim = new Date(dataAgendamento.getTime() + duracaoMinutos * 60000);

    const event = {
      summary: `${servicoNome} - ${clienteNome}`,
      description: `Agendamento MarkaAI\nID: ${appointmentId}\nStatus: ${appointmentData.status}\nValor: R$ ${appointmentData.valor_total?.toFixed(2) || '0.00'}`,
      start: {
        dateTime: dataAgendamento.toISOString(),
        timeZone: 'America/Sao_Paulo',
      },
      end: {
        dateTime: dataFim.toISOString(),
        timeZone: 'America/Sao_Paulo',
      },
      extendedProperties: {
        private: {
          markaai_appointment_id: appointmentId,
          markaai_shop_id: appointmentData.shopId,
        },
      },
    };

    // Verifica se já existe evento
    const existingEventId = appointmentData.googleCalendarEventId;

    if (existingEventId) {
      // Atualiza evento existente
      await calendar.events.update({
        calendarId: calendarId,
        eventId: existingEventId,
        resource: event,
      });
      console.log(`✅ Evento atualizado no Google Calendar: ${existingEventId}`);
    } else {
      // Cria novo evento
      const response = await calendar.events.insert({
        calendarId: calendarId,
        resource: event,
      });

      // Salva ID do evento no Firestore
      await admin.firestore()
        .collection('appointments')
        .doc(appointmentId)
        .update({
          googleCalendarEventId: response.data.id,
        });

      console.log(`✅ Evento criado no Google Calendar: ${response.data.id}`);
    }

  } catch (error) {
    console.error(`Erro ao sincronizar para usuário ${userId}:`, error);
  }
}

/**
 * Encontra ou cria o calendário de backup "MarkaAI - Agendamentos"
 */
async function findOrCreateBackupCalendar(calendar) {
  try {
    const calendarName = 'MarkaAI - Agendamentos';

    // Lista calendários
    const listResponse = await calendar.calendarList.list();
    const existingCalendar = listResponse.data.items?.find(
      cal => cal.summary === calendarName
    );

    if (existingCalendar) {
      return existingCalendar.id;
    }

    // Cria novo calendário
    const createResponse = await calendar.calendars.insert({
      resource: {
        summary: calendarName,
        description: 'Backup automático dos agendamentos do MarkaAI',
        timeZone: 'America/Sao_Paulo',
      },
    });

    return createResponse.data.id;
  } catch (error) {
    console.error('Erro ao criar/encontrar calendário:', error);
    return null;
  }
}

/**
 * Deleta um evento do Google Calendar
 */
async function deleteFromGoogleCalendar(userId, appointmentId, eventId) {
  try {
    const userDoc = await admin.firestore()
      .collection('users')
      .doc(userId)
      .get();

    if (!userDoc.exists) return;

    const userData = userDoc.data();
    const calendarData = userData.googleCalendar;

    if (!calendarData || !calendarData.connected || !eventId) return;

    // Carregar googleapis de forma tardia (lazy loading)
    const { google } = require('googleapis');

    const oauth2Client = new google.auth.OAuth2(
      process.env.GOOGLE_CLIENT_ID,
      process.env.GOOGLE_CLIENT_SECRET,
      process.env.GOOGLE_REDIRECT_URI
    );

    oauth2Client.setCredentials({
      access_token: calendarData.accessToken,
      refresh_token: calendarData.refreshToken,
      expiry_date: new Date(calendarData.expiry).getTime(),
    });

    const calendar = google.calendar({ version: 'v3', auth: oauth2Client });
    const calendarId = await findOrCreateBackupCalendar(calendar);

    if (calendarId) {
      await calendar.events.delete({
        calendarId: calendarId,
        eventId: eventId,
      });
      console.log(`✅ Evento deletado do Google Calendar: ${eventId}`);
    }
  } catch (error) {
    console.error(`Erro ao deletar evento do Google Calendar:`, error);
  }
}

// Trigger: Quando um agendamento é CRIADO
exports.onAppointmentCreated = onDocumentCreated(
  'appointments/{appointmentId}',
  async (event) => {
    const appointmentId = event.params.appointmentId;
    const appointmentData = event.data.data();

    console.log('🆕 Novo agendamento criado:', appointmentId);

    // Sincroniza com Google Calendar
    await syncAppointmentToGoogleCalendar(appointmentId, appointmentData);
  }
);

// (Função administrativa temporária removida)

// Trigger adicional: validar política de agendamentos múltiplos ao criar um appointment
exports.onAppointmentValidatePolicy = onDocumentCreated('appointments/{appointmentId}', async (event) => {
  const snap = event.data;
  if (!snap) return;
  const data = snap.data();
  const appointmentId = event.params.appointmentId;
  try {
    const shopId = data.shopId;
    const clientId = data.clientId;
    if (!shopId || !clientId) return;

    const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
    if (!shopDoc.exists) return;
    const shopData = shopDoc.data() || {};
    const config = shopData.config || {};
    const permitirMultiplos = config.permitir_multiplos;
    // Se não definido ou true -> nada a fazer
    if (permitirMultiplos === undefined || permitirMultiplos === true) return;

    // Verifica appts ativos do mesmo cliente na mesma loja (exceto este recém criado)
    const now = admin.firestore.Timestamp.now();
    const existing = await admin.firestore()
      .collection('appointments')
      .where('shopId', '==', shopId)
      .where('clientId', '==', clientId)
      .where('status', 'in', ['agendado', 'confirmado', 'pendente', 'pendente_verificacao'])
      .where('data_agendamento', '>=', now)
      .get();

    // Se encontrou outro agendamento ativo (além do atual), remove o criado e notifica
    const others = existing.docs.filter(d => d.id !== appointmentId);
    if (others.length > 0) {
      console.log(`Política: removendo agendamento ${appointmentId} por duplicidade (cliente ${clientId})`);
      await admin.firestore().collection('appointments').doc(appointmentId).delete();
      // Opcional: enviar notificação ao cliente via FCM (se tiver token)
      try {
        const userDoc = await admin.firestore().collection('users').doc(clientId).get();
        if (userDoc.exists) {
          const userData = userDoc.data() || {};
          const tokens = userData.fcmTokens || [];
          if (Array.isArray(tokens) && tokens.length > 0) {
            await sendPushNotification(tokens, 'Agendamento não permitido', 'Você já possui um agendamento ativo nesta loja. O novo agendamento foi removido automaticamente.');
          }
        }
      } catch (e) {
        console.error('Erro ao notificar cliente sobre remoção por política:', e);
      }
    }
  } catch (e) {
    console.error('Erro ao validar política de agendamento:', e);
  }
});

// Trigger: Quando um agendamento é ATUALIZADO
exports.onAppointmentUpdated = onDocumentUpdated(
  'appointments/{appointmentId}',
  async (event) => {
    const appointmentId = event.params.appointmentId;
    const before = event.data.before.data();
    const after = event.data.after.data();

    // Verifica se foi cancelado
    if (before.status !== 'cancelado' && after.status === 'cancelado') {
      console.log('❌ Agendamento cancelado:', appointmentId);

      // Deleta do Google Calendar se existir eventId
      if (after.googleCalendarEventId) {
        // Busca dono da loja
        const shopDoc = await admin.firestore()
          .collection('shops')
          .doc(after.shopId)
          .get();

        if (shopDoc.exists) {
          const shopData = shopDoc.data();
          const shopOwnerUid = shopData.owner_uid || shopData.ownerId;

          if (shopOwnerUid) {
            await deleteFromGoogleCalendar(
              shopOwnerUid,
              appointmentId,
              after.googleCalendarEventId
            );
          }
        }

        // Deleta do calendário do funcionário também
        if (after.profissionalId) {
          const employeeDoc = await admin.firestore()
            .collection('employees')
            .doc(after.profissionalId)
            .get();

          if (employeeDoc.exists) {
            const employeeData = employeeDoc.data();
            const employeeEmail = employeeData.backup_email;

            if (employeeEmail) {
              const usersSnapshot = await admin.firestore()
                .collection('users')
                .where('email', '==', employeeEmail)
                .limit(1)
                .get();

              if (!usersSnapshot.empty) {
                await deleteFromGoogleCalendar(
                  usersSnapshot.docs[0].id,
                  appointmentId,
                  after.googleCalendarEventId
                );
              }
            }
          }
        }
      }
    } else {
      // Atualiza evento no Google Calendar
      console.log('🔄 Agendamento atualizado:', appointmentId);
      await syncAppointmentToGoogleCalendar(appointmentId, after);
    }
  }
);

// Trigger: Quando um agendamento é DELETADO
exports.onAppointmentDeleted = onDocumentDeleted(
  'appointments/{appointmentId}',
  async (event) => {
    const appointmentId = event.params.appointmentId;
    const appointmentData = event.data.data();

    console.log('🗑️ Agendamento deletado:', appointmentId);

    if (appointmentData.googleCalendarEventId) {
      // Busca dono da loja
      const shopDoc = await admin.firestore()
        .collection('shops')
        .doc(appointmentData.shopId)
        .get();

      if (shopDoc.exists) {
        const shopData = shopDoc.data();
        const shopOwnerUid = shopData.owner_uid || shopData.ownerId;

        if (shopOwnerUid) {
          await deleteFromGoogleCalendar(
            shopOwnerUid,
            appointmentId,
            appointmentData.googleCalendarEventId
          );
        }
      }
    }
  }
);

// ============================================================
// createSubscription: Ativa/muda o plano de assinatura da plataforma MarkaAI
// Callable Function (onCall) — auth é verificado automaticamente pelo Firebase
// ============================================================
exports.createSubscription = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Usuário não autenticado.');
  }

  const uid = auth.uid;
  const data = request.data;

  // Validar parâmetros
  const { shopId, planId, planName, planPrice, billingCycle } = data;
  if (!shopId || !planId || !planName) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Parâmetros incompletos: shopId, planId e planName são obrigatórios.'
    );
  }

  const validPlans = ['free', 'starter', 'pro', 'vip'];
  if (!validPlans.includes(planId)) {
    throw new functions.https.HttpsError('invalid-argument', `Plano inválido: ${planId}`);
  }

  // Verificar que a loja existe
  const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
  if (!shopDoc.exists) {
    throw new functions.https.HttpsError('not-found', 'Loja não encontrada.');
  }

  // Verificar que o usuário logado é dono desta loja
  const shopData = shopDoc.data();
  const shopOwnerUid = shopData?.ownerId || shopData?.userId || shopData?.owner_uid || null;

  if (shopOwnerUid && shopOwnerUid !== uid) {
    console.warn(`createSubscription: uid ${uid} tentou alterar loja de ${shopOwnerUid}`);
    throw new functions.https.HttpsError('permission-denied', 'Você não tem permissão para alterar esta loja.');
  }

  // Se ownerId não estiver na loja, verificar via documento do usuário
  if (!shopOwnerUid) {
    const userDoc = await admin.firestore().collection('users').doc(uid).get();
    const userShopId = userDoc.data()?.shopId;
    if (userShopId && userShopId !== shopId) {
      console.warn(`createSubscription: shopId ${shopId} não pertence ao usuário ${uid}`);
      throw new functions.https.HttpsError('permission-denied', 'Você não tem permissão para alterar esta loja.');
    }
  }

  // Atualizar plano no Firestore
  const subscriptionData = {
    plan_id: planId,
    plan_name: planName,
    price: parseFloat(planPrice) || 0,
    status: 'active',
    billing_cycle: billingCycle || 'monthly',
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
    activated_by: uid,
  };

  await admin.firestore().collection('shops').doc(shopId).update({
    subscription: subscriptionData,
  });

  console.log(`✅ createSubscription: loja ${shopId} mudou para plano ${planId} (uid ${uid})`);

  return {
    success: true,
    message: `Plano ${planName} ativado com sucesso!`,
    planId,
  };
});

// ============================================================
// FASE 1 — SEED DE DADOS DE TESTE
// Endpoint: POST /seedTestData
// Header requerido: x-seed-key: markaai-seed-dev
// Uso no terminal: curl -X POST https://REGION-PROJECT.cloudfunctions.net/seedTestData \
//                      -H "x-seed-key: markaai-seed-dev" -H "Content-Type: application/json" -d '{}'
// Cleanup: -d '{"action":"cleanup"}'
// ATENÇÃO: remover em produção ou garantir que x-seed-key não seja exposta.
// ============================================================
const { seedTestData } = require('./seed_test_data');
exports.seedTestData = seedTestData;

// ============================================================
// ASSINATURA: CICLO DE VIDA
// ============================================================

// TESTE 10 — Upgrade de plano com crédito pro-rata
exports.upgradeSubscription = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new functions.https.HttpsError('unauthenticated', 'Usuário não autenticado.');
  const uid = auth.uid;
  const { shopId, newPlanId, newPlanName, newPlanPrice } = request.data;

  if (!shopId || !newPlanId) {
    throw new functions.https.HttpsError('invalid-argument', 'shopId e newPlanId são obrigatórios.');
  }

  const db = admin.firestore();
  const shopRef = db.collection('shops').doc(shopId);
  const shopDoc = await shopRef.get();
  if (!shopDoc.exists) throw new functions.https.HttpsError('not-found', 'Loja não encontrada.');

  const shopData = shopDoc.data();
  const subscriptionId = shopData?.subscription?.stripe_subscription_id;

  // Se não tem assinatura Stripe, trata como upgrade manual (legado ou free -> paid)
  if (!subscriptionId) {
    // Lógica original para ativar planos sem cobrar via Stripe (Free -> Start por exemplo)
    await shopRef.update({
      plan: newPlanId,
      plan_id: newPlanId,
      'subscription.plan_id': newPlanId,
      'subscription.status': 'active',
    });
    return { success: true, message: "Plano atualizado localmente." };
  }

  const newPriceId = PRICE_IDS[newPlanId];
  if (!newPriceId) throw new functions.https.HttpsError('not-found', 'ID de preço não encontrado.');

  try {
    // 1. Recuperar assinatura atual no Stripe
    const subscription = await stripe.subscriptions.retrieve(subscriptionId);

    // 2. Realizar o Upgrade no Stripe (com pro-rata automático)
    await stripe.subscriptions.update(subscriptionId, {
      items: [{
        id: subscription.items.data[0].id,
        price: newPriceId,
      }],
      proration_behavior: 'always_invoice', // Cobra a diferença imediatamente
      payment_behavior: 'default_incomplete', // Exige pagamento se houver diferença
      expand: ['latest_invoice.payment_intent'],
    });

    console.log(`✅ upgradeSubscription (Stripe): loja ${shopId} → ${newPlanId}`);
    return { success: true, message: `Upgrade para ${newPlanName} solicitado via Stripe.` };
  } catch (error) {
    console.error("Stripe Upgrade Error:", error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

// TESTE 11 — Downgrade agendado para próximo ciclo
exports.downgradeSubscription = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new functions.https.HttpsError('unauthenticated', 'Usuário não autenticado.');
  const uid = auth.uid;
  const { shopId, newPlanId, newPlanName } = request.data;
  if (!shopId || !newPlanId) {
    throw new functions.https.HttpsError('invalid-argument', 'shopId e newPlanId são obrigatórios.');
  }
  const db = admin.firestore();
  const shopRef = db.collection('shops').doc(shopId);
  const shopDoc = await shopRef.get();
  if (!shopDoc.exists) throw new functions.https.HttpsError('not-found', 'Loja não encontrada.');
  const shopData = shopDoc.data();
  const ownerId = shopData?.ownerId || shopData?.userId || shopData?.owner_uid;
  if (ownerId && ownerId !== uid) {
    throw new functions.https.HttpsError('permission-denied', 'Sem permissão para alterar esta loja.');
  }
  const current = shopData?.subscription || {};
  const currentPeriodEnd = current.current_period_end || null;
  // Plano atual continua até fim do período; downgrade entra depois
  await shopRef.update({
    'subscription.pending_downgrade': {
      plan_id: newPlanId,
      plan_name: newPlanName || newPlanId,
      scheduled_for: currentPeriodEnd || admin.firestore.FieldValue.serverTimestamp(),
      scheduled_by: uid,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    },
    'subscription.updated_at': admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(`✅ downgradeSubscription: loja ${shopId} downgrade agendado para ${newPlanId} (uid ${uid})`);
  return { success: true, message: `Downgrade para ${newPlanName || newPlanId} agendado para o próximo ciclo.` };
});

// TESTE 12 — Cancelamento com manutenção de acesso até fim do período
exports.cancelSubscription = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new functions.https.HttpsError('unauthenticated', 'Usuário não autenticado.');
  const uid = auth.uid;
  const { shopId } = request.data;
  if (!shopId) throw new functions.https.HttpsError('invalid-argument', 'shopId é obrigatório.');

  const db = admin.firestore();
  const shopRef = db.collection('shops').doc(shopId);
  const shopDoc = await shopRef.get();
  if (!shopDoc.exists) throw new functions.https.HttpsError('not-found', 'Loja não encontrada.');

  const shopData = shopDoc.data();
  const subscriptionId = shopData?.subscription?.stripe_subscription_id;

  if (!subscriptionId) {
    // Fallback cancelamento local
    await shopRef.update({
      'subscription.status': 'canceled',
      'subscription.updated_at': admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: true, message: "Acesso local cancelado." };
  }

  try {
    // Agendar cancelamento para o fim do período (para não prejudicar o cliente)
    await stripe.subscriptions.update(subscriptionId, {
      cancel_at_period_end: true,
    });

    console.log(`✅ cancelSubscription (Stripe): loja ${shopId} agendada para encerrar.`);
    return { success: true, message: "Sua assinatura será encerrada ao final do período pago. Você mantém acesso até lá." };
  } catch (error) {
    console.error("Stripe Cancel Error:", error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

// TESTE 13 — Reativação de assinatura cancelada
exports.reactivateSubscription = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new functions.https.HttpsError('unauthenticated', 'Usuário não autenticado.');
  const uid = auth.uid;
  const { shopId } = request.data;
  if (!shopId) throw new functions.https.HttpsError('invalid-argument', 'shopId é obrigatório.');

  const db = admin.firestore();
  const shopRef = db.collection('shops').doc(shopId);
  const shopDoc = await shopRef.get();
  if (!shopDoc.exists) throw new functions.https.HttpsError('not-found', 'Loja não encontrada.');

  const shopData = shopDoc.data();
  const subscriptionId = shopData?.subscription?.stripe_subscription_id;

  if (!subscriptionId) {
    throw new functions.https.HttpsError('failed-precondition', 'Nenhuma assinatura Stripe vinculada.');
  }

  try {
    // Reverter o cancelamento agendado (Stripe volta a ser recorrente)
    await stripe.subscriptions.update(subscriptionId, {
      cancel_at_period_end: false,
    });

    console.log(`✅ reactivateSubscription (Stripe): loja ${shopId} reativada.`);
    return { success: true, message: "Sua assinatura foi reativada com sucesso! 🚀" };
  } catch (error) {
    console.error("Stripe Reactivate Error:", error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

// ============================================================
// 🌍 SISTEMA DE LOCALIZAÇÃO — ETAPA 1 (Backend)
// ============================================================

// Cache em memória para resultados do ViaCEP (TTL: 24h)
const cepCache = new Map();
const CEP_CACHE_TTL_MS = 24 * 60 * 60 * 1000; // 24 horas

/**
 * fetchCep — Proxy interno para a API do ViaCEP.
 * Callable: cliente chama functions().httpsCallable('fetchCep')({ cep: '01310100' })
 * Retorna: { logradouro, bairro, cidade, estado, cep } ou lança erro.
 */
exports.fetchCep = onCall(async (request) => {
  const cepRaw = (request.data.cep || '').toString().replace(/\D/g, '');
  if (cepRaw.length !== 8) {
    throw new functions.https.HttpsError('invalid-argument', 'CEP deve conter 8 dígitos.');
  }

  // Verificar cache
  const cached = cepCache.get(cepRaw);
  if (cached && (Date.now() - cached.ts) < CEP_CACHE_TTL_MS) {
    console.log(`[fetchCep] Cache hit para CEP: ${cepRaw}`);
    return cached.data;
  }

  try {
    console.log(`[fetchCep] Consultando ViaCEP para: ${cepRaw}`);
    const response = await axios.get(`https://viacep.com.br/ws/${cepRaw}/json/`, {
      timeout: 5000,
    });

    const data = response.data;
    if (data.erro) {
      throw new functions.https.HttpsError('not-found', 'CEP não encontrado. Verifique o número e tente novamente.');
    }

    const result = {
      cep: data.cep || cepRaw,
      logradouro: data.logradouro || '',
      bairro: data.bairro || '',
      cidade: data.localidade || '',
      estado: data.uf || '',
    };

    // Salvar no cache
    cepCache.set(cepRaw, { data: result, ts: Date.now() });
    console.log(`[fetchCep] OK: ${result.cidade}/${result.estado}`);
    return result;

  } catch (err) {
    if (err instanceof functions.https.HttpsError) throw err;
    console.error('[fetchCep] Erro ao consultar ViaCEP:', err.message);
    throw new functions.https.HttpsError(
      'unavailable',
      'Não foi possível consultar o CEP no momento. Preencha cidade e estado manualmente.'
    );
  }
});

/**
 * getAvailableCities — Retorna cidades distintas cadastradas na coleção `shops`.
 * Callable: cliente chama functions().httpsCallable('getAvailableCities')({ query: 'São', estado: 'SP' })
 * Idéal para autocomplete do SeletorDeCidade.
 */
// Cache de cidades (TTL: 10 minutos)
let citiesCache = null;
let citiesCacheTs = 0;
const CITIES_CACHE_TTL_MS = 10 * 60 * 1000; // 10 minutos

exports.getAvailableCities = onCall(async (request) => {
  const queryStr = ((request.data || {}).query || '').toLowerCase().trim();
  const estadoFilter = ((request.data || {}).estado || '').toUpperCase().trim();

  const now = Date.now();

  // Usar cache se disponível e recente
  let allCities = citiesCache;
  if (!allCities || (now - citiesCacheTs) > CITIES_CACHE_TTL_MS) {
    console.log('[getAvailableCities] Carregando cidades do Firestore...');
    const snap = await admin.firestore()
      .collection('shops')
      .where('cidade', '!=', '')
      .get();

    const citySet = new Map(); // key = 'cidade|estado'
    snap.docs.forEach((doc) => {
      const d = doc.data();
      const cidade = (d.cidade || '').trim();
      const estado = (d.estado || '').trim().toUpperCase();
      if (cidade && estado.length === 2) {
        const key = `${cidade.toLowerCase()}|${estado}`;
        if (!citySet.has(key)) {
          citySet.set(key, { cidade, estado });
        }
      }
    });

    allCities = Array.from(citySet.values()).sort((a, b) =>
      a.cidade.localeCompare(b.cidade, 'pt-BR')
    );
    citiesCache = allCities;
    citiesCacheTs = now;
    console.log(`[getAvailableCities] ${allCities.length} cidades distintas encontradas.`);
  }

  // Filtrar por query e/ou estado
  let filtered = allCities;
  if (estadoFilter) {
    filtered = filtered.filter((c) => c.estado === estadoFilter);
  }
  if (queryStr) {
    filtered = filtered.filter((c) =>
      c.cidade.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '')
        .includes(queryStr.normalize('NFD').replace(/[\u0300-\u036f]/g, ''))
    );
  }

  return { cities: filtered.slice(0, 50) }; // Limitar a 50 resultados
});

// ============================================================
// 🔄 SISTEMA DE CANCELAMENTO E REAGENDAMENTO (FASE 8)
// ============================================================

exports.cancelAppointment = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new functions.https.HttpsError('unauthenticated', 'Usuário não autenticado.');

  const { appointmentId, reason, requestRefund, pixKey, amount } = request.data;
  if (!appointmentId) throw new functions.https.HttpsError('invalid-argument', 'ID do agendamento é obrigatório.');

  const db = admin.firestore();
  const docRef = db.collection('appointments').doc(appointmentId);

  return db.runTransaction(async (transaction) => {
    const docSnap = await transaction.get(docRef);
    if (!docSnap.exists) throw new functions.https.HttpsError('not-found', 'Agendamento não encontrado.');

    const data = docSnap.data();

    // Authorization check
    // Clients can only cancel their own appointments. Shops can cancel any appointment belonging to them.
    const isClient = (data.clientId || data.cliente_id) === auth.uid;
    const isShopOwner = data.shopId; // We should ideally check if the auth.uid is the shop owner, but for now we trust shop-side requests or we do a quick check

    let shopData = null;
    const shopSnap = await transaction.get(db.collection('shops').doc(data.shopId));
    if (shopSnap.exists) {
      shopData = shopSnap.data();
    }

    const isAdmin = shopData && shopData.owner_uid === auth.uid;

    if (!isClient && !isAdmin) {
      throw new functions.https.HttpsError('permission-denied', 'Sem permissão para cancelar este agendamento.');
    }

    if (data.status === 'cancelado') {
      throw new functions.https.HttpsError('failed-precondition', 'Este agendamento já está cancelado.');
    }

    // Time validation for cancellation (default 24h)
    const tempoMinimo = shopData?.config?.tempo_cancelamento_horas ?? 24;
    const appointmentDate = data.data_agendamento.toDate();
    const now = new Date();
    const horasRestantes = (appointmentDate - now) / (1000 * 60 * 60);

    // Only enforce time limit for clients. Shop owners can cancel at any time.
    if (isClient && horasRestantes < tempoMinimo) {
      throw new functions.https.HttpsError('failed-precondition', `O cancelamento deve ser feito com no mínimo ${tempoMinimo} horas de antecedência.`);
    }

    const valorPago = data.valor_pago || 0;
    const updateData = {
      status: 'cancelado',
      cancelado_em: admin.firestore.FieldValue.serverTimestamp(),
      cancelado_por: isClient ? 'cliente' : 'loja',
      motivo_cancelamento: reason || null
    };

    if (requestRefund && valorPago > 0) {
      updateData.reembolso_pendente = true;

      const refundRef = db.collection('refundRequests').doc();
      transaction.set(refundRef, {
        appointmentId: docRef.id,
        shopId: data.shopId,
        clientId: data.clientId || data.cliente_id || '',
        clientName: data.client_nome || data.cliente_nome || '',
        valor_pago: amount || valorPago, // Optional partial refund
        chave_pix: pixKey || '',
        motivo: reason || '',
        status: 'pendente',
        data_solicitacao: admin.firestore.FieldValue.serverTimestamp()
      });
    }

    transaction.update(docRef, updateData);
    return { success: true, message: 'Agendamento cancelado com sucesso.' };
  });
});

exports.rescheduleAppointment = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new functions.https.HttpsError('unauthenticated', 'Usuário não autenticado.');

  const { appointmentId, newDateISO, newServiceId, newServiceName, newPrice, newProfessionalId, newProfessionalName } = request.data;
  if (!appointmentId || !newDateISO) throw new functions.https.HttpsError('invalid-argument', 'Faltam dados obrigatórios (appointmentId ou newDateISO).');

  const db = admin.firestore();
  const docRef = db.collection('appointments').doc(appointmentId);
  const newDate = new Date(newDateISO);

  return db.runTransaction(async (transaction) => {
    const docSnap = await transaction.get(docRef);
    if (!docSnap.exists) throw new functions.https.HttpsError('not-found', 'Agendamento não encontrado.');
    const data = docSnap.data();

    // Permissões
    const isClient = (data.clientId || data.cliente_id) === auth.uid;
    const shopSnap = await transaction.get(db.collection('shops').doc(data.shopId));
    let shopData = null;
    if (shopSnap.exists) shopData = shopSnap.data();

    const isAdmin = shopData && shopData.owner_uid === auth.uid;

    if (!isClient && !isAdmin) {
      throw new functions.https.HttpsError('permission-denied', 'Sem permissão para reagendar.');
    }

    if (data.status === 'cancelado') {
      throw new functions.https.HttpsError('failed-precondition', 'Agendamento cancelado não pode ser reagendado.');
    }

    // Regras da loja (permitir reagendamento, tempo minimo)
    const storeConfig = shopData?.config || {};
    if (isClient && storeConfig.permitir_reagendamento === false) {
      throw new functions.https.HttpsError('failed-precondition', 'Esta loja não permite reagendamento via app.');
    }

    // A loja pode forçar que não permita por padrão
    const tempoMinimo = storeConfig.tempo_reagendamento_horas ?? 12; // 12h se não configurado
    const oldDate = data.data_agendamento.toDate();
    const now = new Date();
    const horasParaAntigo = (oldDate - now) / (1000 * 60 * 60);

    if (isClient && horasParaAntigo < tempoMinimo) {
      throw new functions.https.HttpsError('failed-precondition', `A loja exige antecedência mínima de ${tempoMinimo}h para reagendar.`);
    }

    // Calcular diferença de preço se houver mudança de serviço/valor
    let restanteAPagarAtualizado = data.restante_a_pagar || 0;
    const valorPagoAtual = data.valor_pago || 0;
    let novoPrecoCalculado = data.valor_total || data.valor || 0;

    if (newPrice !== undefined && newPrice !== null) {
      novoPrecoCalculado = parseFloat(newPrice);
      restanteAPagarAtualizado = novoPrecoCalculado - valorPagoAtual;
      if (restanteAPagarAtualizado < 0) restanteAPagarAtualizado = 0; // Lidaremos com reembolsos manualmente
    }

    // UPDATE
    const updateData = {
      data_agendamento: admin.firestore.Timestamp.fromDate(newDate),
      reagendado_em: admin.firestore.FieldValue.serverTimestamp(),
      reagendado_por: isClient ? 'cliente' : 'loja',
      valor_total: novoPrecoCalculado,
      restante_a_pagar: restanteAPagarAtualizado,
    };

    if (newProfessionalId) {
      updateData.profissional_id = newProfessionalId;
      updateData.profissional_nome = newProfessionalName || null;
      updateData.profissionalId = newProfessionalId; // Manter compatibilidade com ambos os campos
    }

    if (newServiceId) {
      updateData.servico_id = newServiceId;
      updateData.servicoId = newServiceId; // Manter compatibilidade
      if (newServiceName) updateData.servico_nome = newServiceName;
    }

    transaction.update(docRef, updateData);
    return { success: true, message: 'Agendamento alterado com sucesso.', restanteCalculado: restanteAPagarAtualizado };
  });
});

exports.approveRefund = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new functions.https.HttpsError('unauthenticated', 'Usuário não autenticado.');

  const { refundId, approve } = request.data;
  if (!refundId) throw new functions.https.HttpsError('invalid-argument', 'ID do reembolso é obrigatório.');

  const db = admin.firestore();
  const refundRef = db.collection('refundRequests').doc(refundId);

  return db.runTransaction(async (transaction) => {
    const refundSnap = await transaction.get(refundRef);
    if (!refundSnap.exists) throw new functions.https.HttpsError('not-found', 'Solicitação não encontrada.');
    const refundData = refundSnap.data();

    if (refundData.status !== 'pendente') {
      throw new functions.https.HttpsError('failed-precondition', 'Solicitação já processada.');
    }

    // Verificação de segurança: quem chama DEVE ser o dono da loja
    const shopSnap = await transaction.get(db.collection('shops').doc(refundData.shopId));
    if (!shopSnap.exists || shopSnap.data().owner_uid !== auth.uid) {
      throw new functions.https.HttpsError('permission-denied', 'Só o dono da loja pode processar o reembolso.');
    }

    const novoStatus = approve ? 'aprovado' : 'recusado';

    transaction.update(refundRef, {
      status: novoStatus,
      data_processamento: admin.firestore.FieldValue.serverTimestamp(),
      processado_por: auth.uid
    });

    if (approve && refundData.appointmentId) {
      // Atualizar no agendamento para não constar mais como pendente
      const appRef = db.collection('appointments').doc(refundData.appointmentId);
      transaction.update(appRef, {
        reembolso_pendente: false,
        reembolso_pago: true
      });
    }

    return { success: true, message: `Reembolso ${novoStatus}.` };
  });
});

exports.debugAppointments = require('./debug').debugAppointments;

// ============================================================
// STRIPE SAAS - Assinaturas de Planos (MarkaAI → Lojas)
// ============================================================

/**
 * Cria uma assinatura Stripe para o dono de loja.
 * Retorna os dados necessários para o PaymentSheet nativo do Flutter.
 */
exports.createStripeSubscription = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new functions.https.HttpsError('unauthenticated', 'Usuário não autenticado.');

  const { planId, shopId, email } = request.data;
  if (!planId || !shopId || !email) {
    throw new functions.https.HttpsError('invalid-argument', 'planId, shopId e email são obrigatórios.');
  }

  const priceId = PRICE_IDS[planId];
  if (!priceId) {
    throw new functions.https.HttpsError('invalid-argument', `Plano inválido: ${planId}`);
  }

  const db = admin.firestore();

  try {
    const shopRef = db.collection('shops').doc(shopId);
    const shopSnap = await shopRef.get();
    if (!shopSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Loja não encontrada.');
    }
    const shopData = shopSnap.data();

    // Verificar ou criar Customer no Stripe
    let customerId = shopData.stripe_customer_id;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: email,
        metadata: { shopId, uid: auth.uid }
      });
      customerId = customer.id;
      await shopRef.update({ stripe_customer_id: customerId });
    }

    // Criar Ephemeral Key para o PaymentSheet
    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customerId },
      { apiVersion: '2023-10-16' }
    );

    // Criar a Subscription com pagamento incompleto (aguarda confirmação do usuário)
    const subscription = await stripe.subscriptions.create({
      customer: customerId,
      items: [{ price: priceId }],
      payment_behavior: 'default_incomplete',
      payment_settings: { save_default_payment_method: 'on_subscription' },
      expand: ['latest_invoice.payment_intent'],
      metadata: { shopId, planId, uid: auth.uid }
    });

    const paymentIntent = subscription.latest_invoice?.payment_intent;
    if (!paymentIntent) {
      throw new functions.https.HttpsError('internal', 'Não foi possível criar o PaymentIntent.');
    }

    // Salvar subscription_id temporário no Firestore (será confirmado pelo webhook)
    await shopRef.update({
      stripe_subscription_id_pending: subscription.id,
      stripe_plan_pending: planId
    });

    console.log(`createStripeSubscription: shop=${shopId} plan=${planId} sub=${subscription.id}`);

    return {
      paymentIntentClientSecret: paymentIntent.client_secret,
      customer: customerId,
      ephemeralKey: ephemeralKey.secret,
      subscriptionId: subscription.id
    };
  } catch (e) {
    console.error('createStripeSubscription error:', e.message);
    if (e instanceof functions.https.HttpsError) throw e;
    throw new functions.https.HttpsError('internal', e.message);
  }
});

/**
 * Webhook do Stripe - Confirma pagamento e atualiza a assinatura no Firestore.
 * Configurar no Dashboard Stripe: https://dashboard.stripe.com/webhooks
 */
exports.stripeWebhook = onRequest(async (req, res) => {
  const sig = req.headers['stripe-signature'];
  // Configure STRIPE_WEBHOOK_SECRET no Firebase: firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
  const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET || '';

  let event;
  try {
    if (webhookSecret) {
      event = stripe.webhooks.constructEvent(req.rawBody, sig, webhookSecret);
    } else {
      event = JSON.parse(req.rawBody.toString());
      console.warn('stripeWebhook: STRIPE_WEBHOOK_SECRET não configurado. Validação desabilitada.');
    }
  } catch (e) {
    console.error('stripeWebhook signature error:', e.message);
    return res.status(400).send(`Webhook Error: ${e.message}`);
  }

  const db = admin.firestore();

  switch (event.type) {
    case 'invoice.payment_succeeded': {
      const invoice = event.data.object;
      const subscriptionId = invoice.subscription;
      const customerId = invoice.customer;

      // Buscar loja pelo customer_id
      const shopsSnap = await db.collection('shops').where('stripe_customer_id', '==', customerId).get();
      if (shopsSnap.empty) {
        console.warn(`stripeWebhook: Nenhuma loja encontrada para customer=${customerId}`);
        break;
      }
      const shopRef = shopsSnap.docs[0].ref;
      const sub = await stripe.subscriptions.retrieve(subscriptionId);
      const priceId = sub.items.data[0]?.price.id;
      const planId = Object.keys(PRICE_IDS).find(k => PRICE_IDS[k] === priceId) || 'unknown';

      await shopRef.update({
        'subscription.plan_id': planId,
        'subscription.status': 'active',
        'subscription.stripe_subscription_id': subscriptionId,
        'subscription.current_period_end': new Date(sub.current_period_end * 1000),
        'subscription.updated_at': admin.firestore.FieldValue.serverTimestamp(),
        stripe_subscription_id: subscriptionId,
        stripe_subscription_id_pending: admin.firestore.FieldValue.delete(),
        stripe_plan_pending: admin.firestore.FieldValue.delete()
      });
      console.log(`stripeWebhook: Assinatura ativada. shop=${shopRef.id} plan=${planId}`);
      break;
    }

    case 'customer.subscription.deleted': {
      const sub = event.data.object;
      const customerId = sub.customer;
      const shopsSnap = await db.collection('shops').where('stripe_customer_id', '==', customerId).get();
      if (!shopsSnap.empty) {
        await shopsSnap.docs[0].ref.update({
          'subscription.status': 'canceled',
          'subscription.updated_at': admin.firestore.FieldValue.serverTimestamp()
        });
      }
      break;
    }

    default:
      console.log(`stripeWebhook: Evento não tratado: ${event.type}`);
  }

  res.json({ received: true });
});

/**
 * Cancela a assinatura ao final do período atual.
 */
exports.cancelSubscription = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new functions.https.HttpsError('unauthenticated', 'Não autenticado.');

  const { shopId } = request.data;
  if (!shopId) throw new functions.https.HttpsError('invalid-argument', 'shopId obrigatório.');

  const db = admin.firestore();
  const shopSnap = await db.collection('shops').doc(shopId).get();
  if (!shopSnap.exists) throw new functions.https.HttpsError('not-found', 'Loja não encontrada.');

  const shopData = shopSnap.data();
  const subId = shopData.stripe_subscription_id || shopData.subscription?.stripe_subscription_id;
  if (!subId) throw new functions.https.HttpsError('failed-precondition', 'Nenhuma assinatura ativa encontrada.');

  const sub = await stripe.subscriptions.update(subId, { cancel_at_period_end: true });
  const accessUntil = new Date(sub.current_period_end * 1000);

  await db.collection('shops').doc(shopId).update({
    'subscription.status': 'canceled',
    'subscription.access_until': accessUntil,
    'subscription.updated_at': admin.firestore.FieldValue.serverTimestamp()
  });

  return { success: true, message: `Assinatura cancelada. Acesso até ${accessUntil.toLocaleDateString('pt-BR')}.` };
});

/**
 * Reativa assinatura cancelada antes do fim do período.
 */
exports.reactivateSubscription = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new functions.https.HttpsError('unauthenticated', 'Não autenticado.');

  const { shopId } = request.data;
  if (!shopId) throw new functions.https.HttpsError('invalid-argument', 'shopId obrigatório.');

  const db = admin.firestore();
  const shopSnap = await db.collection('shops').doc(shopId).get();
  if (!shopSnap.exists) throw new functions.https.HttpsError('not-found', 'Loja não encontrada.');

  const subId = shopSnap.data().stripe_subscription_id || shopSnap.data().subscription?.stripe_subscription_id;
  if (!subId) throw new functions.https.HttpsError('failed-precondition', 'Nenhuma assinatura para reativar.');

  await stripe.subscriptions.update(subId, { cancel_at_period_end: false });
  await db.collection('shops').doc(shopId).update({
    'subscription.status': 'active',
    'subscription.access_until': admin.firestore.FieldValue.delete(),
    'subscription.updated_at': admin.firestore.FieldValue.serverTimestamp()
  });

  return { success: true, message: 'Assinatura reativada com sucesso! 🚀' };
});

/**
 * Upgrade de plano - troca o price na assinatura ativa (pro-rata automático pelo Stripe).
 */
exports.upgradeSubscription = onCall(async (request) => {
  const auth = request.auth;
  if (!auth) throw new functions.https.HttpsError('unauthenticated', 'Não autenticado.');

  const { shopId, newPlanId } = request.data;
  if (!shopId || !newPlanId) throw new functions.https.HttpsError('invalid-argument', 'shopId e newPlanId obrigatórios.');

  const newPriceId = PRICE_IDS[newPlanId];
  if (!newPriceId) throw new functions.https.HttpsError('invalid-argument', `Plano inválido: ${newPlanId}`);

  const db = admin.firestore();
  const shopSnap = await db.collection('shops').doc(shopId).get();
  if (!shopSnap.exists) throw new functions.https.HttpsError('not-found', 'Loja não encontrada.');

  const subId = shopSnap.data().stripe_subscription_id || shopSnap.data().subscription?.stripe_subscription_id;
  if (!subId) throw new functions.https.HttpsError('failed-precondition', 'Nenhuma assinatura ativa para upgrade.');

  const sub = await stripe.subscriptions.retrieve(subId);
  const itemId = sub.items.data[0]?.id;

  await stripe.subscriptions.update(subId, {
    items: [{ id: itemId, price: newPriceId }],
    proration_behavior: 'create_prorations'
  });

  await db.collection('shops').doc(shopId).update({
    'subscription.plan_id': newPlanId,
    'subscription.updated_at': admin.firestore.FieldValue.serverTimestamp()
  });

  return { success: true, message: `Plano alterado para ${newPlanId.toUpperCase()}` };
});

// ===================================================================
// SISTEMA DE E-MAILS TRANSACIONAIS (NODEMAILER)
// ===================================================================

/**
 * Disparado quando um NOVO agendamento é CRIADO.
 */
exports.onAppointmentCreatedEmail = onDocumentCreated('appointments/{appointmentId}', async (event) => {
  const data = event.data.data();
  if (!data) return;

  const emailCliente = data.emailCliente;
  if (!emailCliente || !emailCliente.includes('@')) {
    console.log(`onAppointmentCreatedEmail ignorado: emailCliente inválido para ${event.params.appointmentId}`);
    return;
  }

  try {
    const shopDoc = await admin.firestore().collection('shops').doc(data.shopId).get();
    const shopName = shopDoc.exists ? (shopDoc.data().nome || 'Barbearia/Salão') : 'MarkaAI';

    const dateObj = data.data_agendamento.toDate();
    const dateStr = dateObj.toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' }) +
      " às " + dateObj.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });

    await emailService.sendAppointmentEmail({
      toEmail: emailCliente,
      patientName: data.nomeCliente || 'Cliente',
      shopName: shopName,
      serviceName: data.servicoNome || 'Serviço',
      dateStr: dateStr,
      price: data.valor,
      isCancellation: false,
    });
  } catch (error) {
    console.error("Erro no gatilho onAppointmentCreatedEmail:", error);
  }
});

/**
 * Disparado quando um agendamento existente é ATUALIZADO (Ex: Cancelado / Reprogramado / Concluído).
 */
exports.onAppointmentUpdatedEmail = onDocumentUpdated('appointments/{appointmentId}', async (event) => {
  const beforeData = event.data.before.data();
  const afterData = event.data.after.data();
  if (!afterData) return;

  const emailCliente = afterData.emailCliente;
  if (!emailCliente || !emailCliente.includes('@')) return;

  // Verifica se o status mudou para 'cancelado' ou 'rejeitado'
  const mudouStatusParaCancelado = (beforeData.status !== afterData.status) &&
    (afterData.status === 'cancelado' || afterData.status === 'rejeitado');

  // Verifica se a data mudou (reagendamento)
  const mudouData = beforeData.data_agendamento.toMillis() !== afterData.data_agendamento.toMillis();

  // Se não foi cancelado nem reagendado, não enviamos spam
  if (!mudouStatusParaCancelado && !mudouData) return;

  try {
    const shopDoc = await admin.firestore().collection('shops').doc(afterData.shopId).get();
    const shopName = shopDoc.exists ? (shopDoc.data().nome || 'Barbearia/Salão') : 'MarkaAI';

    const dateObj = afterData.data_agendamento.toDate();
    const dateStr = dateObj.toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' }) +
      " às " + dateObj.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });

    await emailService.sendAppointmentEmail({
      toEmail: emailCliente,
      patientName: afterData.nomeCliente || 'Cliente',
      shopName: shopName,
      serviceName: afterData.servicoNome || 'Serviço',
      dateStr: dateStr,
      price: afterData.valor,
      isCancellation: mudouStatusParaCancelado,
    });
  } catch (error) {
    console.error("Erro no gatilho onAppointmentUpdatedEmail:", error);
  }
});

exports.deleteUserAccount = onCall(async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Usuário não autenticado');
  }

  const uid = request.auth.uid;

  try {
    const userDoc = await admin.firestore().collection('users').doc(uid).get();

    if (userDoc.exists) {
      const userData = userDoc.data();
      const shopId = userData.shopId;

      // Se tiver loja vinculada (sendo dono)
      if (shopId && userData.papel === 'dono') {
        const shopDoc = await admin.firestore().collection('shops').doc(shopId).get();
        if (shopDoc.exists) {
          const customerId = shopDoc.data().stripeCustomerId;
          // Se tiver um customer do Stripe, cancelar todas as assinaturas dele primeiro
          if (customerId) {
            try {
              const subscriptions = await stripe.subscriptions.list({
                customer: customerId,
                status: 'active',
              });
              for (const sub of subscriptions.data) {
                await stripe.subscriptions.cancel(sub.id);
              }
            } catch (e) {
              console.warn("Stripe cancel warn (exclusão conta):", e.message);
            }
          }
          // Deleta a loja
          await admin.firestore().collection('shops').doc(shopId).delete();
        }
      }

      // Deleta os dados do user 
      await admin.firestore().collection('users').doc(uid).delete();
    }

    // E por fim, deleta o registro no Firebase Authentication
    await admin.auth().deleteUser(uid);

    return { success: true, message: "Conta excluída" };
  } catch (error) {
    console.error("Erro em deleteUserAccount:", error);
    throw new functions.https.HttpsError('internal', "Erro ao excluir conta");
  }
});

