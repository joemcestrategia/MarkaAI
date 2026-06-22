-- 212_fix_birthday_trigger_type.sql
-- Fix operator does not exist: uuid = text in handle_birthday_discount_usage_fn

CREATE OR REPLACE FUNCTION public.handle_birthday_discount_usage_fn()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_email TEXT;
    v_phone TEXT;
    v_year INTEGER;
BEGIN
    -- Executa apenas se o desconto de aniversário for aplicado e não for um "pre-save" incompleto
    -- (No sistema atual, agendamentos incompletos podem não ter data de agendamento final ainda)
    IF (NEW.birthday_discount_applied = true AND NEW.scheduled_at IS NOT NULL) THEN
        v_year := EXTRACT(YEAR FROM NEW.scheduled_at::TIMESTAMPTZ);
        
        -- Busca dados do usuário para registro anti-fraude
        SELECT email, phone INTO v_email, v_phone 
        FROM public.users 
        WHERE id::text = NEW.client_id;

        -- 1. Trava Global no Usuário (Impede uso em qualquer loja)
        UPDATE public.users 
        SET birthday_locked = true, 
            last_birthday_discount_year = v_year
        WHERE id::text = NEW.client_id;

        -- 2. Registro Anti-Fraude na Loja (E-mail)
        IF v_email IS NOT NULL AND v_email <> '' THEN
            INSERT INTO public.birthday_discount_registry (shop_id, identifier, year, user_id)
            VALUES (NEW.shop_id, 'email_' || v_email, v_year, NEW.client_id)
            ON CONFLICT (shop_id, identifier, year) DO NOTHING;
        END IF;

        -- 3. Registro Anti-Fraude na Loja (Telefone)
        IF v_phone IS NOT NULL AND v_phone <> '' THEN
            INSERT INTO public.birthday_discount_registry (shop_id, identifier, year, user_id)
            VALUES (NEW.shop_id, 'phone_' || v_phone, v_year, NEW.client_id)
            ON CONFLICT (shop_id, identifier, year) DO NOTHING;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;
