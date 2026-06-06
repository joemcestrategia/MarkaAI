-- 20260604_fix_plan_limits_and_boost.sql
-- Corrige limites de plano para alinhar com subscription_service.dart
-- e adiciona colunas de boost para client_home_page

-- ════════════════════════════════════════════════════════════
-- 1. Corrigir limites de profissionais
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.check_employee_limit_fn()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_id TEXT;
    v_is_trial BOOLEAN;
    v_limit INTEGER;
    v_count INTEGER;
BEGIN
    SELECT plan_id, trial_active INTO v_plan_id, v_is_trial 
    FROM public.shops 
    WHERE id = NEW.shop_id;
    
    IF v_plan_id IS NULL THEN
        SELECT plan INTO v_plan_id FROM public.users WHERE shop_id = NEW.shop_id AND tipo = 'dono' LIMIT 1;
    END IF;

    IF v_is_trial = true THEN
        v_plan_id := 'pro';
    END IF;

    v_plan_id := COALESCE(LOWER(v_plan_id), 'free');
    
    IF v_plan_id = 'pro' THEN v_limit := 5;
    ELSIF v_plan_id = 'plus' THEN v_limit := 3;
    ELSIF v_plan_id = 'starter' OR v_plan_id = 'start' THEN v_limit := 2;
    ELSE v_limit := 1;
    END IF;

    SELECT count(*) INTO v_count FROM public.employees WHERE shop_id = NEW.shop_id;

    IF v_count >= v_limit THEN
        RAISE EXCEPTION 'Limite de profissionais atingido para o plano % (Máx: %)', v_plan_id, v_limit;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════
-- 2. Corrigir limites de fotos por serviço
-- ════════════════════════════════════════════════════════════

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
    
    IF v_plan_id = 'pro' THEN v_limit := 5;
    ELSIF v_plan_id = 'plus' THEN v_limit := 5;
    ELSIF v_plan_id = 'starter' OR v_plan_id = 'start' THEN v_limit := 3;
    ELSE v_limit := 1;
    END IF;

    v_photo_count := array_length(NEW.photos_urls, 1);
    
    IF v_photo_count > v_limit THEN
        RAISE EXCEPTION 'O plano % permite no máximo % fotos por serviço.', v_plan_id, v_limit;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════════════════════════
-- 3. Colunas de boost (client_home_page lê is_boosted e boost_expires_at)
-- ════════════════════════════════════════════════════════════

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='shops' AND column_name='boost') THEN
        ALTER TABLE public.shops ADD COLUMN boost JSONB DEFAULT '{}'::jsonb;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='shops' AND column_name='is_boosted') THEN
        ALTER TABLE public.shops ADD COLUMN is_boosted BOOLEAN DEFAULT false;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='shops' AND column_name='boost_expires_at') THEN
        ALTER TABLE public.shops ADD COLUMN boost_expires_at TIMESTAMPTZ;
    END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 4. Trigger que sincroniza boost JSONB → colunas top-level automaticamente
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.sync_boost_columns_fn()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.boost IS NOT NULL THEN
        NEW.is_boosted := (NEW.boost->>'is_active')::boolean AND 
                          (NEW.boost->>'expires_at')::timestamptz > now();
        NEW.boost_expires_at := (NEW.boost->>'expires_at')::timestamptz;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_sync_boost_columns ON public.shops;
CREATE TRIGGER tr_sync_boost_columns
BEFORE INSERT OR UPDATE OF boost ON public.shops
FOR EACH ROW
EXECUTE FUNCTION public.sync_boost_columns_fn();
