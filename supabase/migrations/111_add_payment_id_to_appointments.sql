-- 111_add_payment_id_to_appointments.sql
-- Adiciona coluna payment_id para rastreio de transações do Mercado Pago/Stripe

DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='payment_id') THEN
        ALTER TABLE public.appointments ADD COLUMN payment_id TEXT;
    END IF;
END $$;
