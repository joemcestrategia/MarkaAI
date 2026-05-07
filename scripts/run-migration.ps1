$supabaseUrl = 'https://uhccgcojwqvkfyzrmebv.supabase.co'
$serviceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Mzk2NjA0OCwiZXhwIjoyMDg5NTQyMDQ4fQ.aT38wj3fJkZSJFa7Ke7WqUSMPCy-zS4Q25kXPLtXwik'

$sql = @"
DROP TABLE IF EXISTS public.whatsapp_messages CASCADE;
DROP TABLE IF EXISTS public.whatsapp_conversations CASCADE;
DROP TABLE IF EXISTS public.whatsapp_qr_codes CASCADE;

ALTER TABLE public.shops 
  DROP COLUMN IF EXISTS whatsapp_instance_id,
  DROP COLUMN IF EXISTS whatsapp_status,
  DROP COLUMN IF EXISTS whatsapp_connected_at,
  DROP COLUMN IF EXISTS ai_agent_enabled,
  DROP COLUMN IF EXISTS ai_agent_name,
  DROP COLUMN IF EXISTS ai_agent_instructions;

CREATE TABLE IF NOT EXISTS public.shop_whatsapp_config (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id text NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  wa_phone_number_id text NOT NULL,
  wa_business_account_id text,
  wa_access_token text NOT NULL,
  wa_webhook_verify_token text NOT NULL,
  wa_template_confirmed_name text,
  wa_template_reminder_name text,
  is_active boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(shop_id)
);

ALTER TABLE public.shop_whatsapp_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner_full_access" ON public.shop_whatsapp_config
  FOR ALL USING (
    shop_id IN (
      SELECT shop_id::text FROM public.users WHERE id = auth.uid()
    ) OR shop_id = auth.uid()::text
  );

CREATE TABLE IF NOT EXISTS public.whatsapp_send_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id text REFERENCES public.shops(id) ON DELETE CASCADE,
  to_phone text NOT NULL,
  template_name text,
  status text NOT NULL,
  response_json jsonb,
  sent_at timestamptz DEFAULT now()
);

ALTER TABLE public.whatsapp_send_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner_read_logs" ON public.whatsapp_send_log
  FOR SELECT USING (
    shop_id IN (
      SELECT shop_id::text FROM public.users WHERE id = auth.uid()
    ) OR shop_id = auth.uid()::text
  );
"@

$headers = @{
  'apikey' = $serviceKey
  'Authorization' = "Bearer $serviceKey"
  'Content-Type' = 'application/json'
  'Prefer' = 'return=minimal'
}

$body = @{ query = $sql } | ConvertTo-Json

Write-Host "Executando migration via API..."
try {
  $r = Invoke-WebRequest -Method POST -Uri "$supabaseUrl/rest/v1/rpc/exec_sql" -Headers $headers -Body $body
  Write-Host "Status: $($r.StatusCode)"
  Write-Host $r.Content
} catch {
  Write-Host "Erro: $($_.Exception.Response.StatusCode) - $($_.Exception.Message)"
  # Tentar endpoint alternativo
  Write-Host "`nTentando via pg..."
}
