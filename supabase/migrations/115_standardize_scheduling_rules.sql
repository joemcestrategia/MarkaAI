-- 115_standardize_scheduling_rules.sql
-- Padronização definitiva das colunas de expediente e regras de negócio para Inglês (snake_case)

-- 1. Padronização na tabela public.employees
DO $$ 
BEGIN 
    -- horario_inicio -> work_start
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='employees' AND column_name='horario_inicio') THEN
        ALTER TABLE public.employees RENAME COLUMN horario_inicio TO work_start;
    END IF;

    -- horario_fim -> work_end
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='employees' AND column_name='horario_fim') THEN
        ALTER TABLE public.employees RENAME COLUMN horario_fim TO work_end;
    END IF;

    -- dias_trabalho -> work_days
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='employees' AND column_name='dias_trabalho') THEN
        ALTER TABLE public.employees RENAME COLUMN dias_trabalho TO work_days;
    END IF;

    -- servicos_habilidade -> services_ids
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='employees' AND column_name='servicos_habilidade') THEN
        ALTER TABLE public.employees RENAME COLUMN servicos_habilidade TO services_ids;
    END IF;

    -- Garantir que work_days e services_ids sejam JSONB ou Arrays (normalização)
    -- Se forem strings, convertemos para JSONB
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='employees' AND column_name='work_days' AND data_type != 'jsonb') THEN
        ALTER TABLE public.employees ALTER COLUMN work_days TYPE JSONB USING to_jsonb(work_days);
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='employees' AND column_name='services_ids' AND data_type != 'jsonb') THEN
        ALTER TABLE public.employees ALTER COLUMN services_ids TYPE JSONB USING to_jsonb(services_ids);
    END IF;
END $$;

-- 2. Garantir que a tabela public.appointments tenha duration_min sempre preenchido
UPDATE public.appointments 
SET duration_min = 30 
WHERE duration_min IS NULL;

-- 3. Adicionar colunas de suporte se faltarem no shops (algumas extensões de configuração)
DO $$ 
BEGIN 
    -- feriados_configurados
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shops' AND column_name='configured_holidays') THEN
        ALTER TABLE public.shops ADD COLUMN configured_holidays JSONB DEFAULT '{}'::jsonb;
    END IF;
END $$;
