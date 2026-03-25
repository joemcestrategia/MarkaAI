#!/usr/bin/env python3
"""
Substitui a lógica de busca IBGE pela lista estática embutida no app.
Remove: iterarEbuscarIBGE, _fetchIBGE, _todasAsCidadesIBGE, _ibgeFetchFuture
Adiciona: import de kMunicipiosBrasil + uso direto na busca
"""

path = r'lib\core\widgets\seletor_de_cidade.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Adiciona o import da lista estática logo após os outros imports
OLD_IMPORT = "import '../../core/theme/app_colors.dart';"
NEW_IMPORT = """import '../../core/theme/app_colors.dart';
import '../../core/data/cidades_brasil.dart';"""

content = content.replace(OLD_IMPORT, NEW_IMPORT, 1)
print("Import adicionado.")

# 2. Substitui o bloco dos campos estáticos + iterarEbuscarIBGE + _fetchIBGE
# pelo getCitySuggestions simplificado
OLD_STATIC_BLOCK_MARKER_START = "  static List<CidadeOpcao>? _todasAsCidadesIBGE;"
OLD_STATIC_BLOCK_MARKER_END = "  static Future<List<CidadeOpcao>> getCitySuggestions(String query) async {"

start_idx = content.find(OLD_STATIC_BLOCK_MARKER_START)
end_idx = content.find(OLD_STATIC_BLOCK_MARKER_END)

if start_idx == -1 or end_idx == -1:
    print(f"ERRO: bloco não encontrado start={start_idx} end={end_idx}")
    exit(1)

old_block = content[start_idx:end_idx]
print(f"Bloco estático encontrado ({len(old_block)} chars)")

# Novo: sem campos estáticos de IBGE, sem fetchIBGE
# Mantemos apenas um método estático simples que usa a lista embutida
NEW_STATIC_BLOCK = """  /// Retorna sugestões de cidades a partir da lista estática embutida no app.
  /// Não depende de rede. Usa kMunicipiosBrasil de cidades_brasil.dart.
  static List<CidadeOpcao> buscarCidadesLocais(String query) {
    if (query.isEmpty) return [];
    final q = StringUtils.removeDiacritics(query).toLowerCase().trim();
    final matches = kMunicipiosBrasil
        .where((e) => StringUtils.removeDiacritics(e.$1).toLowerCase().contains(q))
        .map((e) => CidadeOpcao(cidade: e.$1, estado: e.$2, count: 0))
        .toList();
    matches.sort((a, b) {
      final aNome = StringUtils.removeDiacritics(a.cidade).toLowerCase();
      final bNome = StringUtils.removeDiacritics(b.cidade).toLowerCase();
      final aStarts = aNome.startsWith(q) ? 0 : 1;
      final bStarts = bNome.startsWith(q) ? 0 : 1;
      if (aStarts != bStarts) return aStarts.compareTo(bStarts);
      return a.cidade.compareTo(b.cidade);
    });
    return matches.take(30).toList();
  }

  """

content = content[:start_idx] + NEW_STATIC_BLOCK + content[end_idx:]
print("Bloco estático substituído.")

# 3. Substitui o corpo de getCitySuggestions para usar buscarCidadesLocais
# Localiza o bloco inteiro
GET_CITY_START = "  static Future<List<CidadeOpcao>> getCitySuggestions(String query) async {"
get_start = content.find(GET_CITY_START)

# Encontra o fechamento da função (próximo '  }' no nível correto)
pos = get_start + len(GET_CITY_START)
depth = 1
while pos < len(content) and depth > 0:
    c = content[pos]
    if c == '{':
        depth += 1
    elif c == '}':
        depth -= 1
    pos += 1

get_end = pos  # pos aponta logo após o '}'
old_getCitySuggestions = content[get_start:get_end]
print(f"getCitySuggestions encontrado ({len(old_getCitySuggestions)} chars)")

NEW_GET_CITY = """  static Future<List<CidadeOpcao>> getCitySuggestions(String query) async {
    // Usa lista local para autocomplete - sem dependência de rede
    return buscarCidadesLocais(query);
  }"""

content = content[:get_start] + NEW_GET_CITY + content[get_end:]
print("getCitySuggestions simplificado.")

# 4. Salva
with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f"\nArquivo salvo!")

# Verifica
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()
print(f"Total linhas: {len(lines)}")

# Mostra as linhas relevantes
for i, line in enumerate(lines):
    if any(x in line for x in ['buscarCidadesLocais', 'kMunicipiosBrasil', 'cidades_brasil', '_todasAsCidades', '_ibgeFetchFuture', 'getCitySuggestions']):
        print(f"L{i+1}: {line.rstrip()}")
