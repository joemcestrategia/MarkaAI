import requests

print("Verificando se a tabela 'shops' está 100% vazia...")

URL = "https://uhccgcojwqvkfyzrmebv.supabase.co"
KEY = "sb_publishable_gmX2ol9O_y3XjHt8bJ-NgQ_b2nfxFmR"

headers = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
    "Content-Type": "application/json"
}

try:
    # Buscar todas as lojas
    resp = requests.get(f"{URL}/rest/v1/shops?select=id,name,slug", headers=headers)
    if resp.status_code == 200:
        shops = resp.json()
        if not shops:
            print("Sucesso: A tabela 'shops' está COMPLETAMENTE VAZIA (0 linhas).")
        else:
            print(f"Atenção: Foram encontradas {len(shops)} lojas:")
            for s in shops:
                print(f"- {s.get('name')} | Slug: {s.get('slug')} | ID: {s.get('id')}")
    else:
        print(f"Erro ao consultar: {resp.status_code} - {resp.text}")

except Exception as e:
    print(f"Erro na requisição: {e}")

print("Fim da verificação.")
