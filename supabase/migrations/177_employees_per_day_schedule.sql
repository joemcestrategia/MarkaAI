-- ============================================================================
-- 177_employees_per_day_schedule.sql
--
-- Adiciona configuração de jornada POR DIA da semana, com pausa opcional.
--
-- Formato de public.employees.work_schedule (JSONB):
--   {
--     "1": { "enabled": true,  "start": "08:00", "end": "18:00",
--            "break": { "start": "12:00", "end": "13:00" } },
--     "2": { "enabled": true,  "start": "09:00", "end": "19:00", "break": null },
--     ...
--     "7": { "enabled": false }
--   }
-- Chaves 1..7 = padrão Dart (1=Seg ... 7=Dom).
--
-- Estratégia: aditiva. As colunas legadas (work_days, work_start, work_end,
-- start_time, end_time) seguem existindo. Quando work_schedule é INSERT/UPDATE,
-- um trigger BEFORE recalcula automaticamente:
--   - work_days  = lista de dias com enabled=true
--   - work_start = MIN(start) entre dias habilitados
--   - work_end   = MAX(end)   entre dias habilitados
-- Isso preserva:
--   - Trigger 168 (validação work_days em appointments) sem alterações.
--   - Builds antigos do app que ainda leem work_start/work_end agregados.
-- ============================================================================

-- 1. Colunas necessárias.
--    Em alguns ambientes só existem start_time/end_time (sem work_start/work_end).
--    Adicionamos as legadas IF NOT EXISTS para que o restante da migration e o
--    trigger possam atribuí-las uniformemente.
ALTER TABLE public.employees
    ADD COLUMN IF NOT EXISTS work_schedule JSONB,
    ADD COLUMN IF NOT EXISTS work_start    TEXT,
    ADD COLUMN IF NOT EXISTS work_end      TEXT;

-- 1b. Seed inicial das colunas legadas a partir de start_time/end_time
--     quando estiverem vazias. Mantém compat com builds que leem work_start/work_end.
UPDATE public.employees
SET work_start = COALESCE(NULLIF(work_start, ''), NULLIF(start_time, ''), '08:00')
WHERE work_start IS NULL OR work_start = '';

UPDATE public.employees
SET work_end = COALESCE(NULLIF(work_end, ''), NULLIF(end_time, ''), '18:00')
WHERE work_end IS NULL OR work_end = '';

-- 2. Backfill: monta work_schedule a partir das colunas legadas existentes.
--    Apenas onde ainda está NULL.
UPDATE public.employees e
SET work_schedule = (
    SELECT jsonb_object_agg(d::text, day_obj)
    FROM (
        SELECT
            d,
            CASE
                WHEN COALESCE(e.work_days, '[]'::jsonb) @> to_jsonb(d) THEN
                    jsonb_build_object(
                        'enabled', true,
                        'start',   COALESCE(NULLIF(e.work_start, ''), NULLIF(e.start_time, ''), '08:00'),
                        'end',     COALESCE(NULLIF(e.work_end,   ''), NULLIF(e.end_time,   ''), '18:00'),
                        'break',   NULL::jsonb
                    )
                ELSE
                    jsonb_build_object('enabled', false)
            END AS day_obj
        FROM generate_series(1, 7) AS d
    ) s
)
WHERE e.work_schedule IS NULL;

-- 3. Função de sincronização: deriva colunas legadas a partir de work_schedule.
CREATE OR REPLACE FUNCTION public.employees_sync_legacy_schedule_fn()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_days    JSONB := '[]'::jsonb;
    v_start   TEXT  := NULL;
    v_end     TEXT  := NULL;
    v_d       INT;
    v_day     JSONB;
    v_s       TEXT;
    v_e       TEXT;
BEGIN
    -- Só roda se work_schedule realmente mudou (ou é INSERT)
    IF TG_OP = 'UPDATE' AND NEW.work_schedule IS NOT DISTINCT FROM OLD.work_schedule THEN
        RETURN NEW;
    END IF;

    IF NEW.work_schedule IS NULL OR jsonb_typeof(NEW.work_schedule) <> 'object' THEN
        RETURN NEW;
    END IF;

    FOR v_d IN 1..7 LOOP
        v_day := NEW.work_schedule -> v_d::text;
        IF v_day IS NULL THEN CONTINUE; END IF;
        IF COALESCE((v_day ->> 'enabled')::boolean, false) THEN
            v_days := v_days || to_jsonb(v_d);
            v_s := NULLIF(v_day ->> 'start', '');
            v_e := NULLIF(v_day ->> 'end',   '');
            IF v_s IS NOT NULL THEN
                IF v_start IS NULL OR v_s < v_start THEN v_start := v_s; END IF;
            END IF;
            IF v_e IS NOT NULL THEN
                IF v_end IS NULL OR v_e > v_end THEN v_end := v_e; END IF;
            END IF;
        END IF;
    END LOOP;

    NEW.work_days  := v_days;
    -- Mantém work_start/work_end e os legados start_time/end_time alinhados.
    -- Só sobrescreve quando temos pelo menos um dia habilitado, para não
    -- zerar dados de profissionais com work_schedule vazio acidental.
    IF v_start IS NOT NULL THEN NEW.work_start := v_start; NEW.start_time := v_start; END IF;
    IF v_end   IS NOT NULL THEN NEW.work_end   := v_end;   NEW.end_time   := v_end;   END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_employees_sync_legacy_schedule ON public.employees;
CREATE TRIGGER tr_employees_sync_legacy_schedule
BEFORE INSERT OR UPDATE OF work_schedule
ON public.employees
FOR EACH ROW
EXECUTE FUNCTION public.employees_sync_legacy_schedule_fn();

-- 4. Comentários para o time
COMMENT ON COLUMN public.employees.work_schedule IS
'Jornada por dia da semana (1=Seg..7=Dom). Cada dia: {enabled, start, end, break:{start,end}|null}. Fonte de verdade; colunas legadas work_days/work_start/work_end/start_time/end_time são derivadas via trigger.';
