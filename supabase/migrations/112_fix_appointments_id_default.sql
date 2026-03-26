-- 112_fix_appointments_id_default.sql
-- Garante que a coluna "id" da tabela "appointments" auto-gere um UUID caso não seja enviado pelo app

DO $$ 
BEGIN
    ALTER TABLE public.appointments ALTER COLUMN id SET DEFAULT gen_random_uuid();
EXCEPTION WHEN OTHERS THEN
    -- Ignorar se já estiver definido ou ocorrer outro erro não crítico
END $$;
