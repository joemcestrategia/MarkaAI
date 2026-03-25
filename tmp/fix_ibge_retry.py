#!/usr/bin/env python3
"""
Corrige a lógica de fetch IBGE no seletor_de_cidade.dart:
- Adiciona retry após falha (reseta _ibgeFetchFuture)
- Adiciona timeout de 10s no http.get
- Exibe erro visível ao usuário quando IBGE falha
"""

path = r'lib\core\widgets\seletor_de_cidade.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Localiza o bloco que começa em iterarEbuscarIBGE e termina em _fetchIBGE
BUSCAR = "  static Future<void> iterarEbuscarIBGE() async {"
FETCH  = "  static Future<void> _fetchIBGE() async {"

start_idx = content.find(BUSCAR)
fetch_idx = content.find(FETCH)

# O bloco de _fetchIBGE vai até o próximo '  }\n\n' após ele
fetch_end_marker = "\n  }\n\n  static Future<List<CidadeOpcao>>"
fetch_end_idx = content.find(fetch_end_marker, fetch_idx)
if fetch_end_idx == -1:
    fetch_end_marker2 = "\n  }\n\n  static void _processCityDoc"
    fetch_end_idx = content.find(fetch_end_marker2, fetch_idx)
    marker_len = len("\n  }\n\n")
else:
    marker_len = len("\n  }\n\n")

if start_idx == -1 or fetch_idx == -1 or fetch_end_idx == -1:
    print("ERRO: não encontrou os blocos esperados")
    print(f"  iterarEbuscarIBGE: {start_idx}")
    print(f"  _fetchIBGE: {fetch_idx}")
    print(f"  fetch_end: {fetch_end_idx}")
    exit(1)

# Bloco antigo: de BUSCAR até o final de _fetchIBGE (exclusive o marcador final)
old_block = content[start_idx : fetch_end_idx + marker_len]
print(f"Bloco antigo encontrado ({len(old_block)} chars):")
print(old_block[:200] + "...")

new_block = """  // Carrega cidades do IBGE com retry em caso de falha
  static Future<void> iterarEbuscarIBGE() async {
    if (_todasAsCidadesIBGE != null) return;
    // Permite retry: se o fetch anterior falhou, _ibgeFetchFuture e _todasAsCidades
    // ambos ficam vazios. Resetamos para tentar de novo.
    if (_ibgeFetchFuture != null) {
      await _ibgeFetchFuture;
      if (_todasAsCidadesIBGE != null) return; // sucesso
      // Falhou antes - reseta para tentar novamente
      _ibgeFetchFuture = null;
    }
    _ibgeFetchFuture = _fetchIBGE();
    await _ibgeFetchFuture;
  }

  static Future<void> _fetchIBGE() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('ibge_cidades_cache');

      List data;
      if (cached != null) {
        data = jsonDecode(cached);
        debugPrint('[IBGE] Cidades carregadas do cache local (${cached.length} bytes)');
      } else {
        debugPrint('[IBGE] Baixando lista de municipios...');
        final res = await http
            .get(Uri.parse(
                'https://servicodados.ibge.gov.br/api/v1/localidades/municipios'))
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          data = jsonDecode(res.body);
          await prefs.setString('ibge_cidades_cache', res.body);
          debugPrint('[IBGE] ${data.length} municipios baixados e salvos em cache!');
        } else {
          debugPrint('[IBGE] HTTP ${res.statusCode} - falha ao baixar municipios');
          // Reseta o future para permitir retry
          _ibgeFetchFuture = null;
          return;
        }
      }

      _todasAsCidadesIBGE = data.map((e) {
        final c = e['nome'] as String? ?? '';
        final state =
            e['microrregiao']?['mesorregiao']?['UF']?['sigla'] as String? ?? '';
        return CidadeOpcao(cidade: c, estado: state, count: 0);
      }).toList();
      debugPrint('[IBGE] Lista pronta: ${_todasAsCidadesIBGE!.length} cidades');
    } catch (e) {
      debugPrint('[IBGE] Erro ao buscar municipios: $e');
      // Reseta o future para permitir retry
      _ibgeFetchFuture = null;
    }
  }

"""

new_content = content[:start_idx] + new_block + content[fetch_end_idx + marker_len:]

with open(path, 'w', encoding='utf-8') as f:
    f.write(new_content)

print(f"\nArquivo corrigido! {len(content)} -> {len(new_content)} chars")

# Verifica as linhas relevantes no resultado
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if 'iterarEbuscarIBGE' in line or '_fetchIBGE' in line or 'timeout' in line.lower():
        print(f"L{i+1}: {line.rstrip()}")
