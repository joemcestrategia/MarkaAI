-- Migration: 161_add_google_calendar_event_id.sql
-- Adiciona coluna para rastrear eventos criados no Google Calendar

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'appointments'
          AND column_name = 'google_calendar_event_id'
    ) THEN
        ALTER TABLE public.appointments ADD COLUMN google_calendar_event_id TEXT;
    END IF;
END $$;

-- Índice para queries de contagem de sincronizados
CREATE INDEX IF NOT EXISTS idx_appointments_gcal_event
  ON public.appointments (shop_id, google_calendar_event_id)
  WHERE google_calendar_event_id IS NOT NULL;
