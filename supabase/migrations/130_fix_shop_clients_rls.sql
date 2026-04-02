-- 130_fix_shop_clients_rls.sql
-- Corrige a política RLS de shop_clients para seguir o mesmo padrão das
-- demais tabelas (appointments, services, employees): qualquer usuário
-- cujo users.shop_id bata com o shop_id da linha pode gerenciar os dados.
-- A política anterior usava shops.owner_id = auth.uid(), bloqueando funcionários.

DROP POLICY IF EXISTS "Shop owners can manage their shop clients" ON public.shop_clients;

CREATE POLICY "Shop staff can manage their shop clients" ON public.shop_clients
    FOR ALL TO authenticated
    USING (
        shop_id IN (
            SELECT shop_id FROM public.users WHERE id = auth.uid()
        )
        OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
    )
    WITH CHECK (
        shop_id IN (
            SELECT shop_id FROM public.users WHERE id = auth.uid()
        )
        OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
    );

-- Garantir que shop_views também segue o mesmo padrão (SELECT já existia; adicionar INSERT/UPDATE/DELETE para dono/funcionário)
DROP POLICY IF EXISTS "Shop owners can see views for their shop" ON public.shop_views;

CREATE POLICY "Shop staff can see views for their shop" ON public.shop_views
    FOR SELECT TO authenticated
    USING (
        shop_id IN (
            SELECT shop_id FROM public.users WHERE id = auth.uid()
        )
        OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
    );
