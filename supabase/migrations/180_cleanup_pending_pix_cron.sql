-- Migration 180: Limpeza automática de agendamentos pendente_pix abandonados
--
-- A cada 5 minutos, marca como 'cancelado' agendamentos em status 'pendente_pix'
-- que foram criados há mais de 20 minutos. Isso libera o slot para outros clientes
-- e evita que reservas órfãs bloqueiem horários indefinidamente.
--
-- IMPORTANTE: Executar manualmente no SQL Editor do Supabase.

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Função de limpeza idempotente
CREATE OR REPLACE FUNCTION public.cleanup_expired_pending_pix()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  affected INT;
BEGIN
  UPDATE public.appointments
     SET status = 'cancelado',
         updated_at = NOW()
   WHERE status = 'pendente_pix'
     AND created_at < NOW() - INTERVAL '20 minutes';

  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected;
END;
$$;

COMMENT ON FUNCTION public.cleanup_expired_pending_pix() IS
  'Cancela agendamentos pendente_pix abandonados (> 20 min). Acionado por pg_cron.';

-- Remove job antigo se existir (migration idempotente)
DO $$
BEGIN
  PERFORM cron.unschedule('cleanup-expired-pending-pix');
EXCEPTION WHEN OTHERS THEN
  -- job não existia, ignora
  NULL;
END $$;

-- Agendar a cada 5 minutos
SELECT cron.schedule(
  'cleanup-expired-pending-pix',
  '*/5 * * * *',
  $$SELECT public.cleanup_expired_pending_pix();$$
);
