-- 106_fix_categories_id_default.sql
-- Garante que a coluna ID da tabela categorias tenha um valor padrão automático

DO $$ 
DECLARE 
    col_type text;
BEGIN 
    -- 1. Descobrir o tipo da coluna id
    SELECT data_type INTO col_type 
    FROM information_schema.columns 
    WHERE table_name = 'categories' AND column_name = 'id';

    -- 2. Aplicar o default correto baseado no tipo
    IF col_type = 'uuid' THEN
        ALTER TABLE public.categories ALTER COLUMN id SET DEFAULT gen_random_uuid();
    ELSIF col_type = 'text' THEN
        ALTER TABLE public.categories ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
    END IF;
END $$;
