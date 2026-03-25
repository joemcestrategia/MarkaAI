import requests

print("Iniciando auditoria de colunas via API REST...")

URL = "https://uhccgcojwqvkfyzrmebv.supabase.co"
KEY = "sb_publishable_gmX2ol9O_y3XjHt8bJ-NgQ_b2nfxFmR"

headers = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
    "Content-Type": "application/json"
}

tables = ["shops", "users", "services", "appointments", "employees", "categories"]

for t in tables:
    print(f"\n--- Estrutura da Tabela: {t} ---")
    try:
        resp = requests.get(f"{URL}/rest/v1/{t}?select=*&limit=1", headers=headers)
        if resp.status_code == 200:
            data = resp.json()
            if data:
                print(f"Colunas encontradas: {list(data[0].keys())}")
            else:
                print("Tabela vazia. Não é possível inferir colunas por este método.")
        else:
            print(f"Erro {resp.status_code}: {resp.text}")
    except Exception as e:
        print(f"Erro na requisição: {e}")

print("\nSe você tiver uma tabela vazia, eu ainda posso inferir pelos arquivos do projeto.")
print("Fim da auditoria.")
