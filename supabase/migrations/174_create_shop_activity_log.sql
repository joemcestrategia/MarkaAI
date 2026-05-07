-- Log de atividades detalhado por loja
-- Registra: criação de agendamento, reagendamento, cancelamento, pagamento confirmado
-- EXECUTAR NO SUPABASE SQL EDITOR

CREATE TABLE IF NOT EXISTS shop_activity_log (
  id             UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  shop_id        TEXT        NOT NULL,
  appointment_id TEXT,
  event_type     TEXT        NOT NULL
    CHECK (event_type IN (
      'agendamento_criado',
      'reagendamento',
      'pagamento_confirmado',
      'agendamento_cancelado',
      'status_alterado'
    )),
  actor_type     TEXT        NOT NULL DEFAULT 'sistema'
    CHECK (actor_type IN ('cliente', 'dono', 'sistema')),
  actor_name     TEXT,
  description    TEXT        NOT NULL DEFAULT '',
  metadata       JSONB       DEFAULT '{}',
  created_at     TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shop_activity_shop_date
  ON shop_activity_log (shop_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_shop_activity_appointment
  ON shop_activity_log (appointment_id)
  WHERE appointment_id IS NOT NULL;

ALTER TABLE shop_activity_log ENABLE ROW LEVEL SECURITY;

-- Donos leem apenas sua própria loja
CREATE POLICY "owner_read_activity"
  ON shop_activity_log FOR SELECT
  USING (
    shop_id IN (
      SELECT s.id FROM shops s WHERE s.owner_id::text = auth.uid()::text
      UNION
      SELECT u.shop_id FROM users u
        WHERE u.id::text = auth.uid()::text AND u.shop_id IS NOT NULL
    )
  );

-- service_role tem acesso total (Edge Functions)
CREATE POLICY "service_role_all_activity"
  ON shop_activity_log FOR ALL
  USING (auth.role() = 'service_role');
