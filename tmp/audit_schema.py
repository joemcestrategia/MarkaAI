import requests

print("Consultando a estrutura de chaves do Supabase (OpenAPI)...")

URL = "https://uhccgcojwqvkfyzrmebv.supabase.co"
KEY = "sb_publishable_gmX2ol9O_y3XjHt8bJ-NgQ_b2nfxFmR"

headers = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
}

try:
    resp = requests.get(f"{URL}/rest/v1/", headers=headers)
    print("Status Code:", resp.status_code)
    
    if resp.status_code == 200:
        data = resp.json()
        print("\n--- TABELAS ENCONTRADAS ---")
        paths = data.get("paths", {})
        for path in paths.keys():
            if path.startswith("/") and len(path) > 1 and "rpc" not in path:
                table_name = path.replace("/", "")
                print(table_name)
    else:
        print("Erro ao ler OpenAPI:", resp.text)

except Exception as e:
    print(f"Erro na requisição: {e}")
