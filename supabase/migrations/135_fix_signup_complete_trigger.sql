-- 135_fix_signup_complete_trigger.sql
-- CORREÇÃO: O upsert direto do Flutter após signUp() falhava com RLS 42501
-- porque auth.uid() é NULL quando email confirmation está habilitado.
--
-- Solução: Expandir o trigger handle_new_user para inserir TODOS os campos
-- do perfil a partir do raw_user_meta_data, eliminando a necessidade do
-- upsert direto quando o usuário ainda não tem sessão ativa.
-- O Flutter só fará upsert quando houver sessão (atualização de perfil).

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
        verified
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
        COALESCE((NEW.raw_user_meta_data->>'verified')::boolean, false)
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
        updated_at   = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
