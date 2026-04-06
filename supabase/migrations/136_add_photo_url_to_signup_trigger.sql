-- 136_add_photo_url_to_signup_trigger.sql
-- Adiciona photo_url ao trigger handle_new_user para que usuários
-- que se cadastram via Google OAuth já tenham a foto salva na tabela.
-- O campo é populado a partir de raw_user_meta_data->>'avatar_url'
-- (Google OAuth) com fallback para 'picture'.

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
        COALESCE(NEW.raw_user_meta_data->>'name', NEW.email),
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
        name         = EXCLUDED.name,
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
        -- Atualiza photo_url apenas se ainda não tiver uma foto salva
        photo_url    = COALESCE(public.users.photo_url, EXCLUDED.photo_url),
        updated_at   = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
