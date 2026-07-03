-- 116_enforce_plan_limits.sql
-- Reforça os limites de negócio (profissionais e fotos) diretamente no banco de dados

-- 1. Função para validar limite de profissionais
CREATE OR REPLACE FUNCTION public.check_employee_limit_fn()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_id TEXT;
    v_is_trial BOOLEAN;
    v_limit INTEGER;
    v_count INTEGER;
BEGIN
    -- Busca o plano e status de trial da loja
    SELECT plan_id, trial_active INTO v_plan_id, v_is_trial 
    FROM public.shops 
    WHERE id = NEW.shop_id;
    
    -- Fallback para tabela de usuários se a loja não tiver dados de plano (configuração inicial)
    IF v_plan_id IS NULL THEN
        SELECT plano INTO v_plan_id FROM public.users WHERE shop_id = NEW.shop_id AND tipo = 'dono' LIMIT 1;
    END IF;

    -- Lógica de Trial: Libera o plano PRO
    IF v_is_trial = true THEN
        v_plan_id := 'pro';
    END IF;

    -- Normalização e Definição de Limites
    v_plan_id := COALESCE(LOWER(v_plan_id), 'free');
    
    IF v_plan_id = 'pro' THEN v_limit := 3;
    ELSIF v_plan_id = 'plus' THEN v_limit := 2;
    ELSIF v_plan_id = 'starter' THEN v_limit := 1;
    ELSE v_limit := 1; -- free
    END IF;

    -- Conta quantos funcionários a loja já possui
    SELECT count(*) INTO v_count FROM public.employees WHERE shop_id = NEW.shop_id;

    IF v_count >= v_limit THEN
        RAISE EXCEPTION 'Limite de profissionais atingido para o plano % (Máx: %)', v_plan_id, v_limit;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Gatilho para funcionários (Sempre antes da inserção)
DROP TRIGGER IF EXISTS tr_check_employee_limit ON public.employees;
CREATE TRIGGER tr_check_employee_limit
BEFORE INSERT ON public.employees
FOR EACH ROW
EXECUTE FUNCTION public.check_employee_limit_fn();

-- 3. Função para validar limite de fotos por serviço
CREATE OR REPLACE FUNCTION public.check_service_photos_limit_fn()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_id TEXT;
    v_is_trial BOOLEAN;
    v_limit INTEGER;
    v_photo_count INTEGER;
BEGIN
    SELECT plan_id, trial_active INTO v_plan_id, v_is_trial 
    FROM public.shops 
    WHERE id = NEW.shop_id;
    
    IF v_is_trial = true THEN
        v_plan_id := 'pro';
    END IF;

    v_plan_id := COALESCE(LOWER(v_plan_id), 'free');
    
    -- Limites de fotos conforme o plano (Alinhado com plan_features.dart)
    IF v_plan_id = 'pro' THEN v_limit := 10;
    ELSIF v_plan_id = 'plus' THEN v_limit := 5;
    ELSIF v_plan_id = 'starter' THEN v_limit := 3;
    ELSE v_limit := 1; -- free
    END IF;

    -- Verifica a quantidade de fotos no array
    v_photo_count := array_length(NEW.photos_urls, 1);
    
    IF v_photo_count > v_limit THEN
        RAISE EXCEPTION 'O plano % permite no máximo % fotos por serviço.', v_plan_id, v_limit;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Gatilho para serviços (Inserção e Atualização de Fotos)
DROP TRIGGER IF EXISTS tr_check_service_photos_limit ON public.services;
CREATE TRIGGER tr_check_service_photos_limit
BEFORE INSERT OR UPDATE OF photos_urls ON public.services
FOR EACH ROW
WHEN (NEW.photos_urls IS NOT NULL)
EXECUTE FUNCTION public.check_service_photos_limit_fn();
