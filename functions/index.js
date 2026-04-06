const { onRequest } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions');

const SUPABASE_URL = 'https://uhccgcojwqvkfyzrmebv.supabase.co';
const SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjYwNDgsImV4cCI6MjA4OTU0MjA0OH0.bK3UsISxVqw5gJktnBkMwmh7Swb17eV-UgD2Ia9e_PA';

exports.shopPreview = onRequest(
  { region: 'us-east1', timeoutSeconds: 10, minInstances: 0 },
  async (req, res) => {
    const slug = req.path.replace(/^\/+/, '').split('/')[0];
    const shopUrl = `https://markaai.com.br/${slug || ''}`;

    if (!slug) {
      res.redirect(302, 'https://markaai.com.br');
      return;
    }

    try {
      const apiRes = await fetch(
        `${SUPABASE_URL}/rest/v1/shops?slug=eq.${encodeURIComponent(slug)}&select=name,niche,category,city,state,logo_url,description&limit=1`,
        {
          headers: {
            apikey: SUPABASE_ANON_KEY,
            Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
          },
        }
      );

      const shops = await apiRes.json();
      const shop = Array.isArray(shops) ? shops[0] : null;

      if (!shop) {
        res.redirect(302, shopUrl);
        return;
      }

      const name = shop.name || 'MarkaAI';
      const niche = shop.niche || shop.category || '';
      const city = shop.city || '';
      const state = shop.state || '';
      const locationParts = [city, state].filter(Boolean);
      const location = locationParts.join(' — ');
      const subtitle = [niche, location].filter(Boolean).join(' · ');
      const description = subtitle
        ? `${subtitle} · Agende online pelo MarkaAI`
        : `Agende online com ${name} pelo MarkaAI`;
      const image = shop.logo_url || 'https://markaai.com.br/icons/Icon-512.png';

      res.set('Cache-Control', 'public, max-age=300, s-maxage=600');
      res.set('Content-Type', 'text/html; charset=utf-8');
      res.send(`<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <title>${escHtml(name)} · MarkaAI</title>
  <meta name="description" content="${escHtml(description)}">
  <!-- Open Graph -->
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="MarkaAI">
  <meta property="og:url" content="${escHtml(shopUrl)}">
  <meta property="og:title" content="${escHtml(name)}">
  <meta property="og:description" content="${escHtml(description)}">
  <meta property="og:image" content="${escHtml(image)}">
  <meta property="og:image:width" content="400">
  <meta property="og:image:height" content="400">
  <!-- Twitter / WhatsApp fallback -->
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="${escHtml(name)}">
  <meta name="twitter:description" content="${escHtml(description)}">
  <meta name="twitter:image" content="${escHtml(image)}">
  <!-- Redirect for regular browsers -->
  <meta http-equiv="refresh" content="0; url=${escHtml(shopUrl)}">
  <script>window.location.replace('${escJs(shopUrl)}');</script>
</head>
<body style="font-family:sans-serif;text-align:center;padding:40px;color:#333;">
  <p>Redirecionando para <a href="${escHtml(shopUrl)}">${escHtml(name)}</a>…</p>
</body>
</html>`);
    } catch (err) {
      logger.error('shopPreview error:', err);
      res.redirect(302, shopUrl);
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
