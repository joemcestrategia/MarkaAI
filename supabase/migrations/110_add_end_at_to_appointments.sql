-- 110_add_end_at_to_appointments.sql
-- Adiciona coluna end_at para armazenar o horário de término do agendamento

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='end_at') THEN
        ALTER TABLE public.appointments ADD COLUMN end_at TIMESTAMPTZ;
    END IF;
END $$;

-- Preenche end_at para agendamentos existentes que tenham scheduled_at e duration_min
UPDATE public.appointments
SET end_at = scheduled_at + (duration_min || ' minutes')::interval
WHERE end_at IS NULL
  AND scheduled_at IS NOT NULL
  AND duration_min IS NOT NULL
  AND duration_min > 0;
