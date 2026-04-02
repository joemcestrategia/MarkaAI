-- 129_add_client_photo_and_email_to_appointments.sql
-- Adiciona campos de contato e foto do cliente ao registro de agendamento

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='client_photo') THEN
        ALTER TABLE public.appointments ADD COLUMN client_photo TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='client_email') THEN
        ALTER TABLE public.appointments ADD COLUMN client_email TEXT;
    END IF;
END $$;
