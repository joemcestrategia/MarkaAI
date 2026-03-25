// ignore_for_file: use_build_context_synchronously, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'web_helper_stub.dart' if (dart.library.html) 'web_helper_real.dart'
    as web_helper;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

/// Importação de catálogo WhatsApp — apenas Web/PC.
/// Fluxo automático via bookmarklet + postMessage.
class CatalogImportPage extends StatefulWidget {
  const CatalogImportPage({super.key});

  @override
  State<CatalogImportPage> createState() => _CatalogImportPageState();
}

class _CatalogImportPageState extends State<CatalogImportPage> {
  // 0=número, 1=bookmarklet, 2=aguardando, 3=preview, 4=importando, 5=done
  int _step = 0;

  String? _shopId;
  StreamSubscription? _msgSub;

  List<_CatalogProduct> _products = [];
  String _importStatus = '';
  int _importedCount = 0;

  // -- Script do bookmarklet -------------------------------------------------
  // Usa window.opener (quando aberto pelo MarkaAI) OU postMessage via origem
  // Se ambos falharem, copia o JSON pro clipboard como último recurso.
  //
  // NOTA: WhatsApp Web usa classes ofuscadas que mudam frequentemente.
  // Este script usa múltiplas estratégias para extrair dados de forma robusta.
  static String _script(String targetOrigin) =>
      r"""
(async () => {
  const delay = ms => new Promise(r => setTimeout(r, ms));

  // -- Helpers --------------------------------------------------------------
  // Extrai preço numérico de um texto (suporta BRL, R$, valores puros)
  function extractPrice(text) {
    if (!text) return null;
    // Remove "BRL" e "R$" e pega o número
    const cleaned = text.replace(/BRL/gi, '').replace(/R\$/g, '').trim();
    // Formato brasileiro: 1.234,56 ou 1234,56
    const brMatch = cleaned.match(/(\d[\d.]*),(\d{2})/);
    if (brMatch) return brMatch[1].replace(/\./g, '') + '.' + brMatch[2];
    // Formato internacional: 1234.56
    const intMatch = cleaned.match(/(\d+\.\d{2})/);
    if (intMatch) return intMatch[1];
    // Apenas número inteiro
    const intOnly = cleaned.match(/(\d+)/);
    if (intOnly) return intOnly[1];
    return null;
  }

  // Busca a melhor imagem dentro de um elemento
  function findImage(el) {
    // Estratégia 1: img com src CDN do WhatsApp
    let img = el.querySelector('img[src*="whatsapp"]');
    if (img?.src) return img.src;
    // Estratégia 2: img com src blob (preview local)
    img = el.querySelector('img[src^="blob:"]');
    if (img?.src) return img.src;
    // Estratégia 3: img com src https (qualquer CDN)
    img = el.querySelector('img[src^="https"]');
    if (img?.src) return img.src;
    // Estratégia 4: qualquer img com src
    img = el.querySelector('img[src]');
    if (img?.src && !img.src.includes('data:image/gif')) return img.src;
    // Estratégia 5: background-image CSS
    const divs = el.querySelectorAll('div[style*="background-image"]');
    for (const d of divs) {
      const m = d.style.backgroundImage.match(/url\(["']?(.*?)["']?\)/);
      if (m && m[1]) return m[1];
    }
    return '';
  }

  // -- Rola o catálogo para carregar tudo ------------------------------------
  const panel = document.querySelector('[role="list"]');
  if (panel) {
    panel.scrollTop = 0; await delay(400);
    let last = -1;
    for (let i = 0; i < 80; i++) {
      panel.scrollTop += 400; await delay(200);
      if (panel.scrollTop === last) break;
      last = panel.scrollTop;
    }
    panel.scrollTop = 0; await delay(700);
  }

  // -- Extração dos produtos ------------------------------------------------
  const produtos = [];

  // Estratégia A: Buscar por itens de lista no catálogo via [role="list"] > items
  // Estratégia B: Buscar por containers que contêm padrão de preço (BRL/R$)
  // Combinamos ambas para máxima cobertura.

  // Coleta todos os containers candidatos
  let items = [];

  // Tenta seletores conhecidos (vários formatos do WhatsApp Web)
  const selectors = [
    'div._ak72',                           // formato antigo
    '[role="list"] > div',                  // itens diretos da lista
    '[role="listitem"]',                    // listitem semântico
    '[data-testid="catalog-item"]',         // data-testid
    '[role="list"] [role="row"]',            // row dentro de list
  ];
  for (const sel of selectors) {
    const found = document.querySelectorAll(sel);
    if (found.length > items.length) items = [...found];
  }

  // Se nenhum seletor achou, tenta achar divs que contêm "BRL" ou "R$"
  if (items.length === 0) {
    const allDivs = document.querySelectorAll('div');
    const candidates = new Set();
    allDivs.forEach(d => {
      if ((d.innerText?.includes('BRL') || d.innerText?.includes('R$')) && d.children.length > 1) {
        // Sobe até achar o container "item" (div com pouca profundidade)
        let p = d;
        for (let up = 0; up < 4; up++) {
          if (p.parentElement && p.parentElement.children.length > 1) {
            p = p.parentElement;
          } else break;
        }
        candidates.add(p);
      }
    });
    items = [...candidates];
  }

  items.forEach(item => {
    // Coleta todos os textos-folha (sem filhos elemento)
    const allLeafTexts = [...item.querySelectorAll('span,div,p')]
      .map(el => el.childElementCount === 0 ? el.innerText?.trim() : '')
      .filter(t => t && t.length > 0)
      .filter((v,i,a) => a.indexOf(v) === i); // deduplica

    // Acha qual texto contém o preço (BRL xxx ou R$ xxx ou só número)
    let precoRaw = '';
    let precoIdx = -1;
    for (let ti = 0; ti < allLeafTexts.length; ti++) {
      const t = allLeafTexts[ti];
      if (t.includes('BRL') || t.match(/R\$\s*[\d.,]+/)) {
        precoRaw = t;
        precoIdx = ti;
        break;
      }
    }
    // Se não achou preço explícito, procura texto que é só número
    if (!precoRaw) {
      for (let ti = 0; ti < allLeafTexts.length; ti++) {
        const t = allLeafTexts[ti];
        if (/^\d[\d.,]+$/.test(t.trim())) {
          precoRaw = t;
          precoIdx = ti;
          break;
        }
      }
    }

    const preco = extractPrice(precoRaw) ?? '0';

    // Textos não-preço, filtrados
    const textosUteis = allLeafTexts.filter((t, idx) => {
      if (idx === precoIdx) return false;
      if (t.startsWith('BRL')) return false;
      if (/^R\$/.test(t)) return false;
      if (/^\d{2}:\d{2}$/.test(t)) return false;  // horário
      if (/^\d{2}\/\d{2}/.test(t)) return false;  // data
      if (t.length <= 1) return false;
      return true;
    });

    const nome = textosUteis[0] ?? '';
    const descricao = textosUteis.slice(1).join(' ').substring(0, 300);

    // Imagem
    const imagemUrl = findImage(item);

    if (nome) {
      produtos.push({ nome, descricao, preco, imagemUrl });
    }
  });

  // Deduplica por nome
  const uniqueMap = new Map();
  produtos.forEach(p => { if (!uniqueMap.has(p.nome)) uniqueMap.set(p.nome, p); });
  const uniqueProdutos = [...uniqueMap.values()];

  if (!uniqueProdutos.length) { alert('âš ï¸ Nenhum produto encontrado. Abra uma conversa com o catálogo visível.'); return; }

  const payload = JSON.stringify({ type: 'markaai_catalog', produtos: uniqueProdutos });
  
  // Tenta enviar via window.opener (quando aberto pelo MarkaAI)
  if (window.opener && !window.opener.closed) {
    try { window.opener.postMessage(payload, '""" +
      targetOrigin +
      r"""'); alert('? ' + uniqueProdutos.length + ' produtos enviados para o MarkaAI!'); return; } catch(e) {}
  }

  // Fallback: tenta abrir o MarkaAI com dados na URL hash
  const encoded = btoa(unescape(encodeURIComponent(payload)));
  const chunks = Math.ceil(encoded.length / 1500);
  if (chunks <= 1) {
    window.open('""" +
      targetOrigin +
      r"""/#catalog=' + encoded, '_blank');
    alert('? ' + uniqueProdutos.length + ' produtos! A aba do MarkaAI vai receber os dados.');
  } else {
    // Muitos dados: copia JSON pro clipboard
    try { await navigator.clipboard.writeText(payload); alert('? ' + uniqueProdutos.length + ' produtos copiados! Cole no MarkaAI.'); }
    catch(e) {
      const ta = document.createElement('textarea');
      ta.value = payload; document.body.appendChild(ta);
      ta.select(); document.execCommand('copy'); ta.remove();
      alert('? ' + uniqueProdutos.length + ' produtos copiados! Cole no MarkaAI.');
    }
  }
})();
""";

