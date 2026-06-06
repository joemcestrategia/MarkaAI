-- Migration 181: Sistema de Pré-Reserva (Lock Temporário de 5 minutos)
--
-- Cria um agendamento provisório com status='pre_reserva' que reserva o horário
-- enquanto o cliente está na tela de checkout. Após 5 minutos sem confirmação,
-- o cron remove o registro automaticamente, liberando o slot.
--
-- Características:
--  - Atomic: usa exclusion constraint de 179 — se falhar, retorna {success:false}
--  - Invisível ao dono: status='pre_reserva' deve ser filtrado nas telas de gestão
--  - Sem notificações: appointmentTriggers só dispara para status 'agendado'/'confirmado'
--  - TTL: 5 minutos (cleanup a cada 1 minuto)
--
-- IMPORTANTE: Executar no SQL Editor do Supabase APÓS as migrations 179 e 180.

-- =============================================================
-- 1) RPC: tentar_pre_reserva
-- =============================================================
CREATE OR REPLACE FUNCTION public.tentar_pre_reserva(
  p_shop_id TEXT,
  p_client_id TEXT,
  p_professional_id TEXT,
  p_service_id TEXT,
  p_scheduled_at TIMESTAMPTZ,
  p_duration_min INTEGER,
  p_client_name TEXT DEFAULT NULL,
  p_client_email TEXT DEFAULT NULL,
  p_client_phone TEXT DEFAULT NULL,
  p_professional_name TEXT DEFAULT NULL,
  p_service_name TEXT DEFAULT NULL,
  p_total_value NUMERIC DEFAULT 0
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_new_id TEXT;
  v_end_at TIMESTAMPTZ;
BEGIN
  -- Validações básicas
  IF p_shop_id IS NULL OR p_client_id IS NULL OR p_professional_id IS NULL
     OR p_scheduled_at IS NULL OR p_duration_min IS NULL OR p_duration_min <= 0 THEN
    RETURN jsonb_build_object('success', false, 'reason', 'parametros_invalidos');
  END IF;

  v_end_at := p_scheduled_at + (p_duration_min * INTERVAL '1 minute');

  -- Antes de tentar inserir, remover qualquer pre_reserva pendente do mesmo
  -- cliente para esse profissional/horário (evita duplicar locks do próprio cliente)
  DELETE FROM public.appointments
   WHERE client_id = p_client_id
     AND status = 'pre_reserva'
     AND created_at < NOW() - INTERVAL '10 seconds';

  BEGIN
    INSERT INTO public.appointments (
      shop_id, client_id, professional_id, service_id,
      scheduled_at, end_at, duration_min,
      client_name, client_email, client_phone,
      professional_name, service_name,
      total_value, total_price,
      status, payment_method, payment_status,
      created_at
    ) VALUES (
      p_shop_id, p_client_id, p_professional_id, p_service_id,
      p_scheduled_at, v_end_at, p_duration_min,
      COALESCE(p_client_name, 'Cliente'), p_client_email, p_client_phone,
      COALESCE(p_professional_name, 'Profissional'),
      COALESCE(p_service_name, 'Serviço'),
      COALESCE(p_total_value, 0), COALESCE(p_total_value, 0),
      'pre_reserva', 'pendente', 'pendente',
      NOW()
    )
    RETURNING id INTO v_new_id;

    RETURN jsonb_build_object('success', true, 'appointment_id', v_new_id);
  EXCEPTION
    WHEN exclusion_violation THEN
      RETURN jsonb_build_object('success', false, 'reason', 'horario_ocupado');
    WHEN unique_violation THEN
      RETURN jsonb_build_object('success', false, 'reason', 'horario_ocupado');
    WHEN OTHERS THEN
      RETURN jsonb_build_object('success', false, 'reason', 'erro_inesperado', 'detail', SQLERRM);
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tentar_pre_reserva(
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, INTEGER,
  TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC
) TO authenticated;

COMMENT ON FUNCTION public.tentar_pre_reserva IS
  'Cria lock temporário (pre_reserva) de 5 minutos. Retorna {success, appointment_id, reason}.';

-- =============================================================
-- 2) Cleanup de pre_reservas expiradas (5 minutos)
-- =============================================================
CREATE OR REPLACE FUNCTION public.cleanup_expired_pre_reservas()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  affected INT;
BEGIN
  DELETE FROM public.appointments
   WHERE status = 'pre_reserva'
     AND created_at < NOW() - INTERVAL '5 minutes';

  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected;
END;
$$;

COMMENT ON FUNCTION public.cleanup_expired_pre_reservas() IS
  'Remove pre_reservas expiradas (> 5 min). Acionado por pg_cron.';

-- =============================================================
-- 3) Job pg_cron: cleanup a cada 1 minuto
-- =============================================================
DO $$
BEGIN
  PERFORM cron.unschedule('cleanup-expired-pre-reservas');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

SELECT cron.schedule(
  'cleanup-expired-pre-reservas',
  '* * * * *', -- a cada minuto
  $$SELECT public.cleanup_expired_pre_reservas();$$
);

-- =============================================================
-- 4) Índice para acelerar cleanup
-- =============================================================
CREATE INDEX IF NOT EXISTS idx_appointments_pre_reserva_created
  ON public.appointments (created_at)
  WHERE status = 'pre_reserva';
