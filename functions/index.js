/* getInstallments HTTP endpoint removed (duplicate). Use the onCall getInstallments defined later in this file.
   The later implementation will be adapted to handle HTTP if needed. */

const functions = require("firebase-functions");
const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require("firebase-functions/v2/firestore");
const { onRequest, onCall } = require("firebase-functions/v2/https");
const { defineString } = require("firebase-functions/params");
const admin = require("firebase-admin");
const axios = require("axios");
const fs = require("fs");
const path = require("path");
const cors = require("cors")({ origin: true });

// Definir parâmetro de ambiente para Google Places API Key
const GOOGLE_PLACES_API_KEY = defineString("GOOGLE_PLACES_API_KEY");

admin.initializeApp();

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
      if (!isBot) {
        return res.redirect(302, siteUrl);
      }
      // Fallback OG for bots when shop not found
      const fallbackHtml = `<!doctype html><html lang="pt-BR"><head>
        <meta charset="utf-8">
        <title>Marka AI</title>
        <meta property="og:title" content="Marka AI" />
        <meta property="og:description" content="Conectando você aos melhores negócios." />
        <meta property="og:image" content="${siteUrl}/icons/Icon-512.png" />
        <meta property="og:url" content="${siteUrl}" />
        <meta property="og:site_name" content="Marka AI" />
        <meta property="og:type" content="website" />
      </head><body></body></html>`;
      return res.status(200).send(fallbackHtml);
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

