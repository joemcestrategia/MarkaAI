#!/usr/bin/env python3
"""
Baixa os municípios do IBGE (com suporte a gzip) e gera um arquivo Dart estático.
"""
import urllib.request
import json
import gzip
import os

print("Baixando municípios do IBGE...")
url = 'https://servicodados.ibge.gov.br/api/v1/localidades/municipios'

req = urllib.request.Request(url, headers={'Accept-Encoding': 'gzip, deflate', 'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        raw_bytes = resp.read()
        # Tenta decomprimir se vier gzip
        try:
            raw = gzip.decompress(raw_bytes).decode('utf-8')
            print("Descomprimido de gzip.")
        except Exception:
            raw = raw_bytes.decode('utf-8')
    data = json.loads(raw)
    print(f"Baixados {len(data)} municípios.")
except Exception as e:
    print(f"ERRO ao baixar: {e}")
    exit(1)

# Extrai nome e UF
cidades = []
for m in data:
    nome = m.get('nome', '')
    uf = ''
    try:
        uf = m['microrregiao']['mesorregiao']['UF']['sigla']
    except (KeyError, TypeError):
        pass
    if nome:
        cidades.append((nome, uf))

# Ordena alfabeticamente por nome
cidades.sort(key=lambda x: x[0])

# Gera o arquivo Dart
output_path = r'lib\core\data\cidades_brasil.dart'
os.makedirs(os.path.dirname(output_path), exist_ok=True)

with open(output_path, 'w', encoding='utf-8') as f:
    f.write("// AUTO-GERADO — NÃO EDITE MANUALMENTE\n")
    f.write("// Fonte: IBGE - Localidades/Municípios\n")
    f.write(f"// Total: {len(cidades)} municípios\n\n")
    f.write("const List<(String cidade, String uf)> kMunicipiosBrasil = [\n")
    for nome, uf in cidades:
        nome_escaped = nome.replace("'", "\\'")
        f.write(f"  ('{nome_escaped}', '{uf}'),\n")
    f.write("];\n")

print(f"\nArquivo gerado: {output_path}")
print(f"Total: {len(cidades)} municípios")
print("\nPrimeiros 10:")
for nome, uf in cidades[:10]:
    print(f"  {nome} - {uf}")
print("Últimos 5:")
for nome, uf in cidades[-5:]:
    print(f"  {nome} - {uf}")
