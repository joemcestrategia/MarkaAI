import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'

function escapeHtml(unsafe: string) {
  if (!unsafe) return ''
  return unsafe
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;")
}

const siteUrl = 'https://markaai.com.br'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const url = new URL(req.url)
    const slug = (url.pathname.replace(/^\//, '').replace(/\/$/, '') || url.searchParams.get('slug') || '').trim()
    
    if (!slug || slug.includes('.') || slug.startsWith('_')) {
      return new Response('Slug inválido', { status: 400 })
    }

    const ua = req.headers.get('user-agent') || ''
    const isBot = /whatsapp|facebookexternalhit|twitterbot|googlebot|linkedinbot|slackbot|discordbot|telegrambot|applebot|bingbot|yandex/i.test(ua)
    
    // Fetch via Service Role because the route is public
    const supabase = createSupabaseAdminClient()
    const { data: shopDoc } = await supabase.from('shops').select('*').eq('slug', slug).single()

    if (!shopDoc) {
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
        </head><body></body></html>`
        return new Response(fallbackHtml, { headers: { 'Content-Type': 'text/html; charset=utf-8' } })
      }

      const ogHtmlTags = `<title>Marka AI - Não Encontrada</title><meta property="og:title" content="Loja não encontrada" />`
      const fullHtml = `<!doctype html>
      <html lang="pt-BR">
      <head>
        <base href="/">
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        ${ogHtmlTags}
      </head>
      <body style="margin: 0; padding: 0; background: #5B2DB6;">
        <div id="splash" style="position: fixed; inset: 0; background: linear-gradient(180deg, #5B2DB6, #4A1F8A); display: flex; align-items: center; justify-content: center; flex-direction: column; z-index: 9999; color: #fff; font-family: sans-serif;">
          <div style="font-size: 24px; font-weight: bold; margin-bottom: 20px;">Marka AI</div>
          <div style="font-size: 14px; opacity: 0.8;">Carregando...</div>
        </div>
        <script src="flutter_bootstrap.js" async></script>
      </body></html>`
      return new Response(fullHtml, { headers: { 'Content-Type': 'text/html; charset=utf-8' } })
    }

    const name = shopDoc.nome || shopDoc.name || 'Loja MarkaAI'
    const category = shopDoc.categoria || shopDoc.segmento || shopDoc.tipo || ''
    const descricao = shopDoc.descricao || ''
    const address = shopDoc.endereco || shopDoc.address || shopDoc.cidade || ''
    const imageUrl = shopDoc.logoUrl || shopDoc.coverUrl || shopDoc.imageUrl || `${siteUrl}/icons/Icon-512.png`
    const shopUrl = `${siteUrl}/${slug}`

    const ogTitle = category ? `${name} | ${category} [ Reserve agora ]` : `${name} [ Reserve agora ]`
    
    let ogDescription = `Agende sua consulta com ${name}`
    if (address) ogDescription += ` • ${address}`
    if (descricao && descricao.length > 0) ogDescription = descricao

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
    `

    const fullHtml = `<!doctype html>
    <html lang="pt-BR">
    <head>
      <base href="/">
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      ${ogHtmlTags}
      <link rel="icon" type="image/png" href="favicon.png"/>
      <link rel="manifest" href="manifest.json">
    </head>
    <body style="margin: 0; padding: 0; background: #5B2DB6;">
      <div id="splash" style="position: fixed; inset: 0; background: linear-gradient(180deg, #5B2DB6, #4A1F8A); display: flex; align-items: center; justify-content: center; flex-direction: column; z-index: 9999; color: #fff; font-family: sans-serif;">
        <div style="font-size: 24px; font-weight: bold; margin-bottom: 20px;">Marka AI</div>
        <div style="font-size: 14px; opacity: 0.8;">Carregando ${escapeHtml(name)}...</div>
      </div>
      <div style="display: none;">
        <h1>${escapeHtml(name)}</h1>
        <p>${escapeHtml(ogDescription)}</p>
        <a href="${escapeHtml(shopUrl)}">Agendar agora</a>
      </div>
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
    </html>`

    return new Response(fullHtml, { 
      headers: { 
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store, no-cache, must-revalidate, proxy-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0'
      } 
    })

  } catch (err) {
    console.error('publicShopPreview error:', err)
    return new Response('Internal error', { status: 500 })
  }
})
