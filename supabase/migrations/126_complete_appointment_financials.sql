-- 126_complete_appointment_financials.sql
-- Consolidação e padronização de todas as colunas financeiras e de descontos nos agendamentos

DO $$ 
BEGIN 
    -- 1. Métodos e Status de Pagamento
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='payment_method') THEN
        ALTER TABLE public.appointments ADD COLUMN payment_method TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='payment_status') THEN
        ALTER TABLE public.appointments ADD COLUMN payment_status TEXT DEFAULT 'pendente';
    END IF;

    -- 2. Detalhamento de Descontos e Valores
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='discount_amount') THEN
        ALTER TABLE public.appointments ADD COLUMN discount_amount NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='total_payable') THEN
        ALTER TABLE public.appointments ADD COLUMN total_payable NUMERIC DEFAULT 0;
    END IF;

    -- 3. Campos de Redundância (Garantir que todos os nomes comuns existam para evitar erros de código legado)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='valor_sinal') THEN
        ALTER TABLE public.appointments ADD COLUMN valor_sinal NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='total_value') THEN
        ALTER TABLE public.appointments ADD COLUMN total_value NUMERIC DEFAULT 0;
    END IF;

END $$;

-- 4. Migração de dados legados (Backfill)
UPDATE public.appointments 
SET payment_status = 'pago' 
WHERE status = 'concluido' AND payment_status = 'pendente';

UPDATE public.appointments 
SET total_payable = total_price 
WHERE (total_payable IS NULL OR total_payable = 0) AND total_price > 0;