  String get _origin => web_helper.getWindowOrigin();

  String get _bookmarkletHref =>
      'javascript:${Uri.encodeComponent(_script(_origin))}';

  @override
  void initState() {
    super.initState();
    _loadShopId();
    _listenPostMessage();
    _checkHashData(); // verifica se chegaram dados via URL hash
  }

  Future<void> _loadShopId() async {
    String? sId = await SessionService.getShopId();
    if (sId == null || sId.isEmpty) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final data = await Supabase.instance.client
            .from('users')
            .select('shopId')
            .eq('id', user.id)
            .maybeSingle();
        sId = data?['shop_id'] ?? data?['shopId'];
      }
    }
    if (mounted) setState(() => _shopId = sId);
  }

  void _listenPostMessage() {
    _msgSub = web_helper.listenPostMessage((raw) {
      _handlePayload(raw);
    });
  }

  void _checkHashData() {
    try {
      final encoded = web_helper.getHashCatalogData();
      if (encoded != null) {
        final decoded = utf8.decode(base64.decode(encoded));
        _handlePayload(decoded);
      }
    } catch (_) {}
  }

  void _handlePayload(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['type'] != 'markaai_catalog') return;
      final rawList = json['produtos'] as List<dynamic>;
      final parsed = rawList
          .map((e) => _CatalogProduct.fromJson(e as Map<String, dynamic>))
          .toList();
      // Auto-detect invalid items
      for (final p in parsed) {
        if (p.looksInvalid) p.selected = false;
      }
      if (mounted && parsed.isNotEmpty) {
        setState(() {
          _products = parsed;
          _step = 3;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  // -- Formata número e abre WhatsApp Web -----------------------------------
  void _openCatalog() {
    // Abre web.whatsapp.com diretamente para evitar que o Windows intercepte
    // o link wa.me e abra o app do WhatsApp Desktop.
    web_helper.openWindow('https://web.whatsapp.com', 'markaai_wa');
    if (_step <= 1) setState(() => _step = 1);
  }

  void _copyBookmarklet() {
    Clipboard.setData(ClipboardData(text: _bookmarkletHref));
    _snack(
        'URL do bookmarklet copiada! Cole no endereço da URL ao criar o favorito.',
        Colors.green);
  }

  Future<void> _pasteFromClipboard() async {
    String? text;
    try {
      // Usa a API nativa do navegador (mais confiável no Flutter Web)
      text = await web_helper.readClipboardWeb();
    } catch (_) {}
    if (text == null || text.isEmpty) {
      // Fallback: Flutter Clipboard
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text;
    }
    if (text == null || text.isEmpty) {
      _snack(
          'Nada encontrado no clipboard. Clique o favorito no WhatsApp Web primeiro.',
          Colors.orange);
      return;
    }
    _handlePayload(text);
    if (_step != 3) {
      _snack(
          'Formato inválido. Certifique-se de usar o favorito correto no WhatsApp Web.',
          Colors.red);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating));
  }

  // -- Helpers de seleção ----------------------------------------------------
  int get _selectedCount => _products.where((p) => p.selected).length;

  void _toggleAll(bool val) {
    setState(() {
      for (final p in _products) {
        p.selected = val;
      }
    });
  }

  void _removeProduct(int index) {
    setState(() => _products.removeAt(index));
  }

  // -- Importação Firestore + Storage ---------------------------------------
  Future<void> _startImport() async {
    if (_shopId == null) {
      _snack('ID da loja não encontrado.', Colors.red);
      return;
    }
    final toImport = _products.where((p) => p.selected).toList();
    if (toImport.isEmpty) {
      _snack('Nenhum item selecionado para importar.', Colors.orange);
      return;
    }

    debugPrint('?? Importação: shopId=$_shopId, ${toImport.length} itens');

    setState(() {
      _step = 4;
      _importedCount = 0;
      _importStatus = 'Iniciando...';
    });

    int success = 0;
    final List<String> errors = [];
    for (int i = 0; i < toImport.length; i++) {
      final p = toImport[i];
      setState(() =>
          _importStatus = 'Importando ${i + 1}/${toImport.length}: ${p.nome}');
      try {
        final precoStr = p.preco.replaceAll(RegExp(r'[^\d.]'), '');
        final preco = double.tryParse(precoStr) ?? 0.0;

        debugPrint(
            '  ? Salvando "${p.nome}" (R\$ $preco) em services [shopId=$_shopId]');

        // Salva na coleção TOP-LEVEL 'services' com shopId como campo
        // (mesmo padrão do service_register_page.dart)
        await Supabase.instance.client.from('services').insert({
          'name': p.nome,
          'description': p.descricao,
          'price': preco,
          'cost': 0,
          'duration_min': 60,
          'is_active': true,
          'shop_id': _shopId,
          'photos_urls': <String>[],
          'variations': <Map<String, dynamic>>[],
          'requer_aviso': false,
          'mensagem_aviso': '',
          'importado_whatsapp': true,
          'atualizado_em': DateTime.now().toIso8601String(),
        });
        success++;
        setState(() => _importedCount = success);
        debugPrint('  ? "${p.nome}" importado com sucesso');
      } catch (e) {
        debugPrint('  âŒ Erro ${p.nome}: $e');
        errors.add('${p.nome}: $e');
      }
    }
    setState(() {
      _step = 5;
      _importStatus = errors.isEmpty
          ? 'Concluído! $success de ${toImport.length} importados.'
          : 'Concluído! $success de ${toImport.length} importados. '
              '${errors.length} erro(s).';
    });
    debugPrint(
        'ðŸ Importação finalizada: $success/${toImport.length} OK, ${errors.length} erros');
  }

  // -- Build -----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const Scaffold(
          body: Center(child: Text('Apenas disponível na versão web.')));
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: AppColors.primaryPurple,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        title: const Row(children: [
          Icon(Icons.upload_file_rounded, color: Color(0xFF25D366), size: 22),
          SizedBox(width: 10),
          Text('Importar Catálogo WhatsApp',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
        ]),
      ),
      body: Row(children: [
        _buildSidebar(),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(40), child: _buildStep())),
      ]),
    );
  }

  Widget _buildSidebar() {
    const steps = [
      ('Número', Icons.phone_outlined),
      ('Instalar favorito', Icons.bookmark_add_outlined),
      ('Aguardando', Icons.hourglass_top),
      ('Revisar', Icons.checklist),
      ('Importando', Icons.cloud_upload_outlined),
      ('Concluído', Icons.check_circle_outline),
    ];
    return Container(
      width: 205,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Progresso',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 16),
        ...steps.asMap().entries.map((e) {
          final idx = e.key;
          final (label, icon) = e.value;
          final done = idx < _step;
          final active = idx == _step;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(children: [
              Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? Colors.green
                          : active
                              ? AppColors.primaryPurple
                              : Colors.grey[200]),
                  child: Icon(done ? Icons.check : icon,
                      size: 14,
                      color: (done || active) ? Colors.white : Colors.grey)),
              const SizedBox(width: 9),
              Flexible(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              active ? FontWeight.bold : FontWeight.normal,
                          color: active
                              ? AppColors.primaryPurple
                              : done
                                  ? Colors.green
                                  : Colors.grey))),
            ]),
          );
        }),
      ]),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _step0();
      case 1:
        return _step1();
      case 2:
        return _step2();
      case 3:
        return _step3();
      case 4:
        return _step4();
      case 5:
        return _step5();
      default:
        return _step0();
    }
  }

  // -- STEP 0 ----------------------------------------------------------------
  Widget _step0() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _hdr('ðŸŒ', 'Abrir WhatsApp Web',
            'Clique abaixo para abrir o WhatsApp Web no navegador. Lá você vai navegar até o seu catálogo.'),
        const SizedBox(height: 28),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Por que não usamos o link wa.me?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          _tip(
              'No Windows, links wa.me abrem o app WhatsApp Desktop — não o WhatsApp Web. '
              'Por isso abrimos o web.whatsapp.com diretamente no navegador.'),
          const SizedBox(height: 14),
          const Text('Como navegar até o catálogo no WhatsApp Web:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          ..._catalogSteps(),
        ])),
        const SizedBox(height: 28),
        _bigBtn('Abrir WhatsApp Web', _openCatalog,
            color: const Color(0xFF25D366), icon: Icons.open_in_new),
      ]);

  List<Widget> _catalogSteps() {
    final steps = [
      '1. No WhatsApp Web, abra a conversa da sua conta Business',
      '2. Clique no nome/foto da loja no topo da conversa',
      '3. Role para baixo até ver "Ver catálogo" e clique',
      '',
      'Alternativa rápida: pesquise o número da loja e clique em "Ver catálogo"',
    ];
    return steps
        .map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(s,
                  style: TextStyle(
                      color: s.startsWith('Alt')
                          ? Colors.blue[700]
                          : Colors.grey[700],
                      fontStyle: s.startsWith('Alt')
                          ? FontStyle.italic
                          : FontStyle.normal,
                      fontSize: 13,
                      height: 1.5)),
            ))
        .toList();
  }

  // -- STEP 1: Bookmarklet ---------------------------------------------------
  Widget _step1() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _hdr('ðŸ”–', 'Instalar o Favorito (uma única vez)',
            'Salve o bookmarklet na barra de favoritos do Chrome para usar sempre.'),
        const SizedBox(height: 24),
        _infoCard(
            Icons.bookmark_add,
            'Como instalar:',
            [
              '1. Pressione Ctrl+Shift+B para exibir a barra de favoritos',
              '2. Clique com o botão direito na barra de favoritos ? "Adicionar página"',
              '3. Cole a URL copiada pelo botão abaixo no campo de endereço',
              '4. Salve com o nome: ?? MarkaAI — Importar Catálogo',
            ],
            color: Colors.blue[700]!),
        const SizedBox(height: 20),
        // Botão de copiar URL do bookmarklet
        _BookmarkletCopyButton(
            href: _bookmarkletHref, onCopy: _copyBookmarklet),
        const SizedBox(height: 24),
        _infoCard(
            Icons.check_circle_outline,
            'Próximo passo:',
            [
              'Na aba do WhatsApp Web aberta, role o catálogo até o FINAL.',
              'Depois clique no favorito "?? MarkaAI — Importar Catálogo".',
              'Os dados chegam aqui automaticamente — sem copiar nada!',
            ],
            color: const Color(0xFF25D366)),
        const SizedBox(height: 28),
        Row(children: [
          OutlinedButton(
              onPressed: () => setState(() => _step = 0),
              child: const Text('â† Voltar')),
          const SizedBox(width: 14),
          Expanded(
              child: ElevatedButton.icon(
            onPressed: () => setState(() => _step = 2),
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Já instalei — aguardar'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
          )),
        ]),
      ]);

  // -- STEP 2: Aguardando ----------------------------------------------------
  Widget _step2() => Center(
          child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(
              width: 68,
              height: 68,
              child: CircularProgressIndicator(
                  color: Color(0xFF25D366), strokeWidth: 5)),
          const SizedBox(height: 28),
          const Text('Aguardando dados do catálogo...',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(
            'Na aba do WhatsApp Web:\n'
            '1. Role o catálogo até o FINAL (carrega as imagens)\n'
            '2. Clique no favorito "?? MarkaAI — Importar Catálogo"\n'
            '3. Os dados chegam aqui automaticamente!',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Colors.grey[600], fontSize: 14, height: 1.7),
          ),
          const SizedBox(height: 28),
          // -- Opção A: automático via postMessage (já ouvindo) ------------------
          // -- Opção B: colar do clipboard (fallback quando opener=null) ---------
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFF25D366).withValues(alpha: 0.3)),
            ),
            child: Column(children: [
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.content_paste, color: Color(0xFF25D366), size: 20),
                SizedBox(width: 8),
                Text('O favorito copiou os dados?',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF25D366))),
              ]),
              const SizedBox(height: 8),
              Text(
                  'Se apareceu "? X produtos copiados! Cole no MarkaAI.", clique aqui:',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste, size: 20),
                  label: const Text('Colar dados copiados',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: _openCatalog,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Reabrir WhatsApp Web')),
          const SizedBox(height: 10),
          TextButton(
              onPressed: () => setState(() => _step = 1),
              child: const Text('â† Voltar para instalar o favorito')),
        ]),
      ));

  // -- STEP 3: Tabela de seleção ---------------------------------------------
  Widget _step3() {
    final allSelected = _products.every((p) => p.selected);
    final noneSelected = _products.every((p) => !p.selected);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _hdr('?', '${_products.length} itens encontrados',
          'Selecione os serviços que deseja importar. Edite nome, descrição e preço clicando no campo.'),
      const SizedBox(height: 14),
      // -- Toolbar ----------------------------------------------------------
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            color: AppColors.primaryPurple.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Checkbox(
            value: allSelected
                ? true
                : noneSelected
                    ? false
                    : null,
            tristate: true,
            activeColor: AppColors.primaryPurple,
            onChanged: (v) => _toggleAll(v ?? false),
          ),
          const SizedBox(width: 6),
          Text('$_selectedCount de ${_products.length} selecionados',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primaryPurple)),
          const Spacer(),
          if (_products.any((p) => p.looksInvalid))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 15, color: Colors.orange),
                const SizedBox(width: 4),
                Text(
                    '${_products.where((p) => p.looksInvalid).length} parecem conversas',
                    style: const TextStyle(fontSize: 11, color: Colors.orange)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      // -- Tabela -----------------------------------------------------------
      _card(Column(
          children: _products.asMap().entries.map((e) {
        final i = e.key;
        final p = e.value;
        return Column(children: [
          if (i > 0) const Divider(height: 1),
          AnimatedOpacity(
            opacity: p.selected ? 1.0 : 0.45,
            duration: const Duration(milliseconds: 200),
            child: Container(
              color:
                  p.looksInvalid && !p.selected ? Colors.amber.shade50 : null,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(children: [
                // -- Checkbox ----------------------------------------------
                Checkbox(
                  value: p.selected,
                  activeColor: AppColors.primaryPurple,
                  onChanged: (v) => setState(() => p.selected = v ?? false),
                ),
                // -- Imagem -----------------------------------------------
                Container(
                    width: 44,
                    height: 44,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey[100]),
                    child: p.imagemUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(p.imagemUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                    Icons.image_not_supported,
                                    size: 20,
                                    color: Colors.grey)))
                        : const Icon(Icons.image_not_supported,
                            size: 20, color: Colors.grey)),
                // -- Nome + Descrição (editável) --------------------------
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      _editableField(
                          value: p.nome,
                          onChanged: (v) => p.nome = v,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                          hint: 'Nome do serviço'),
                      const SizedBox(height: 2),
                      _editableField(
                          value: p.descricao,
                          onChanged: (v) => p.descricao = v,
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12),
                          hint: 'Descrição'),
                    ])),
                const SizedBox(width: 8),
                // -- Preço (editável) -------------------------------------
                SizedBox(
                    width: 120,
                    child: _editableField(
                        value: p.preco,
                        onChanged: (v) => p.preco = v,
                        style: const TextStyle(
                            color: AppColors.primaryPurple,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                        hint: '0.00',
                        prefix: 'R\$ ')),
                const SizedBox(width: 4),
                // -- Warning icon -----------------------------------------
                if (p.looksInvalid)
                  Tooltip(
                      message: 'Parece ser trecho de conversa',
                      child: Icon(Icons.warning_amber_rounded,
                          size: 18, color: Colors.orange.shade400)),
                // -- Remove button ----------------------------------------
                IconButton(
                    icon:
                        Icon(Icons.close, size: 17, color: Colors.red.shade300),
                    tooltip: 'Remover',
                    onPressed: () => _removeProduct(i),
                    splashRadius: 16,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28)),
              ]),
            ),
          ),
        ]);
      }).toList())),
      const SizedBox(height: 24),
      Row(children: [
        OutlinedButton(
            onPressed: () => setState(() => _step = 2),
            child: const Text('â† Refazer')),
        const SizedBox(width: 14),
        Expanded(
            child: ElevatedButton.icon(
          onPressed: _selectedCount > 0 ? _startImport : null,
          icon: const Icon(Icons.cloud_upload),
          label: Text('Importar $_selectedCount Serviços'),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey[300],
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        )),
      ]),
    ]);
  }

  // -- Campo editável inline -------------------------------------------------
  Widget _editableField({
    required String value,
    required ValueChanged<String> onChanged,
    required TextStyle style,
    String hint = '',
    String prefix = '',
  }) {
    return TextFormField(
      initialValue: value,
      onChanged: onChanged,
      style: style,
      decoration: InputDecoration(
        isDense: true,
        prefixText: prefix.isNotEmpty ? prefix : null,
        prefixStyle: style,
        hintText: hint,
        hintStyle: style.copyWith(color: Colors.grey[400]),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide:
                const BorderSide(color: AppColors.primaryPurple, width: 1.5)),
      ),
    );
  }

  // -- STEP 4: Importando ---------------------------------------------------
  Widget _step4() {
    final prog = _products.isNotEmpty ? _importedCount / _products.length : 0.0;
    return Center(
        child: Padding(
      padding: const EdgeInsets.all(60),
      child: Column(children: [
        const Icon(Icons.cloud_upload,
            size: 60, color: AppColors.primaryPurple),
        const SizedBox(height: 22),
        const Text('Importando produtos...',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(_importStatus,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600])),
        const SizedBox(height: 26),
        LinearProgressIndicator(
            value: prog,
            backgroundColor: Colors.grey[200],
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.primaryPurple),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 10),
        Text('$_importedCount de ${_products.length}',
            style: const TextStyle(
                color: AppColors.primaryPurple, fontWeight: FontWeight.bold)),
      ]),
    ));
  }

  // -- STEP 5: Concluído ----------------------------------------------------
  Widget _step5() => Center(
          child: Padding(
        padding: const EdgeInsets.all(60),
        child: Column(children: [
          const Icon(Icons.check_circle, size: 76, color: Colors.green),
          const SizedBox(height: 22),
          const Text('Importação concluída! ??',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Text(_importStatus,
              style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          const SizedBox(height: 36),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.check),
            label: const Text('Ir para Serviços'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                textStyle:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ),
        ]),
      ));

  // -- Helpers ---------------------------------------------------------------
  Widget _hdr(String emoji, String title, String sub) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emoji, style: const TextStyle(fontSize: 38)),
        const SizedBox(height: 10),
        Text(title,
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87)),
        const SizedBox(height: 7),
        Text(sub, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
      ]);

  Widget _card(Widget child) => Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200)),
        padding: const EdgeInsets.all(18),
        child: child,
      );

  Widget _tip(String text) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade200)),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 15, color: Colors.amber),
          const SizedBox(width: 8),
          Flexible(
              child: Text(text,
                  style: const TextStyle(fontSize: 12, color: Colors.black87))),
        ]),
      );

  Widget _infoCard(IconData icon, String title, List<String> items,
          {Color color = AppColors.primaryPurple}) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 17),
            const SizedBox(width: 8),
            Flexible(
                child: Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 13)))
          ]),
          const SizedBox(height: 10),
          ...items.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(s,
                  style: TextStyle(
                      color: Colors.grey[700], fontSize: 13, height: 1.4)))),
        ]),
      );

  Widget _bigBtn(String label, VoidCallback fn,
          {Color color = AppColors.primaryPurple,
          IconData icon = Icons.arrow_forward}) =>
      SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: fn,
          icon: Icon(icon),
          label: Text(label),
          style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              textStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
        ),
      );
}

