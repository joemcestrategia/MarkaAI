-- 07_enable_realtime_all_tables.sql
-- Habilita o Realtime para as tabelas principais do sistema Markaai de forma robusta

-- 1. Garante que a publicação 'supabase_realtime' existe
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;

-- 2. Habilita realtime para cada tabela individualmente, ignorando erros se já estiver habilitado
DO $$
DECLARE
    table_name_var text;
    tables_to_add text[] := ARRAY['services', 'categories', 'employees', 'appointments', 'financial_transactions', 'coupons'];
BEGIN
    FOREACH table_name_var IN ARRAY tables_to_add
    LOOP
        BEGIN
            EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', table_name_var);
        EXCEPTION
            WHEN duplicate_object THEN
                NULL; -- Ignora se a tabela já estiver na publicação
            WHEN others THEN
                RAISE NOTICE 'Erro ao adicionar tabela %: %', table_name_var, SQLERRM;
        END;
    END LOOP;
END $$;
