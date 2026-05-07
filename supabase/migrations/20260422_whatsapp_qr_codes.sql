-- Tabela temporária para armazenar QR Codes do WhatsApp
-- O QR Code expira em 60s, então esta tabela é de curta duração

CREATE TABLE IF NOT EXISTS whatsapp_qr_codes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  shop_id UUID NOT NULL,
  qr_code TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(shop_id)
);

-- RLS: habilitar mas deixar service_role acesso total
ALTER TABLE whatsapp_qr_codes ENABLE ROW LEVEL SECURITY;

-- Policy simples: apenas service_role acessa (Edge Functions usam service_role)
CREATE POLICY "service_role_all" ON whatsapp_qr_codes
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Index para limpeza automática
CREATE INDEX IF NOT EXISTS idx_wqr_expires ON whatsapp_qr_codes(expires_at);
