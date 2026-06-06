const { onRequest } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions');
const fs = require('fs');
const path = require('path');

const SUPABASE_URL = 'https://uhccgcojwqvkfyzrmebv.supabase.co';
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjYwNDgsImV4cCI6MjA4OTU0MjA0OH0.bK3UsISxVqw5gJktnBkMwmh7Swb17eV-UgD2Ia9e_PA';

// Carrega o shell do Flutter app uma vez na inicialização do módulo
let appShellHtml = '';
try {
  appShellHtml = fs.readFileSync(path.join(__dirname, 'app-shell.html'), 'utf8');
} catch (e) {
  logger.warn('app-shell.html não encontrado, usando fallback mínimo');
  appShellHtml = '<!DOCTYPE html><html><head><base href="/"><meta charset="UTF-8"><title>MarkaAI.app</title></head><body><script src="/flutter_bootstrap.js" async></script></body></html>';
}

/**
 * Injeta OG meta tags no HTML do Flutter app shell, substituindo
 * o título e descrição genéricos pelos dados específicos da loja.
 */
function injectOgTags(html, { name, description, image, url }) {
  const ogBlock = `<title>${escHtml(name)} · MarkaAI</title>
  <meta name="description" content="${escHtml(description)}">
  <!-- Open Graph / WhatsApp / Telegram -->
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="MarkaAI">
  <meta property="og:url" content="${escHtml(url)}">
  <meta property="og:title" content="${escHtml(name)}">
  <meta property="og:description" content="${escHtml(description)}">
  <meta property="og:image" content="${escHtml(image)}">
  <meta property="og:image:width" content="400">
  <meta property="og:image:height" content="400">
  <!-- Twitter Card -->
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="${escHtml(name)}">
  <meta name="twitter:description" content="${escHtml(description)}">
  <meta name="twitter:image" content="${escHtml(image)}">`;

  // Substitui o <title> genérico (e adiciona os OG tags no lugar)
  let result = html.replace('<title>MarkaAI.app</title>', ogBlock);
  // Remove a meta description genérica duplicada (já foi incluída no bloco acima)
  result = result.replace(
    /<meta name="description" content="MarkaAI\.app[^"]*">/,
    ''
  );
  return result;
}

exports.shopPreview = onRequest(
  { region: 'us-east1', timeoutSeconds: 10, minInstances: 1 },
  async (req, res) => {
    const reqPath = req.path || '/';

    // Determina se é o caminho legado /preview/{slug} ou direto /{slug}
    const isPreviewPath = reqPath.startsWith('/preview/');
    const rawSlug = isPreviewPath
      ? reqPath.replace(/^\/preview\//, '').split('/')[0]
      : reqPath.replace(/^\/+/, '').split('/')[0];

    const slug = rawSlug || '';
    const shopUrl = `https://markaai.com.br/${slug}`;

    if (!slug) {
      res.redirect(302, 'https://markaai.com.br');
      return;
    }

    try {
      const apiRes = await fetch(
        `${SUPABASE_URL}/rest/v1/shops?slug=ilike.${encodeURIComponent(slug)}&select=name,niche,category,city,state,logo_url&limit=1`,
        {
          headers: {
            apikey: SUPABASE_ANON_KEY,
            Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
          },
        }
      );

      const shops = await apiRes.json();
      const shop = Array.isArray(shops) ? shops[0] : null;

      res.set('Content-Type', 'text/html; charset=utf-8');

      if (!shop) {
        // Slug não corresponde a nenhuma loja → serve o Flutter app normalmente
        res.set('Cache-Control', 'public, max-age=60');
        res.send(appShellHtml);
        return;
      }

      const name = shop.name || 'MarkaAI';
      const niche = shop.niche || shop.category || '';
      const city = shop.city || '';
      const state = shop.state || '';
      const locationParts = [city, state].filter(Boolean);
      const location = locationParts.join(', ');
      const subtitle = [niche, location].filter(Boolean).join(' · ');
      const description = subtitle
        ? `${subtitle} · Agende online pelo MarkaAI`
        : `Agende online com ${name} pelo MarkaAI`;
      const image = shop.logo_url || 'https://markaai.com.br/icons/Icon-512.png';

      res.set('Cache-Control', 'public, max-age=300, s-maxage=600');

      if (isPreviewPath) {
        // Caminho /preview/{slug}: serve HTML mínimo com OG tags + redirect para /{slug}
        // (comportamento legado mantido para compatibilidade com links antigos)
        res.send(`<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <title>${escHtml(name)} · MarkaAI</title>
  <meta name="description" content="${escHtml(description)}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="MarkaAI">
  <meta property="og:url" content="${escHtml(shopUrl)}">
  <meta property="og:title" content="${escHtml(name)}">
  <meta property="og:description" content="${escHtml(description)}">
  <meta property="og:image" content="${escHtml(image)}">
  <meta property="og:image:width" content="400">
  <meta property="og:image:height" content="400">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="${escHtml(name)}">
  <meta name="twitter:description" content="${escHtml(description)}">
  <meta name="twitter:image" content="${escHtml(image)}">
  <meta http-equiv="refresh" content="0; url=${escHtml(shopUrl)}">
  <script>window.location.replace('${escJs(shopUrl)}');</script>
</head>
<body style="font-family:sans-serif;text-align:center;padding:40px;color:#333;">
  <p>Redirecionando para <a href="${escHtml(shopUrl)}">${escHtml(name)}</a>…</p>
</body>
</html>`);
      } else {
        // Caminho direto /{slug}: injeta OG tags no Flutter app shell e serve diretamente.
        // Crawlers (WhatsApp, Telegram, etc.) lêem as OG tags; browsers carregam o Flutter app.
        // Não há redirect, então não existe loop.
        res.send(injectOgTags(appShellHtml, { name, description, image, url: shopUrl }));
      }
    } catch (err) {
      logger.error('shopPreview error:', err);
      // Em caso de erro, serve o Flutter app normalmente
      res.set('Content-Type', 'text/html; charset=utf-8');
      res.send(appShellHtml);
    }
  }
);

function escHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function escJs(str) {
  return String(str).replace(/'/g, "\\'").replace(/\\/g, '\\\\');
}
