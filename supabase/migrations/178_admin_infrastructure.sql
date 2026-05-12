-- Arquivo: supabase/migrations/178_admin_infrastructure.sql
-- Descrição: Infraestrutura completa para o painel admin MarkaAI

-- ==========================================
-- 1. TABELAS
-- ==========================================

-- 1.1 Tabela de histórico de assinaturas
-- NOTA: Se shops(id) for do tipo TEXT no seu banco, altere shop_id para TEXT aqui.
CREATE TABLE IF NOT EXISTS subscription_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id     TEXT NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  old_plan    TEXT,
  new_plan    TEXT NOT NULL,
  changed_by  UUID REFERENCES auth.users(id),
  changed_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reason      TEXT,
  source      TEXT DEFAULT 'manual' -- 'manual', 'stripe', 'admin'
);

ALTER TABLE subscription_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_only" ON subscription_history
  USING ((SELECT role FROM public.users WHERE id = auth.uid()) = 'admin');

-- 1.2 Tabela de feature flags
CREATE TABLE IF NOT EXISTS feature_flags (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  flag_key    TEXT NOT NULL UNIQUE,
  label       TEXT NOT NULL,
  description TEXT,
  enabled_global    BOOLEAN DEFAULT false,
  enabled_for_plans TEXT[] DEFAULT '{}', -- ex: ['plus','pro']
  enabled_for_shops TEXT[] DEFAULT '{}', -- alterado para TEXT[] para compatibilidade
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_rw" ON feature_flags
  USING ((SELECT role FROM public.users WHERE id = auth.uid()) = 'admin');
CREATE POLICY "authenticated_read" ON feature_flags
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- Seed inicial de Feature Flags
INSERT INTO feature_flags (flag_key, label, enabled_for_plans) VALUES
  ('nfse_enabled',         'Emissão de NFS-e',            ARRAY['plus','pro']),
  ('whatsapp_reminders',   'Lembretes WhatsApp',           ARRAY['plus','pro']),
  ('whatsapp_interactive', 'WhatsApp interativo',          ARRAY['pro']),
  ('custom_branding',      'Personalização de marca',      ARRAY['pro']),
  ('multi_location',       'Múltiplas unidades',           ARRAY['pro'])
ON CONFLICT (flag_key) DO NOTHING;

-- 1.3 Tabela de comunicados in-app
CREATE TABLE IF NOT EXISTS admin_announcements (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  type        TEXT DEFAULT 'info', -- 'info', 'warning', 'success', 'critical'
  target_plans TEXT[] DEFAULT '{}', -- vazio = todos
  target_shops TEXT[] DEFAULT '{}', -- alterado para TEXT[] para compatibilidade
  is_active   BOOLEAN DEFAULT true,
  starts_at   TIMESTAMPTZ DEFAULT NOW(),
  expires_at  TIMESTAMPTZ,
  created_by  UUID REFERENCES auth.users(id),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE admin_announcements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_rw" ON admin_announcements
  USING ((SELECT role FROM public.users WHERE id = auth.uid()) = 'admin');
CREATE POLICY "tenant_read" ON admin_announcements
  FOR SELECT USING (
    auth.uid() IS NOT NULL AND
    is_active = true AND
    (expires_at IS NULL OR expires_at > NOW())
  );

-- 1.4 Tabela de auditoria de ações admin
CREATE TABLE IF NOT EXISTS admin_audit_log (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id    UUID NOT NULL REFERENCES auth.users(id),
  action      TEXT NOT NULL, -- 'block_user', 'change_plan', 'impersonate', etc.
  target_type TEXT,          -- 'user', 'shop', 'announcement', etc.
  target_id   TEXT,
  details     JSONB,
  ip_address  TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE admin_audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_only" ON admin_audit_log
  USING ((SELECT role FROM public.users WHERE id = auth.uid()) = 'admin');

-- ==========================================
-- 2. VIEWS
-- ==========================================

-- 2.1 View para KPIs financeiros do admin
CREATE OR REPLACE VIEW admin_revenue_metrics AS
SELECT
  -- MRR: soma de todos os planos pagos ativos
  COALESCE(SUM(
    CASE 
      WHEN s.subscription->>'plano' = 'start' THEN 29.90
      WHEN s.subscription->>'plano' = 'plus'  THEN 59.90
      WHEN s.subscription->>'plano' = 'pro'   THEN 99.90
      ELSE 0
    END
  ), 0) AS mrr,
  -- Contagem por plano
  COUNT(*) FILTER (WHERE s.subscription->>'plano' = 'free')  AS count_free,
  COUNT(*) FILTER (WHERE s.subscription->>'plano' = 'start') AS count_start,
  COUNT(*) FILTER (WHERE s.subscription->>'plano' = 'plus')  AS count_plus,
  COUNT(*) FILTER (WHERE s.subscription->>'plano' = 'pro')   AS count_pro,
  COUNT(*) AS total_shops,
  -- Lojas ativas (com ao menos 1 agendamento nos últimos 30 dias)
  COUNT(DISTINCT a.shop_id) AS active_shops_30d
FROM shops s
LEFT JOIN appointments a 
  ON a.shop_id = s.id 
  AND a.scheduled_at >= NOW() - INTERVAL '30 days'
WHERE s.subscription->>'status' IN ('active', 'trialing');

-- 2.2 View de crescimento diário
CREATE OR REPLACE VIEW admin_growth_daily AS
SELECT
  DATE(created_at) AS dia,
  COUNT(*) AS novos_shops,
  COUNT(*) FILTER (WHERE subscription->>'plano' != 'free') AS novos_pagos
FROM shops
WHERE created_at >= NOW() - INTERVAL '90 days'
GROUP BY DATE(created_at)
ORDER BY dia DESC;

-- 2.3 View de churn mensal
CREATE OR REPLACE VIEW admin_churn_monthly AS
WITH downgraded AS (
  SELECT shop_id, changed_at::date AS mes
  FROM subscription_history
  WHERE old_plan != 'free' AND new_plan = 'free'
),
total_paid AS (
  SELECT DATE_TRUNC('month', created_at) AS mes, COUNT(*) AS total
  FROM shops
  WHERE subscription->>'plano' != 'free'
  GROUP BY 1
)
SELECT 
  tp.mes,
  tp.total AS pagantes_no_mes,
  COALESCE(COUNT(d.shop_id), 0) AS churned,
  ROUND(COALESCE(COUNT(d.shop_id), 0)::numeric / NULLIF(tp.total, 0) * 100, 2) AS churn_rate_pct
FROM total_paid tp
LEFT JOIN downgraded d ON DATE_TRUNC('month', d.mes) = tp.mes
GROUP BY tp.mes, tp.total
ORDER BY tp.mes DESC;
