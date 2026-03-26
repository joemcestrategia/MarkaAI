-- 114_birthday_discount_trigger.sql
-- Automatiza o registro e bloqueio do desconto de aniversário após agendamento

-- 1. Função que processa o uso do desconto de aniversário
CREATE OR REPLACE FUNCTION public.handle_birthday_discount_usage_fn()
RETURNS TRIGGER AS $$
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
        WHERE id = NEW.client_id;

        -- 1. Trava Global no Usuário (Impede uso em qualquer loja)
        UPDATE public.users 
        SET birthday_locked = true, 
            last_birthday_discount_year = v_year
        WHERE id = NEW.client_id;

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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Gatilho disparado após a inserção (ou atualização para aplicar o desconto)
DROP TRIGGER IF EXISTS tr_on_appointment_birthday_discount ON public.appointments;
CREATE TRIGGER tr_on_appointment_birthday_discount
AFTER INSERT OR UPDATE OF birthday_discount_applied ON public.appointments
FOR EACH ROW
WHEN (NEW.birthday_discount_applied = true)
EXECUTE FUNCTION public.handle_birthday_discount_usage_fn();
