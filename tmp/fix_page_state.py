#!/usr/bin/env python3
path = r'lib\core\widgets\seletor_de_cidade.dart'

with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f"Lendo {len(lines)} linhas.")

# 1. Encontrar Bloco _buscarCidades (linhas 944-975 aprox)
# Começa em setState(() => _loading = true);
# Termina antes de String _capitalize(String s) {
start_i = -1
end_i = -1

for i, line in enumerate(lines):
    if i > 900 and 'setState(() => _loading = true);' in line:
        start_i = i
    if start_i != -1 and 'String _capitalize(String s) {' in line:
        end_i = i - 1
        break

if start_i == -1 or end_i == -1:
    print("Erro ao encontrar o bloco de busca.")
    exit(1)

print(f"Bloco de busca localizado: {start_i+1} a {end_i+1}")

new_search_block = [
    "    setState(() => _loading = true);\n",
    "    \n",
    "    // Usa a lista local estática de forma instantânea\n",
    "    final localResult = SeletorDeCidadeModal.buscarCidadesLocais(query);\n",
    "    \n",
    "    final result = localResult.map((m) {\n",
    "      final count = _shopCountByCity[m.cidade.toLowerCase()] ?? 0;\n",
    "      return CidadeOpcao(cidade: m.cidade, estado: m.estado, count: count);\n",
    "    }).toList();\n",
    "\n",
    "    // Ordena: cidades com lojas primeiro (por contagem), depois alfabético\n",
    "    result.sort((a, b) {\n",
    "      if (b.count != a.count) return b.count.compareTo(a.count);\n",
    "      return a.cidade.compareTo(b.cidade);\n",
    "    });\n",
    "\n",
    "    if (mounted) {\n",
    "      setState(() {\n",
    "        _sugestoes = result.take(60).toList();\n",
    "        _loading = false;\n",
    "        _firstLoad = false;\n",
    "      });\n",
    "    }\n",
]

# 2. Encontrar Bloco _normalize (linhas 987-996 aprox)
# Começa com /// Remove acentos para busca sem diacríticos
# Termina antes de void _selecionarCidade
norm_start = -1
norm_end = -1

for i, line in enumerate(lines):
    if i > 970 and 'Remove acentos para busca sem diacr' in line:
        norm_start = i
    if norm_start != -1 and 'void _selecionarCidade(' in line:
        norm_end = i - 1
        break

if norm_start == -1 or norm_end == -1:
    print("Erro ao encontrar o bloco _normalize.")
    exit(1)

print(f"Bloco _normalize localizado: {norm_start+1} a {norm_end+1}")

# Removemos o _normalize completamente pois não há mais chamadas para ele.
# Montamos o novo conteúdo
final_lines = lines[:start_i] + new_search_block + lines[end_i+1:norm_start] + lines[norm_end+1:]

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(final_lines)

print(f"Salvo! Total linhas: {len(final_lines)}")
