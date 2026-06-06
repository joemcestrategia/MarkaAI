-- 1. Add services_count column to shops table
ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS services_count INTEGER DEFAULT 0;

-- 2. Create the function to update the count
CREATE OR REPLACE FUNCTION public.update_shop_services_count()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE public.shops
        SET services_count = (SELECT COUNT(id) FROM public.services WHERE shop_id = OLD.shop_id AND (is_active IS NULL OR is_active = true))
        WHERE id = OLD.shop_id;
        RETURN OLD;
    ELSIF (TG_OP = 'UPDATE') THEN
        UPDATE public.shops
        SET services_count = (SELECT COUNT(id) FROM public.services WHERE shop_id = NEW.shop_id AND (is_active IS NULL OR is_active = true))
        WHERE id = NEW.shop_id;
        RETURN NEW;
    ELSIF (TG_OP = 'INSERT') THEN
        UPDATE public.shops
        SET services_count = (SELECT COUNT(id) FROM public.services WHERE shop_id = NEW.shop_id AND (is_active IS NULL OR is_active = true))
        WHERE id = NEW.shop_id;
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- 3. Create the trigger on the services table
DROP TRIGGER IF EXISTS trigger_update_shop_services_count ON public.services;
CREATE TRIGGER trigger_update_shop_services_count
AFTER INSERT OR UPDATE OR DELETE ON public.services
FOR EACH ROW EXECUTE FUNCTION public.update_shop_services_count();

-- 4. Initial populate for existing shops
UPDATE public.shops s
SET services_count = (
    SELECT COUNT(id) 
    FROM public.services 
    WHERE shop_id = s.id AND (is_active IS NULL OR is_active = true)
);