// -- Bookmarklet Copy Button ------------------------------------------------
// Cria um <a> real via HtmlElementView para ser arrastável para os favoritos,
// mais um botão Flutter fallback para copiar a URL.
class _BookmarkletCopyButton extends StatefulWidget {
  final String href;
  final VoidCallback onCopy;
  const _BookmarkletCopyButton({required this.href, required this.onCopy});

  @override
  State<_BookmarkletCopyButton> createState() => _BookmarkletCopyButtonState();
}

class _BookmarkletCopyButtonState extends State<_BookmarkletCopyButton> {
  late final String _viewId;
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    _viewId = 'bm-${DateTime.now().microsecondsSinceEpoch}';
    _registered = web_helper.registerBookmarkletView(_viewId, widget.href);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_registered)
        SizedBox(height: 46, child: HtmlElementView(viewType: _viewId))
      else
        ElevatedButton.icon(
          onPressed: widget.onCopy,
          icon: const Icon(Icons.copy),
          label: const Text('Copiar URL do Bookmarklet'),
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white),
        ),
      const SizedBox(height: 10),
      Row(children: [
        const Icon(Icons.touch_app, size: 14, color: Colors.grey),
        const SizedBox(width: 6),
        const Flexible(
            child: Text(
                'Ou clique abaixo para copiar a URL e criar o favorito manualmente:',
                style: TextStyle(fontSize: 12, color: Colors.grey))),
      ]),
      const SizedBox(height: 6),
      TextButton.icon(
        onPressed: widget.onCopy,
        icon: const Icon(Icons.copy, size: 15),
        label: const Text('Copiar URL do Bookmarklet'),
      ),
    ]);
  }
}

