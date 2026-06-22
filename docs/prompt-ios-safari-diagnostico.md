# 🔍 Diagnóstico: MarkaAI travando no Safari/iOS

## Contexto do problema

O app MarkaAI (Flutter Web) apresenta falhas intermitentes de carregamento em iPhones:
- Tela branca após clicar no link
- Travamento na Splash Screen sem progredir
- Carregamento infinito (spinner que nunca termina)
- O problema se resolve ao **fechar outras abas do Safari** — o que indica pressão de memória RAM

Um cliente confirmou que o app abriu normalmente após fechar abas abertas.

## Stack do projeto

- **Frontend:** Flutter Web
- **Hospedagem:** VPS Ubuntu/Docker (self-hosted)
- **Servidor web:** Nginx (ou Caddy — confirmar)
- **Autenticação:** Supabase Auth
- **Build:** `flutter build web` (verificar renderer atual)

---

## Causas prováveis a investigar

### 🔴 Causa #1 — Web Renderer CanvasKit (alta prioridade)

O Flutter Web usa por padrão o renderer **CanvasKit**, que baixa um arquivo `.wasm` de ~5MB antes de renderizar qualquer coisa. No Safari do iPhone, isso consome muita RAM durante a inicialização.

**Verificar:**
- Qual renderer está sendo usado no build atual?
- Existe o arquivo `canvaskit.wasm` sendo servido?

```bash
# No diretório build/web, verificar presença de:
ls build/web/canvaskit/
# Se existir canvaskit.wasm, o app está usando CanvasKit
```

**Solução esperada:** Recompilar com HTML renderer:
```bash
flutter build web --web-renderer html --release
```

---

### 🔴 Causa #2 — Ausência de compressão gzip/brotli no Nginx (alta prioridade)

Sem compressão, os arquivos JS do Flutter chegam ao Safari com tamanho total de **2MB a 8MB**, aumentando o tempo de carregamento e a pressão de memória durante o download simultâneo dos chunks.

**Verificar no `nginx.conf` ou no site config:**

```nginx
# Deve existir algo assim:
gzip on;
gzip_types application/javascript application/wasm text/css;
gzip_min_length 1024;
```

**Testar via curl:**
```bash
curl -I -H "Accept-Encoding: gzip" https://[dominio-do-app]/main.dart.js | grep content-encoding
# Esperado: content-encoding: gzip
```

Se não retornar `gzip`, a compressão não está ativa.

---

### 🟡 Causa #3 — Service Worker com cache desatualizado ou ausente

O Flutter Web gera um `flutter_service_worker.js` que, quando ativo, faz o app carregar do cache local na segunda visita — eliminando downloads e reduzindo drasticamente o uso de memória inicial.

**Verificar:**
- O arquivo `flutter_service_worker.js` existe no `build/web/`?
- O Nginx está servindo ele com os headers corretos?
- O servidor não está mandando `Cache-Control: no-cache` nos assets Flutter?

**Headers corretos para assets Flutter:**
```nginx
location ~* \.(js|wasm|css|png|jpg)$ {
    expires 1y;
    add_header Cache-Control "public, immutable";
}

location = /flutter_service_worker.js {
    add_header Cache-Control "no-cache";
}
```

---

### 🟡 Causa #4 — Timeout ou falha silenciosa no carregamento do engine

Se o Flutter engine não carregar (por falta de memória ou timeout de rede), a Splash Screen permanece exibida indefinidamente sem nenhuma mensagem ao usuário.

**Verificar no `web/index.html`:**
- Existe algum listener para `flutter-first-frame`?
- Existe fallback de timeout com mensagem ao usuário?

**Solução esperada — adicionar ao `web/index.html`:**
```html
<script>
  // Remove splash quando o Flutter estiver pronto
  window.addEventListener('flutter-first-frame', function() {
    const splash = document.getElementById('loading');
    if (splash) splash.style.display = 'none';
  });

  // Fallback: após 10s, orienta o usuário
  setTimeout(function() {
    const loading = document.getElementById('loading');
    if (loading && loading.style.display !== 'none') {
      const msg = document.getElementById('loading-message');
      if (msg) msg.innerText = 'Demorando mais que o esperado. Tente fechar outras abas do Safari e recarregue a página.';
    }
  }, 10000);
</script>
```

---

### 🟠 Causa #5 — Bundle JS não dividido (code splitting ausente)

O Flutter Web por padrão gera um único `main.dart.js` com **todo o código da aplicação**. Em iPhones com pouca RAM livre, carregar esse arquivo inteiro de uma vez pode causar o crash da aba.

**Verificar tamanho do bundle:**
```bash
ls -lh build/web/main.dart.js
# Se > 3MB sem gzip, é um fator de risco
```

**Solução esperada:** Usar `deferred` imports nas rotas pesadas que não são necessárias no login:
```dart
import 'package:marka/screens/agenda_screen.dart' deferred as agenda;
import 'package:marka/screens/relatorios_screen.dart' deferred as relatorios;
```

---

### 🟠 Causa #6 — Headers de segurança bloqueando SharedArrayBuffer (CanvasKit)

O CanvasKit requer `SharedArrayBuffer`, que no Safari só funciona se o servidor enviar os headers:
```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

Sem esses headers, o CanvasKit falha silenciosamente em alguns iPhones (especialmente iOS 15+).

**Verificar:**
```bash
curl -I https://[dominio-do-app]/ | grep -i "cross-origin"
```

---

## Checklist de verificação (ordem de prioridade)

| # | Verificação | Comando/Local | Esperado |
|---|---|---|---|
| 1 | Renderer do build | `ls build/web/canvaskit/` | Idealmente ausente (HTML renderer) |
| 2 | Gzip ativo | `curl -I -H "Accept-Encoding: gzip" [url]/main.dart.js` | `content-encoding: gzip` |
| 3 | Tamanho do main.dart.js | `ls -lh build/web/main.dart.js` | < 2MB com gzip |
| 4 | Service Worker presente | `ls build/web/flutter_service_worker.js` | Arquivo existe |
| 5 | Cache-Control nos assets | Headers do Nginx | `immutable` para JS/WASM |
| 6 | Fallback no index.html | `web/index.html` | Listener `flutter-first-frame` + timeout |
| 7 | Headers COOP/COEP | `curl -I [url]/` | Presentes se usar CanvasKit |

---

## Ação imediata recomendada

1. **Verificar o renderer atual** (`canvaskit` ou `html`)
2. Se for CanvasKit → **recompilar com `--web-renderer html`** e fazer deploy
3. **Ativar gzip no Nginx** para `.js` e `.wasm`
4. **Adicionar fallback de timeout** no `index.html` com orientação ao usuário

Essas 4 ações devem resolver 90%+ dos casos relatados.

---

## Observação importante

Não alterar lógica de negócio, rotas, autenticação Supabase ou qualquer funcionalidade existente. O escopo é **exclusivamente infraestrutura de carregamento e configuração do servidor web**.
