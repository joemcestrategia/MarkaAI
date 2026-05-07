-- ============================================================================
-- 168: Enforce work_days validation on appointments (BEFORE INSERT / UPDATE)
--
-- fix: bloquear dias sem equipe ativa para qualquer estabelecimento
--
-- Lógica central:
--   O dia da semana do horário solicitado deve estar presente no work_days do
--   profissional atribuído. Se work_days for NULL ou vazio, rejeitar.
--   Profissional não atribuído (professional_id IS NULL) é permitido — sem
--   restrição de dias.
--
-- Dias da semana — padrão Dart/Flutter (mesmo usado no app e nas Edge Functions):
--   1 = Segunda | 2 = Terça | 3 = Quarta | 4 = Quinta
--   5 = Sexta   | 6 = Sábado | 7 = Domingo
-- PostgreSQL EXTRACT(DOW): 0 = Domingo, 1 = Segunda … 6 = Sábado
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_appointment_work_day_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_work_days    JSONB;
    v_dart_weekday INT;
BEGIN
    -- Sem profissional atribuído: sem restrição de dias
    IF NEW.professional_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Busca work_days do profissional
    SELECT e.work_days INTO v_work_days
    FROM public.employees e
    WHERE e.id = NEW.professional_id;

    -- Profissional não encontrado: deixa passar (referência órfã —
    -- outra constraint trata a integridade referencial)
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    -- work_days NULL ou array vazio → profissional sem dias configurados → rejeitar
    IF v_work_days IS NULL
       OR jsonb_typeof(v_work_days) != 'array'
       OR jsonb_array_length(v_work_days) = 0
    THEN
        RAISE EXCEPTION
            'Agendamento bloqueado: o profissional não possui dias de trabalho configurados. '
            'Configure os dias no painel do estabelecimento antes de aceitar agendamentos.';
    END IF;

    -- Converte DOW para padrão Dart (1=Seg … 6=Sáb, 7=Dom)
    -- scheduled_at é armazenado como UTC; usamos UTC para manter
    -- consistência com as Edge Functions (que também operam em UTC).
    v_dart_weekday := CASE EXTRACT(DOW FROM NEW.scheduled_at)::INT
        WHEN 0 THEN 7   -- Domingo
        ELSE EXTRACT(DOW FROM NEW.scheduled_at)::INT
    END;

    -- Valida se o dia está na lista de dias de trabalho
    IF NOT (v_work_days @> to_jsonb(v_dart_weekday)) THEN
        RAISE EXCEPTION
            'Agendamento bloqueado: o profissional não trabalha neste dia da semana '
            '(dia %, work_days configurados: %).',
            v_dart_weekday, v_work_days;
    END IF;

    RETURN NEW;
END;
$$;

-- Trigger dispara ANTES de INSERT e de UPDATE nos campos que afetam o dia/profissional.
-- UPDATEs de status, payment_id, reminder_* etc. NÃO disparam este trigger.
DROP TRIGGER IF EXISTS tr_check_appointment_work_day ON public.appointments;
CREATE TRIGGER tr_check_appointment_work_day
BEFORE INSERT OR UPDATE OF scheduled_at, professional_id
ON public.appointments
FOR EACH ROW
EXECUTE FUNCTION public.check_appointment_work_day_fn();
