-- MarkaAI Affiliate System Migration
-- Created: 2026-03-23

-- 1.1 — Tabela affiliates
CREATE TABLE IF NOT EXISTS affiliates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  store_id UUID REFERENCES shops(id) ON DELETE SET NULL, -- alterado de 'stores' para 'shops' conforme estrutura do projeto
  coupon_code VARCHAR(20) NOT NULL UNIQUE,
  commission_type VARCHAR(20) NOT NULL DEFAULT 'recurring'
    CHECK (commission_type IN ('recurring', 'one_time')),
  status VARCHAR(20) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'active', 'suspended', 'rejected')),
  stripe_account_id VARCHAR(100),         -- ID da conta Stripe Connect do afiliado
  stripe_onboarding_completed BOOLEAN DEFAULT FALSE,
  total_referrals INTEGER DEFAULT 0,
  total_conversions INTEGER DEFAULT 0,
  total_earned_cents BIGINT DEFAULT 0,    -- Valor total ganho (em centavos)
  total_paid_cents BIGINT DEFAULT 0,      -- Valor total já pago (em centavos)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_affiliates_user_id ON affiliates(user_id);
CREATE INDEX IF NOT EXISTS idx_affiliates_coupon_code ON affiliates(coupon_code);
CREATE INDEX IF NOT EXISTS idx_affiliates_status ON affiliates(status);

-- Trigger para updated_at (reusando se existir ou criando)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS affiliates_updated_at ON affiliates;
CREATE TRIGGER affiliates_updated_at
  BEFORE UPDATE ON affiliates
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 1.2 — Tabela affiliate_program_config
CREATE TABLE IF NOT EXISTS affiliate_program_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  commission_recurring_percent DECIMAL(5,2) NOT NULL DEFAULT 10.00, -- % por mês recorrente
  commission_one_time_percent DECIMAL(5,2) NOT NULL DEFAULT 30.00,  -- % apenas no 1º mês
  discount_percent DECIMAL(5,2) NOT NULL DEFAULT 15.00,             -- Desconto dado ao novo cliente
  min_payout_cents INTEGER NOT NULL DEFAULT 5000,                   -- Valor mínimo para saque (R$ 50,00)
  program_active BOOLEAN NOT NULL DEFAULT TRUE,
  allow_store_self_referral BOOLEAN NOT NULL DEFAULT FALSE,         -- Loja nunca usa o próprio cupom
  updated_by UUID REFERENCES auth.users(id),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Inserir configuração padrão se não existir
INSERT INTO affiliate_program_config (
  commission_recurring_percent,
  commission_one_time_percent,
  discount_percent,
  min_payout_cents,
  program_active
) 
SELECT 10.00, 30.00, 15.00, 5000, TRUE
WHERE NOT EXISTS (SELECT 1 FROM affiliate_program_config LIMIT 1);

-- 1.3 — Tabela affiliate_referrals
CREATE TABLE IF NOT EXISTS affiliate_referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  affiliate_id UUID NOT NULL REFERENCES affiliates(id) ON DELETE CASCADE,
  referred_store_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE, -- alterado de 'stores' para 'shops'
  coupon_code_used VARCHAR(20) NOT NULL,
  subscription_id VARCHAR(200),           -- ID da assinatura Stripe
  stripe_customer_id VARCHAR(100),
  discount_applied_cents INTEGER DEFAULT 0,
  commission_type VARCHAR(20) NOT NULL CHECK (commission_type IN ('recurring', 'one_time')),
  status VARCHAR(30) NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'cancelled', 'paused')),
  first_payment_date TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(referred_store_id) -- Uma loja só pode ser referida uma vez
);

CREATE INDEX IF NOT EXISTS idx_referrals_affiliate_id ON affiliate_referrals(affiliate_id);
CREATE INDEX IF NOT EXISTS idx_referrals_referred_store_id ON affiliate_referrals(referred_store_id);

