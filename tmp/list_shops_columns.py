import sys
import json
import subprocess

def run_query(query):
    try:
        # Tenta usar o CLI do Supabase para pegar as colunas via SQL direto
        cmd = ["supabase", "db", "query", "-r", "uhccgcojwqvkfyzrmebv", f"SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'shops';"]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print(result.stdout)
    except Exception as e:
        print(f"Erro ao rodar query: {e}")

if __name__ == "__main__":
    run_query("")
