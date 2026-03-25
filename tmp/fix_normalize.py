#!/usr/bin/env python3
# Script para corrigir o método _normalize corrompido no seletor_de_cidade.dart

path = r'lib\core\widgets\seletor_de_cidade.dart'

with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f"Total linhas: {len(lines)}")

# Localiza onde começa o _normalize (busca por padrão único)
start_normalize = None
end_normalize = None
start_buscar = None
end_buscar = None

for i, line in enumerate(lines):
    stripped = line.strip()
    if '_normalize(String s) {' in line and start_normalize is None:
        start_normalize = i
        print(f"_normalize encontrado na linha {i+1}: {stripped}")
    if start_normalize is not None and end_normalize is None:
        if stripped == '}' and i > start_normalize:
            end_normalize = i
            print(f"_normalize termina na linha {i+1}")
    if '_buscarCidades(String query) async {' in line:
        start_buscar = i
        print(f"_buscarCidades encontrado na linha {i+1}")
    if start_buscar is not None and end_buscar is None and '} catch (_) {' in line:
        # pega até o próximo '  }' após o catch
        pass
    if start_buscar is not None and end_buscar is None and stripped == '}' and i > (start_buscar + 5):
        # Verifica que é o fechamento da função _buscarCidades (linha em branco depois)
        if i + 1 < len(lines) and lines[i+1].strip() == '':
            end_buscar = i
            print(f"_buscarCidades termina na linha {i+1}")

print(f"\nsubstituindo linhas {start_normalize+1} a {end_normalize+1} (_normalize)")
print(f"substituindo linhas {start_buscar+1} a {end_buscar+1} (_buscarCidades)")

# Novo _normalize (2 linhas)
new_normalize = [
    "  String _normalize(String s) =>\r\n",
    "      StringUtils.removeDiacritics(s).toLowerCase().trim();\r\n",
]

# Novo _buscarCidades
new_buscar = [
    "  Future<void> _buscarCidades(String query) async {\r\n",
    "    if (query.isEmpty) {\r\n",
    "      if (mounted) setState(() => _sugestoes = []);\r\n",
    "      return;\r\n",
    "    }\r\n",
    "    \r\n",
    "    if (mounted) setState(() => _loading = true);\r\n",
    "    \r\n",
    "    try {\r\n",
    "      await SeletorDeCidadeModal.iterarEbuscarIBGE();\r\n",
    "      final ibgeList = SeletorDeCidadeModal._todasAsCidadesIBGE;\r\n",
    "      if (ibgeList == null) throw Exception('IBGE error');\r\n",
    "\r\n",
    "      final q = _normalize(query);\r\n",
    "      final matches = ibgeList.where((m) {\r\n",
    "        final nome = _normalize(m.cidade);\r\n",
    "        return nome.contains(q);\r\n",
    "      }).toList();\r\n",
    "\r\n",
    "      // Prioriza cidades que COMECAM com o termo digitado\r\n",
    "      matches.sort((a, b) {\r\n",
    "        final aNome = _normalize(a.cidade);\r\n",
    "        final bNome = _normalize(b.cidade);\r\n",
    "        final aStarts = aNome.startsWith(q) ? 0 : 1;\r\n",
    "        final bStarts = bNome.startsWith(q) ? 0 : 1;\r\n",
    "        if (aStarts != bStarts) return aStarts.compareTo(bStarts);\r\n",
    "        return a.cidade.compareTo(b.cidade);\r\n",
    "      });\r\n",
    "\r\n",
    "      if (mounted) {\r\n",
    "        setState(() {\r\n",
    "          _sugestoes = matches.take(30).toList();\r\n",
    "          _loading = false;\r\n",
    "        });\r\n",
    "      }\r\n",
    "    } catch (e) {\r\n",
    "      debugPrint('[SeletorDeCidade] Erro ao buscar cidades: $e');\r\n",
    "      if (mounted) setState(() => _loading = false);\r\n",
    "    }\r\n",
    "  }\r\n",
]

# Reconstrói o arquivo em ordem: antes do normalize, novo normalize, entre, novo buscar, depois do buscar
# Identifica a linha em branco entre os dois métodos
# (normalmente end_normalize+1 é uma linha em branco, start_buscar é o início de _buscarCidades)

new_lines = (
    lines[:start_normalize] +
    new_normalize +
    ["\r\n"] +  # linha em branco entre os métodos
    new_buscar +
    ["\r\n"] +  # linha em branco após _buscarCidades
    lines[end_buscar + 2:]  # pula linha em branco já existente após a função
)

with open(path, 'w', encoding='utf-8') as f:
    f.writelines(new_lines)

print(f"\nArquivo corrigido com sucesso! Nova contagem: {len(new_lines)} linhas")

# Verifica o resultado
with open(path, 'r', encoding='utf-8') as f:
    result = f.readlines()

for i in range(start_normalize, min(start_normalize + 45, len(result))):
    print(f"{i+1}: {result[i]}", end='')