// -- Modelo --------------------------------------------------------------------
class _CatalogProduct {
  String nome, descricao, preco, imagemUrl;
  bool selected = true;

  _CatalogProduct({
    required this.nome,
    required this.descricao,
    required this.preco,
    required this.imagemUrl,
  });

  /// Heurística: detecta itens que parecem ser trechos de conversa
  bool get looksInvalid {
    final precoNum = double.tryParse(preco.replaceAll(RegExp(r'[^\d.]'), ''));
    if (precoNum == null || precoNum <= 0) return true;
    if (nome.trim().length < 3) return true;
    if (nome.startsWith('~')) return true;
    // Padrões de data (dd/mm, dd/mm/yyyy) ou hora (HH:MM)
    if (RegExp(r'\d{2}/\d{2}(/\d{2,4})?').hasMatch(nome)) return true;
    if (RegExp(r'^\d{2}:\d{2}$').hasMatch(nome.trim())) return true;
    // Começa com nome de contato do WhatsApp
    if (nome.contains('Dentro do papo') || nome.contains('está como')) {
      return true;
    }
    return false;
  }

  factory _CatalogProduct.fromJson(Map<String, dynamic> j) => _CatalogProduct(
        nome: j['nome']?.toString() ?? '',
        descricao: j['descricao']?.toString() ?? '',
        preco: j['preco']?.toString() ?? '0',
        imagemUrl: j['imagemUrl']?.toString() ?? '',
      );
}
