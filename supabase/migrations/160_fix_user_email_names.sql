-- 160_fix_user_email_names.sql
-- Essa migration corrige um problema onde usuários sem nome (metadata 'name' vazio) 
-- recebiam o e-mail inteiro como nome no perfil (tabela users) e consequentemente
-- nos agendamentos (appointments).

-- 1. Atualizar o trigger `handle_new_user` para usar a primeira parte do email
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (
        id,
        name,
        email,
        role,
        shop_id,
        plan,
        phone,
        zip_code,
        street,
        neighborhood,
        city,
        state,
        number,
        birth_date,
        verified,
        photo_url
    )
    VALUES (
        NEW.id,
        COALESCE(
            NULLIF(TRIM(NEW.raw_user_meta_data->>'name'), ''), 
            INITCAP(SPLIT_PART(NEW.email, '@', 1))
        ),
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'role', 'cliente'),
        NULLIF(NEW.raw_user_meta_data->>'shop_id', ''),
        COALESCE(NEW.raw_user_meta_data->>'plan', 'free'),
        NEW.raw_user_meta_data->>'phone',
        NEW.raw_user_meta_data->>'zip_code',
        NEW.raw_user_meta_data->>'street',
        NEW.raw_user_meta_data->>'neighborhood',
        NEW.raw_user_meta_data->>'city',
        NEW.raw_user_meta_data->>'state',
        NEW.raw_user_meta_data->>'number',
        NULLIF(NEW.raw_user_meta_data->>'birth_date', '')::DATE,
        COALESCE((NEW.raw_user_meta_data->>'verified')::boolean, false),
        COALESCE(
            NEW.raw_user_meta_data->>'avatar_url',
            NEW.raw_user_meta_data->>'picture'
        )
    )
    ON CONFLICT (id) DO UPDATE SET
        name         = COALESCE(NULLIF(TRIM(EXCLUDED.name), ''), public.users.name, INITCAP(SPLIT_PART(EXCLUDED.email, '@', 1))),
        role         = EXCLUDED.role,
        shop_id      = EXCLUDED.shop_id,
        plan         = EXCLUDED.plan,
        phone        = EXCLUDED.phone,
        zip_code     = EXCLUDED.zip_code,
        street       = EXCLUDED.street,
        neighborhood = EXCLUDED.neighborhood,
        city         = EXCLUDED.city,
        state        = EXCLUDED.state,
        number       = EXCLUDED.number,
        birth_date   = EXCLUDED.birth_date,
        verified     = EXCLUDED.verified,
        photo_url    = COALESCE(public.users.photo_url, EXCLUDED.photo_url),
        updated_at   = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Limpar dados existentes na tabela `users`
UPDATE public.users
SET name = INITCAP(SPLIT_PART(email, '@', 1))
WHERE name LIKE '%@%';

-- 3. Limpar dados existentes na tabela `appointments`
-- Primeiro, tenta buscar do perfil correto (se lá já estiver consertado).
-- Se der null ou ainda tiver @, pega a parte antes do @ localmente.
UPDATE public.appointments
SET client_name = (
    SELECT name 
    FROM public.users u
    WHERE u.id::text = appointments.client_id
)
WHERE client_name LIKE '%@%' AND client_id IS NOT NULL;

UPDATE public.appointments
SET client_name = INITCAP(SPLIT_PART(client_name, '@', 1))
WHERE client_name LIKE '%@%';
