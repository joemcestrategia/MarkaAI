
# Script para criar a tabela whatsapp_qr_codes via Supabase Management API
# Usando a service_role que está nos env secrets do Supabase

$projectRef = 'uhccgcojwqvkfyzrmebv'
$supabaseUrl = "https://$projectRef.supabase.co"

# Usar a anon key para autenticar (não temos a service role no frontend)
# Mas podemos usar o endpoint de query da Management API se tivermos o access token
# Por enquanto, vamos tentar via a Supabase REST API com o endpoint correto

Write-Host "Tentando criar tabela via Supabase REST..."

# Verificar se a tabela já existe
$anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjYwNDgsImV4cCI6MjA4OTU0MjA0OH0.bK3UsISxVqw5gJktnBkMwmh7Swb17eV-UgD2Ia9e_PA'

$headers = @{
  'apikey' = $anonKey
  'Authorization' = "Bearer $anonKey"
}

try {
  $r = Invoke-WebRequest -Uri "$supabaseUrl/rest/v1/whatsapp_qr_codes?limit=1" -Headers $headers
  Write-Host "Tabela JÁ EXISTE! Status: $($r.StatusCode)"
} catch {
  $statusCode = $_.Exception.Response.StatusCode.value__
  Write-Host "Tabela não existe (Status: $statusCode) - precisa ser criada manualmente"
  Write-Host "Acesse: https://supabase.com/dashboard/project/$projectRef/editor"
  Write-Host ""
  Write-Host "E execute este SQL:"
  Write-Host @"
CREATE TABLE IF NOT EXISTS whatsapp_qr_codes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  shop_id UUID NOT NULL,
  qr_code TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(shop_id)
);
ALTER TABLE whatsapp_qr_codes ENABLE ROW LEVEL SECURITY;
CREATE POLICY IF NOT EXISTS "service_role_all" ON whatsapp_qr_codes FOR ALL USING (true);
"@
}
