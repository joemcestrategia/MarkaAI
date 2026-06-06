-- Migration 179: Anti Double-Booking via Trigger com Bypass
--
-- ESTRATÉGIA: Trigger BEFORE INSERT/UPDATE em vez de EXCLUDE constraint.
-- Motivo: o dono da loja precisa poder sobrepor agendamentos manualmente
-- (após confirmação na UI), e existem agendamentos sobrepostos legítimos
-- em produção que não devem ser tocados.
--
-- COMPORTAMENTO:
--  - Por padrão (bypass_overlap_check=FALSE), bloqueia novos INSERTs/UPDATEs
--    que se sobreponham a agendamentos ativos do mesmo profissional.
--  - Erro Postgres ERRCODE 23P01 (exclusion_violation) — compatível com o
--    tratamento de erro já implementado no app.
--  - Se bypass_overlap_check=TRUE no NOVO registro, a verificação é pulada
--    (dono confirmou sobreposição na UI).
--  - Dados pré-existentes NÃO são alterados nem validados retroativamente.
--
-- Status considerados ATIVOS (reservam o slot):
--   agendado, confirmado, pendente, pendente_verificacao,
--   pendente_pix, pre_reserva
-- Status considerados INATIVOS:
--   cancelado, rejeitado, recusado, excluido
--
-- IMPORTANTE: Executar manualmente no SQL Editor do Supabase.

-- =============================================================
-- 1) Coluna de bypass (default FALSE — fluxo cliente seguro)
-- =============================================================
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS bypass_overlap_check BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.appointments.bypass_overlap_check IS
  'TRUE quando o dono confirmou sobreposição manual na UI. NUNCA deve ser TRUE em INSERT vindo do checkout do cliente.';

-- =============================================================
-- 2) Função wrapper IMMUTABLE (usada também por queries futuras)
-- =============================================================
CREATE OR REPLACE FUNCTION public.appointment_time_range(
  p_scheduled_at TIMESTAMPTZ,
  p_duration_min INTEGER
)
RETURNS TSTZRANGE
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT tstzrange(
    p_scheduled_at,
    p_scheduled_at + (COALESCE(p_duration_min, 30) || ' minutes')::INTERVAL,
    '[)'
  );
$$;

COMMENT ON FUNCTION public.appointment_time_range(TIMESTAMPTZ, INTEGER) IS
  'Calcula intervalo [início, fim) de um agendamento. IMMUTABLE.';

-- =============================================================
-- 3) Garante remoção da constraint EXCLUDE antiga (se existir)
-- =============================================================
ALTER TABLE public.appointments
  DROP CONSTRAINT IF EXISTS appointments_no_overlap;

-- =============================================================
-- 4) Função de verificação (trigger)
-- =============================================================
CREATE OR REPLACE FUNCTION public.check_appointment_overlap()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_conflict_id TEXT;
  v_inactive_statuses TEXT[] := ARRAY['cancelado','rejeitado','recusado','excluido'];
BEGIN
  -- (a) Bypass explícito (dono confirmou na UI)
  IF COALESCE(NEW.bypass_overlap_check, FALSE) = TRUE THEN
    RETURN NEW;
  END IF;

  -- (b) Se o NOVO registro já é inativo, não precisa checar
  IF NEW.status = ANY (v_inactive_statuses) THEN
    RETURN NEW;
  END IF;

  -- (c) Campos críticos ausentes — deixar passar (outras constraints lidam)
  IF NEW.professional_id IS NULL OR NEW.scheduled_at IS NULL THEN
    RETURN NEW;
  END IF;

  -- (d) Em UPDATE: se os campos de tempo não mudaram E o registro JÁ ERA
  -- ativo antes, o slot já estava reservado (verificado em INSERT/UPDATE
  -- anterior). Pular para não rejeitar transições legítimas como
  -- pre_reserva → pendente_pix → agendado, mudança de paid_amount, etc.
  IF TG_OP = 'UPDATE' THEN
    IF NEW.professional_id IS NOT DISTINCT FROM OLD.professional_id
       AND NEW.scheduled_at IS NOT DISTINCT FROM OLD.scheduled_at
       AND COALESCE(NEW.duration_min, 30) = COALESCE(OLD.duration_min, 30)
       AND NOT (OLD.status = ANY (v_inactive_statuses)) THEN
      RETURN NEW;
    END IF;
  END IF;

  -- (e) Busca conflito com outro agendamento ativo
  SELECT a.id
    INTO v_conflict_id
    FROM public.appointments a
   WHERE a.professional_id = NEW.professional_id
     AND a.id IS DISTINCT FROM NEW.id
     AND NOT (a.status = ANY (v_inactive_statuses))
     AND a.scheduled_at IS NOT NULL
     AND public.appointment_time_range(a.scheduled_at, a.duration_min)
         && public.appointment_time_range(NEW.scheduled_at, NEW.duration_min)
   LIMIT 1;

  IF v_conflict_id IS NOT NULL THEN
    RAISE EXCEPTION 'appointments_no_overlap: conflito com agendamento %', v_conflict_id
      USING ERRCODE = '23P01',
            HINT = 'Para sobrepor manualmente, defina bypass_overlap_check=TRUE no INSERT/UPDATE.';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.check_appointment_overlap() IS
  'Bloqueia sobreposições de agendamentos ativos. Aceita bypass via flag bypass_overlap_check.';

-- =============================================================
-- 5) Trigger BEFORE INSERT OR UPDATE
-- =============================================================
DROP TRIGGER IF EXISTS appointments_check_overlap ON public.appointments;

CREATE TRIGGER appointments_check_overlap
BEFORE INSERT OR UPDATE OF
  scheduled_at, duration_min, professional_id, status, bypass_overlap_check
ON public.appointments
FOR EACH ROW
EXECUTE FUNCTION public.check_appointment_overlap();

COMMENT ON TRIGGER appointments_check_overlap ON public.appointments IS
  'Anti double-booking. Aceita bypass via coluna bypass_overlap_check.';
