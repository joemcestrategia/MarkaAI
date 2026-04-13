-- 142_financial_dashboard_enhancements.sql
-- Adiciona campos necessários para o painel financeiro avançado

-- 1. Campo de custo percentual nos serviços (custo como % do preço de venda)
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS cost_percent NUMERIC DEFAULT 0
    CHECK (cost_percent >= 0 AND cost_percent <= 100);

COMMENT ON COLUMN public.services.cost_percent IS
  'Percentual do preço do serviço que representa o custo (materiais, etc). Ex: 30 = 30% do preço é custo.';

-- 2. Flag de reagendamento nos agendamentos
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS is_rescheduled BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN public.appointments.is_rescheduled IS
  'TRUE se este agendamento passou por pelo menos um reagendamento.';

-- 3. Contador de reagendamentos (quantas vezes foi reagendado)
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS reschedule_count INTEGER DEFAULT 0;

COMMENT ON COLUMN public.appointments.reschedule_count IS
  'Número de vezes que este agendamento foi reagendado.';

-- 4. Garantir que financial_goals existe e usa colunas snake_case
DO $$
BEGIN
  -- Cria a tabela se não existir
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'financial_goals'
  ) THEN
    CREATE TABLE public.financial_goals (
      id          BIGSERIAL PRIMARY KEY,
      goal_id     TEXT NOT NULL,
      shop_id     TEXT NOT NULL,
      value       NUMERIC DEFAULT 0,
      year        INTEGER,
      month       INTEGER,
      updated_at  TIMESTAMPTZ DEFAULT now()
    );
    -- RLS
    ALTER TABLE public.financial_goals ENABLE ROW LEVEL SECURITY;
    CREATE POLICY "Shop owner manages goals"
      ON public.financial_goals
      USING (true)
      WITH CHECK (true);
  ELSE
    -- Renomear shopId → shop_id se necessário
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'financial_goals' AND column_name = 'shopId'
    ) THEN
      ALTER TABLE public.financial_goals RENAME COLUMN "shopId" TO shop_id;
    END IF;
    -- Adicionar shop_id se ainda não existir
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'financial_goals' AND column_name = 'shop_id'
    ) THEN
      ALTER TABLE public.financial_goals ADD COLUMN shop_id TEXT;
    END IF;
    -- Renomear updatedAt → updated_at se necessário
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'financial_goals' AND column_name = 'updatedAt'
    ) THEN
      ALTER TABLE public.financial_goals RENAME COLUMN "updatedAt" TO updated_at;
    END IF;
  END IF;
END $$;
