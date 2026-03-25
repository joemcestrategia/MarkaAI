import requests

print("Iniciando exclusão de Afroed via REST API (Coluna: name)...")

URL = "https://uhccgcojwqvkfyzrmebv.supabase.co"
KEY = "sb_publishable_gmX2ol9O_y3XjHt8bJ-NgQ_b2nfxFmR"

headers = {
    "apikey": KEY,
    "Authorization": f"Bearer {KEY}",
    "Content-Type": "application/json"
}

try:
    # 1. Buscar Loja por 'name'
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
            print(f"Limpando dados para: {nome} (ID: {sid})")
            
            # Deletar filhos (Usando tabelas correspondentes se houver restrições)
            services_resp = requests.delete(f"{URL}/rest/v1/services?shopId=eq.{sid}", headers=headers)
            print(f"Status serviços: {services_resp.status_code}")
            
            appointments_resp = requests.delete(f"{URL}/rest/v1/appointments?shopId=eq.{sid}", headers=headers)
            print(f"Status agendamentos: {appointments_resp.status_code}")
            
            coupons_resp = requests.delete(f"{URL}/rest/v1/coupons?shopId=eq.{sid}", headers=headers)
            print(f"Status coupons: {coupons_resp.status_code}")
            
            # Deletar Loja
            del_resp = requests.delete(f"{URL}/rest/v1/shops?id=eq.{sid}", headers=headers)
            if del_resp.status_code in [200, 204]:
                print(f"Loja {nome} deletada com sucesso!")
            else:
                print(f"Erro ao deletar loja: {del_resp.text}")

except Exception as e:
    print(f"Erro na requisição: {e}")

# Limpar o proprio script de inspeção que sobrou
try:
    import os
    os.remove('c:/src/MarkaAI/tmp/inspect_afroed_rest.py')
    print("inspect_afroed_rest.py removido.")
except:
    pass

print("Processo concluído!")