DROP TRIGGER IF EXISTS referrals_updated_at ON affiliate_referrals;
CREATE TRIGGER referrals_updated_at
  BEFORE UPDATE ON affiliate_referrals
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 1.4 — Tabela affiliate_commissions
CREATE TABLE IF NOT EXISTS affiliate_commissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  affiliate_id UUID NOT NULL REFERENCES affiliates(id) ON DELETE CASCADE,
  referral_id UUID NOT NULL REFERENCES affiliate_referrals(id) ON DELETE CASCADE,
  stripe_payment_intent_id VARCHAR(200),  -- Payment do cliente que gerou a comissão
  stripe_transfer_id VARCHAR(200),        -- Transfer enviado ao afiliado
  amount_cents INTEGER NOT NULL,          -- Valor da comissão (em centavos)
  status VARCHAR(30) NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'paid', 'failed', 'refunded')),
  period_start TIMESTAMPTZ,              -- Início do mês de referência
  period_end TIMESTAMPTZ,                -- Fim do mês de referência
  paid_at TIMESTAMPTZ,
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_commissions_affiliate_id ON affiliate_commissions(affiliate_id);
CREATE INDEX IF NOT EXISTS idx_commissions_status ON affiliate_commissions(status);
CREATE INDEX IF NOT EXISTS idx_commissions_referral_id ON affiliate_commissions(referral_id);

DROP TRIGGER IF EXISTS commissions_updated_at ON affiliate_commissions;
CREATE TRIGGER commissions_updated_at
  BEFORE UPDATE ON affiliate_commissions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 1.5 — Tabela affiliate_clicks (tracking de cliques)
CREATE TABLE IF NOT EXISTS affiliate_clicks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  affiliate_id UUID NOT NULL REFERENCES affiliates(id) ON DELETE CASCADE,
  ip_address INET,
  user_agent TEXT,
  referer TEXT,
  converted BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_clicks_affiliate_id ON affiliate_clicks(affiliate_id);
CREATE INDEX IF NOT EXISTS idx_clicks_created_at ON affiliate_clicks(created_at);

-- 1.6 — Row Level Security (RLS)
ALTER TABLE affiliates ENABLE ROW LEVEL SECURITY;
ALTER TABLE affiliate_referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE affiliate_commissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE affiliate_clicks ENABLE ROW LEVEL SECURITY;

-- Políticas para affiliates
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'affiliates_select_own') THEN
    CREATE POLICY "affiliates_select_own" ON affiliates FOR SELECT USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'affiliates_insert_own') THEN
    CREATE POLICY "affiliates_insert_own" ON affiliates FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'affiliates_update_own') THEN
    CREATE POLICY "affiliates_update_own" ON affiliates FOR UPDATE USING (auth.uid() = user_id);
  END IF;
END $$;

-- Admin acessa tudo (verificando role na tabela 'users' conforme projeto)
-- No projeto MarkaAI a tabela de perfis parece ser 'users' ou 'profiles'.
-- Vou usar uma lógica genérica baseada na existência de 'is_admin' ou role 'admin'
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'affiliates_admin_all') THEN
    CREATE POLICY "affiliates_admin_all" ON affiliates FOR ALL USING (
      EXISTS (
        SELECT 1 FROM users -- No projeto a tabela parece ser 'users'
        WHERE users.id = auth.uid() AND (users.role = 'admin' OR users.is_admin = true)
      )
    );
  END IF;
END $$;

-- Políticas para referrals (somente leitura pelo próprio afiliado)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'referrals_select_own') THEN
    CREATE POLICY "referrals_select_own" ON affiliate_referrals FOR SELECT USING (
      EXISTS (
        SELECT 1 FROM affiliates
        WHERE affiliates.id = affiliate_referrals.affiliate_id
        AND affiliates.user_id = auth.uid()
      )
    );
  END IF;
END $$;

-- Políticas para commissions (somente leitura pelo próprio afiliado)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'commissions_select_own') THEN
    CREATE POLICY "commissions_select_own" ON affiliate_commissions FOR SELECT USING (
      EXISTS (
        SELECT 1 FROM affiliates
        WHERE affiliates.id = affiliate_commissions.affiliate_id
        AND affiliates.user_id = auth.uid()
      )
    );
  END IF;
END $$;
