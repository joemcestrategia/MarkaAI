-- 137_backfill_missing_user_profiles.sql
-- Backfills public.users for all auth users who are missing a profile.
-- Root cause: the handle_new_user trigger was broken in earlier migrations,
-- so users who signed up during that period exist in auth.users but NOT in
-- public.users, causing the visitors tab to show "Cliente (Interesse)" with
-- no name, phone, or address.

INSERT INTO public.users (id, name, email, role, plan)
SELECT
    au.id,
    COALESCE(
        NULLIF(TRIM(au.raw_user_meta_data->>'name'), ''),
        NULLIF(TRIM(au.raw_user_meta_data->>'full_name'), ''),
        NULLIF(TRIM(au.raw_user_meta_data->>'display_name'), ''),
        split_part(au.email, '@', 1)
    ) AS name,
    au.email,
    COALESCE(au.raw_user_meta_data->>'role', 'cliente') AS role,
    COALESCE(au.raw_user_meta_data->>'plan', 'free') AS plan
FROM auth.users au
WHERE NOT EXISTS (
    SELECT 1 FROM public.users pu WHERE pu.id = au.id
);
