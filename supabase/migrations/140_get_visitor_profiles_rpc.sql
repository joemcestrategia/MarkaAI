-- 140_get_visitor_profiles_rpc.sql
-- Creates a SECURITY DEFINER function that lets the business owner fetch
-- user profiles by a list of IDs, bypassing RLS restrictions on public.users.
-- This is the correct pattern for "read-only cross-user lookups" where the
-- caller has a legitimate business reason to see the data.

CREATE OR REPLACE FUNCTION public.get_visitor_profiles(user_ids UUID[])
RETURNS TABLE (
    id          UUID,
    name        TEXT,
    phone       TEXT,
    email       TEXT,
    photo_url   TEXT,
    birth_date  DATE,
    city        TEXT,
    state       TEXT,
    street      TEXT,
    neighborhood TEXT,
    number      TEXT,
    zip_code    TEXT,
    created_at  TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT
        u.id,
        u.name,
        u.phone,
        u.email,
        u.photo_url,
        u.birth_date,
        u.city,
        u.state,
        u.street,
        u.neighborhood,
        u.number,
        u.zip_code,
        u.created_at
    FROM public.users u
    WHERE u.id = ANY(user_ids);
$$;

-- Only authenticated users can call this function
REVOKE ALL ON FUNCTION public.get_visitor_profiles(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_visitor_profiles(UUID[]) TO authenticated;
