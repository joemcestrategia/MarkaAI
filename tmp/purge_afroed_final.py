import requests

print("Iniciando remoção financeira completa de Afroed...")

URL = "https://uhccgcojwqvkfyzrmebv.supabase.co"
KEY = "sb_publishable_gmX2ol9O_y3XjHt8bJ-NgQ_b2nfxFmR"

headers = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
    "Content-Type": "application/json"
}

try:
    resp = requests.get(f"{URL}/rest/v1/shops?select=id,name&name=ilike.*afroed*", headers=headers)
    shops = resp.json()
    
    if not isinstance(shops, list):
        print(f"Resposta inesperada: {shops}")
    elif not shops:
        print("Nenhuma loja contendo 'afroed' encontrada.")
    else:
        for shop in shops:
            sid = shop['id']
            nome = shop['name']
            print(f"\n--- Limpando dados para: {nome} (ID: {sid}) ---")
            
            # Adicionado tables de finanças e inventário
            tables = [
                "services", "appointments", "coupons", "employees", 
                "schedules", "reviews", "categories", 
                "financial_transactions", "cash_flow", "quick_entries", 
                "inventory", "inventory_movements", "invoices"
            ]
            
            for t in list(tables): 
                # remover em lotes por shop_id
                r = requests.delete(f"{URL}/rest/v1/{t}?shop_id=eq.{sid}", headers=headers)
                print(f"[{t}] Deletado: {r.status_code}")

            # Deletar Loja
            print(f"Deletando loja {nome}...")
            del_resp = requests.delete(f"{URL}/rest/v1/shops?id=eq.{sid}", headers=headers)
            if del_resp.status_code in [200, 204]:
                print(f"Loja {nome} deletada com sucesso!")
            else:
                print(f"Erro ao deletar loja: {del_resp.text}")

except Exception as e:
    print(f"Erro na requisição: {e}")

# Limpar vestígio de scripts temporários de purge se houver
try:
    import os
    os.remove('c:/src/MarkaAI/tmp/purge_afroed_complete.py')
except:
    pass

print("Processo concluído!")
