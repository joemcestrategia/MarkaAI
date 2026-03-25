-- 103_standardize_employees.sql
-- Padronização da tabela employees

DO $$ 
BEGIN 
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='employees' AND column_name='nome') THEN
        ALTER TABLE public.employees RENAME COLUMN nome TO name;
    END IF;
END $$;
