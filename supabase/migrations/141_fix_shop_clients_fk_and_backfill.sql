-- 141_fix_shop_clients_fk_and_backfill.sql
-- Consolidates fixes from 138 + 137:
-- 1. FK shop_clients.user_id → auth.users(id)  (não public.users)
--    Resolve: "insert or update on table shop_clients violates foreign key
--    constraint shop_clients_user_id_fkey, Key is not present in table users."
-- 2. Backfill public.users para auth.users sem perfil.

-- ══════════════════════════════════════════════════════════════
-- 1. Remover FK de user_id (shop_clients é metadado de tags;
--    client_id pode ser UUID de agendamento manual não presente
--    em auth.users, causando violação 23503)
-- ══════════════════════════════════════════════════════════════
ALTER TABLE public.shop_clients
    DROP CONSTRAINT IF EXISTS shop_clients_user_id_fkey;

-- ══════════════════════════════════════════════════════════════
-- 2. Backfill perfis ausentes em public.users
-- ══════════════════════════════════════════════════════════════
DO $$
BEGIN
    INSERT INTO public.users (id, name, email)
    SELECT
        au.id,
        COALESCE(
            NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''),
            NULLIF(TRIM(au.raw_user_meta_data->>'full_name'), ''),
            NULLIF(TRIM(au.raw_user_meta_data->>'display_name'), ''),
            split_part(au.email, '@', 1)
        ) AS name,
        au.email
    FROM auth.users au
    WHERE NOT EXISTS (
        SELECT 1 FROM public.users pu WHERE pu.id = au.id
    )
    ON CONFLICT (id) DO NOTHING;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Backfill parcial (algumas linhas ignoradas): %', SQLERRM;
END $$;
