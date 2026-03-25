import requests

print("Iniciando limpeza ABSOLUTA de todas as tabelas...")

URL = "https://uhccgcojwqvkfyzrmebv.supabase.co"
KEY = "sb_publishable_gmX2ol9O_y3XjHt8bJ-NgQ_b2nfxFmR"

headers = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
    "Content-Type": "application/json"
}

# Lista ordenada de tabelas para respeitar Chaves Estrangeiras (filhos primeiro)
tables = [
    "reviews", 
    "financial_transactions", "cash_flow", "quick_entries", 
    "inventory_movements", "inventory", "invoices", "bank_accounts", 
    "coupons", "appointments", "services", "schedules", "employees", 
    "categories", 
    "shops", "users"
]

for t in tables:
    print(f"\nEsotando limpeza da tabela: {t}...")
    try:
        # Usando .delete() com id=!eq.-1 para forçar deleção de tudo de forma segura via REST
        # (Se a tabela usar UUID, o !eq.-1 pode falhar, então tentamos eq.-1 ou filtragem nula)
        # O mais seguro via REST sem filtro é passar id=not.is.null
        resp = requests.delete(f"{URL}/rest/v1/{t}?id=not.is.null", headers=headers)
        if resp.status_code in [200, 204]:
            print(f"[{t}] Dados limpos com sucesso!")
        elif resp.status_code == 404:
            print(f"[{t}] Tabela não encontrada (404), ignorando.")
        else:
            print(f"[{t}] Status: {resp.status_code} - Resposta: {resp.text}")
    except Exception as e:
        print(f"[{t}] Erro na requisição: {e}")

print("\nLimpeza finalizada via REST API!")