exports.mercadopagoCallback = onRequest({ cors: true }, async (req, res) => {
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
              <li>Volte para o app MarcaAI.</li>
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

  const clientId = "8404269586602737";
  const clientSecret = "D1NjvPjNYSyUjWMfngTDsO0PDy0DaghB";
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
  console.log("📦 Payload:", JSON.stringify(data));

  const accessToken = data.accessToken || data.access_token || (data.data ? data.data.accessToken : null);
  const amount = parseFloat(data.amount);
  const email = data.email || data.emailCliente || 'cliente@app.com';
  const description = data.description || 'Pagamento App';

  if (!accessToken) {
    throw new functions.https.HttpsError('invalid-argument', 'TOKEN SUMIU (Backend)');
  }

  const idempotencyKey = auth
    ? `pix-${auth.uid}-${Date.now()}`
    : `pix-anon-${Date.now()}-${Math.random().toString(36).substring(7)}`;

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
  const { accessToken, amount, customerId, cardId, installments, description, email, securityCode } = request.data;

  try {
    const tokenResponse = await axios.post(
      `https://api.mercadopago.com/v1/card_tokens?public_key=${data.publicKey || 'PUBLIC_KEY_DA_LOJA_SE_TIVER'}`,
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
      const baseUrl = accessToken && accessToken.startsWith && accessToken.startsWith('TEST-') ? 'https://api.sandbox.mercadopago.com' : 'https://api.mercadopago.com';
      const params = { bin: bin.toString().substring(0, 6), amount: amountNum };
      const headers = accessToken ? { Authorization: `Bearer ${accessToken}` } : {};

      // If we don't have an accessToken, we can't call the installments endpoint authenticated
      // The other implementation used a public_key. We should support that fallback if possible.
      // However, for now we will stick to the existing logic + CORS, as that is the main barrier.

      const response = await axios.get(`${baseUrl}/v1/payment_methods/installments`, { params, headers });
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

    // Validar idToken enviado no body
    let uid = null;
    if (data?.idToken) {
      try {
        const decoded = await admin.auth().verifyIdToken(data.idToken, true);
        uid = decoded.uid;
        console.log('🔐 UID validado:', uid);
      } catch (err) {
        console.warn('⚠️ Token inválido ou expirado, mas continuando...', err.message);
        // NÃO bloqueamos - apenas logamos o erro
      }
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

    // Enforce plan restrictions: shops on 'start' plan cannot process online payments
    if (shopId) {
      try {
        const shopDocCheck = await admin.firestore().collection('shops').doc(shopId).get();
        if (shopDocCheck.exists) {
          const shopPlan = shopDocCheck.data()?.plan || (shopDocCheck.data()?.payment_plan) || 'start';
          if (shopPlan === 'start') {
            console.warn(`Pagamento bloqueado: loja ${shopId} está no plano START (pagamento online não permitido)`);
            return res.status(403).json({
              success: false,
              error: 'Loja no plano START não permite pagamento online. Utilize pagamento presencial.'
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

    const mpPayload = {
      token: cardToken,
      transaction_amount: Number(valor),
      installments: Number(installments) || 1,
      payer: { email: email },
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
// NOTE: checkSubscriptionsDaily is provided as an HTTP endpoint so it can be scheduled via Cloud Scheduler.
// Use Cloud Scheduler to call this URL every 24 hours.
exports.checkSubscriptionsDaily = onRequest({ cors: true }, async (req, res) => {
  try {
    console.log('checkSubscriptionsDaily (http) starting');

    const now = admin.firestore.Timestamp.now();

    // 1) process trials that ended
    const trialSnap = await admin.firestore().collection('subscriptions')
      .where('status', '==', 'trialing')
      .where('trial_end', '<=', now)
      .get();

    for (const doc of trialSnap.docs) {
      const s = doc.data();
      try {
        const userId = s.userId;
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        const user = userDoc.exists ? userDoc.data() : {};
        const paymentMethod = user?.paymentMethod || null;

        if (paymentMethod && paymentMethod.type === 'card' && s.shopId) {
          const shopDoc = await admin.firestore().collection('shops').doc(s.shopId).get();
          const shopData = shopDoc.exists ? shopDoc.data() : {};
          const accessToken = shopData?.mercadopago?.access_token;
          if (accessToken) {
            try {
              const mpPayload = {
                token: paymentMethod.token,
                transaction_amount: Number(s.price) || 0,
                installments: 1,
                payer: { email: user?.email || 'cliente@markaai.com' },
                capture: true,
                description: `Subscription ${s.planId} for user ${userId}`
              };
              const resp = await axios.post('https://api.mercadopago.com/v1/payments', mpPayload, {
                headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' }
              });
              if (resp.data && (resp.data.status === 'approved' || resp.data.status === 'pending')) {
                const nb = new Date();
                nb.setDate(nb.getDate() + 30);
                await doc.ref.update({ status: 'active', next_billing: admin.firestore.Timestamp.fromDate(nb), updatedAt: admin.firestore.Timestamp.now() });
                await admin.firestore().collection('admin_audit').add({ adminUid: 'system', action: 'auto_charge_success', targetId: doc.id, details: resp.data, createdAt: admin.firestore.FieldValue.serverTimestamp() });
                continue;
              }
            } catch (e) {
              console.error('Auto-charge failed:', e.response?.data || e.message || e);
              await doc.ref.update({ status: 'past_due', updatedAt: admin.firestore.Timestamp.now() });
              await admin.firestore().collection('admin_audit').add({ adminUid: 'system', action: 'auto_charge_failed', targetId: doc.id, error: e.response?.data || e.message || String(e), createdAt: admin.firestore.FieldValue.serverTimestamp() });
              continue;
            }
          }
        }

        await doc.ref.update({ status: 'cancelled', updatedAt: admin.firestore.Timestamp.now() });
        await admin.firestore().collection('users').doc(s.userId).set({ plan: 'start' }, { merge: true });
        await admin.firestore().collection('admin_audit').add({ adminUid: 'system', action: 'trial_expired_downgrade', targetId: doc.id, createdAt: admin.firestore.FieldValue.serverTimestamp() });
      } catch (err) {
        console.error('Error processing trial subscription', doc.id, err);
      }
    }

    // 2) process recurring billing due today or past due
    const billingSnap = await admin.firestore().collection('subscriptions')
      .where('status', 'in', ['active', 'past_due'])
      .where('next_billing', '<=', now)
      .get();

    for (const doc of billingSnap.docs) {
      const s = doc.data();
      try {
        const userId = s.userId;
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        const user = userDoc.exists ? userDoc.data() : {};
        const paymentMethod = user?.paymentMethod || null;
        if (paymentMethod && paymentMethod.type === 'card' && s.shopId) {
          const shopDoc = await admin.firestore().collection('shops').doc(s.shopId).get();
          const shopData = shopDoc.exists ? shopDoc.data() : {};
          const accessToken = shopData?.mercadopago?.access_token;
          if (accessToken) {
            try {
              const mpPayload = {
                token: paymentMethod.token,
                transaction_amount: Number(s.price) || 0,
                installments: 1,
                payer: { email: user?.email || 'cliente@markaai.com' },
                capture: true,
                description: `Recurring subscription ${s.planId} for user ${userId}`
              };
              const resp = await axios.post('https://api.mercadopago.com/v1/payments', mpPayload, {
                headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' }
              });
              if (resp.data && resp.data.status === 'approved') {
                const nb = new Date();
                nb.setDate(nb.getDate() + 30);
                await doc.ref.update({ status: 'active', next_billing: admin.firestore.Timestamp.fromDate(nb), updatedAt: admin.firestore.Timestamp.now() });
                await admin.firestore().collection('admin_audit').add({ adminUid: 'system', action: 'recurring_charge_success', targetId: doc.id, details: resp.data, createdAt: admin.firestore.FieldValue.serverTimestamp() });
                continue;
              } else {
                await doc.ref.update({ status: 'past_due', updatedAt: admin.firestore.Timestamp.now() });
                await admin.firestore().collection('admin_audit').add({ adminUid: 'system', action: 'recurring_charge_nonapproved', targetId: doc.id, details: resp.data, createdAt: admin.firestore.FieldValue.serverTimestamp() });
                continue;
              }
            } catch (e) {
              console.error('Recurring charge failed:', e.response?.data || e.message || e);
              await doc.ref.update({ status: 'past_due', updatedAt: admin.firestore.Timestamp.now() });
              await admin.firestore().collection('admin_audit').add({ adminUid: 'system', action: 'recurring_charge_failed', targetId: doc.id, error: e.response?.data || e.message || String(e), createdAt: admin.firestore.FieldValue.serverTimestamp() });
              continue;
            }
          }
        }

        await doc.ref.update({ status: 'past_due', updatedAt: admin.firestore.Timestamp.now() });
        await admin.firestore().collection('admin_notifications').add({
          level: 'warning',
          message: `Subscription ${doc.id} is past due and requires manual action`,
          subscriptionId: doc.id,
          createdAt: admin.firestore.FieldValue.serverTimestamp()
        });
      } catch (err) {
        console.error('Error processing recurring subscription', doc.id, err);
      }
    }

    console.log('checkSubscriptionsDaily: finished');
    return res.status(200).send({ success: true });
  } catch (err) {
    console.error('checkSubscriptionsDaily error:', err);
    return res.status(500).send({ error: String(err) });
  }
});

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

    // Formatar data e hora
    const appointmentDate = appointment.data_agendamento.toDate();
    const dateStr = appointmentDate.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric' });
    const timeStr = appointmentDate.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });

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

      // Formatar data e hora
      const appointmentDate = after.data_agendamento.toDate();
      const dateStr = appointmentDate.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric' });
      const timeStr = appointmentDate.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });

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