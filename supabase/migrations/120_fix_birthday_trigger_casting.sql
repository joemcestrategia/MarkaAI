-- 120_fix_birthday_trigger_casting.sql
-- Corrige erro de "operator does not exist: uuid = text" no gatilho de desconto de aniversário

CREATE OR REPLACE FUNCTION public.handle_birthday_discount_usage_fn()
RETURNS TRIGGER AS $$
DECLARE
    v_email TEXT;
    v_phone TEXT;
    v_year INTEGER;
BEGIN
    -- Executa apenas se o desconto de aniversário for aplicado e não for um "pre-save" incompleto
    IF (NEW.birthday_discount_applied = true AND NEW.scheduled_at IS NOT NULL) THEN
        v_year := EXTRACT(YEAR FROM NEW.scheduled_at::TIMESTAMPTZ);
        
        -- Busca dados do usuário para registro anti-fraude (Adicionado ::uuid cast)
        SELECT email, phone INTO v_email, v_phone 
        FROM public.users 
        WHERE id = NEW.client_id::uuid;

        -- 1. Trava Global no Usuário (Impede uso em qualquer loja) (Adicionado ::uuid cast)
        UPDATE public.users 
        SET birthday_locked = true, 
            last_birthday_discount_year = v_year
        WHERE id = NEW.client_id::uuid;

        -- 2. Registro Anti-Fraude na Loja (E-mail)
        IF v_email IS NOT NULL AND v_email <> '' THEN
            -- Adicionado ::uuid cast para user_id
            INSERT INTO public.birthday_discount_registry (shop_id, identifier, year, user_id)
            VALUES (NEW.shop_id, 'email_' || v_email, v_year, NEW.client_id::uuid)
            ON CONFLICT (shop_id, identifier, year) DO NOTHING;
        END IF;

        -- 3. Registro Anti-Fraude na Loja (Telefone)
        IF v_phone IS NOT NULL AND v_phone <> '' THEN
            -- Adicionado ::uuid cast para user_id
            INSERT INTO public.birthday_discount_registry (shop_id, identifier, year, user_id)
            VALUES (NEW.shop_id, 'phone_' || v_phone, v_year, NEW.client_id::uuid)
            ON CONFLICT (shop_id, identifier, year) DO NOTHING;
        END IF;
    END IF;

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Em caso de erro (ex: cast falhar), não bloqueia o agendamento mas loga o erro
        RAISE WARNING 'Erro ao registrar uso de desconto de aniversário: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
