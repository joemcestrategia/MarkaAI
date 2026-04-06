-- 138_fix_shop_clients_fk.sql
-- Fix 1: Recreate shop_clients.user_id FK to reference auth.users(id) instead
--         of public.users(id). The FK against public.users blocks saving tags
--         for visitors who don't have a public profile yet.
--
-- Fix 2: Safer profile backfill — uses only columns guaranteed to exist
--         (id, name, email) and wraps in exception handler.

-- ══════════════════════════════════════════════════════════════
-- 1. Fix FK constraint on shop_clients.user_id
-- ══════════════════════════════════════════════════════════════
ALTER TABLE public.shop_clients
    DROP CONSTRAINT IF EXISTS shop_clients_user_id_fkey;

ALTER TABLE public.shop_clients
    ADD CONSTRAINT shop_clients_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ══════════════════════════════════════════════════════════════
-- 2. Backfill missing public.users profiles (safe version)
--    Uses only the 3 core columns that are guaranteed to exist.
--    Additional columns (phone, city, etc.) will populate naturally
--    when the user next triggers the handle_new_user trigger or
--    completes their onboarding.
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
    );
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Backfill error (some rows may have been skipped): %', SQLERRM;
END $$;
