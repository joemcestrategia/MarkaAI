-- 211_fix_work_day_trigger_type.sql
-- Fix operator does not exist: text = uuid in check_appointment_work_day_fn

CREATE OR REPLACE FUNCTION public.check_appointment_work_day_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_work_days    JSONB;
    v_dart_weekday INT;
    v_uid          UUID := auth.uid();
BEGIN
    -- Sem profissional atribuído: sem restrição de dias
    IF NEW.professional_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Permite bypass (sobreposição) se for o dono da loja ou o próprio profissional
    IF v_uid IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM public.shops 
            WHERE id = NEW.shop_id AND owner_id = v_uid::text
        ) THEN
            RETURN NEW;
        END IF;

        IF EXISTS (
            SELECT 1 FROM public.employees
            WHERE id = NEW.professional_id AND user_id = v_uid
        ) THEN
            RETURN NEW;
        END IF;
    END IF;

    -- Busca work_days do profissional
    SELECT e.work_days INTO v_work_days
    FROM public.employees e
    WHERE e.id = NEW.professional_id;

    -- Profissional não encontrado: deixa passar
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    -- work_days NULL ou array vazio -> rejeitar
    IF v_work_days IS NULL
       OR jsonb_typeof(v_work_days) != 'array'
       OR jsonb_array_length(v_work_days) = 0
    THEN
        RAISE EXCEPTION
            'Agendamento bloqueado: o profissional não possui dias de trabalho configurados. '
            'Configure os dias no painel do estabelecimento antes de aceitar agendamentos.';
    END IF;

    -- Converte DOW para padrão Dart (1=Seg … 6=Sáb, 7=Dom)
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
