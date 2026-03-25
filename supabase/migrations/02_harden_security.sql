-- Security Hardening: Enable RLS and define policies for all core tables

-- 1. shops
ALTER TABLE public.shops ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Select shops" ON public.shops;
CREATE POLICY "Public Select shops" ON public.shops FOR SELECT USING (true);
DROP POLICY IF EXISTS "Owner Manage shops" ON public.shops;
CREATE POLICY "Owner Manage shops" ON public.shops FOR ALL TO authenticated 
USING (owner_id::text = auth.uid()::text OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin');

-- 2. categories (Ex-service_categories)
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Select categories" ON public.categories;
CREATE POLICY "Public Select categories" ON public.categories FOR SELECT USING (true);
DROP POLICY IF EXISTS "Admin Manage categories" ON public.categories;
CREATE POLICY "Admin Manage categories" ON public.categories FOR ALL TO authenticated 
USING ((SELECT role FROM public.users WHERE id = auth.uid()) = 'admin');

-- 3. services
ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Select services" ON public.services;
CREATE POLICY "Public Select services" ON public.services FOR SELECT USING (true);
DROP POLICY IF EXISTS "Shop Manage services" ON public.services;
CREATE POLICY "Shop Manage services" ON public.services FOR ALL TO authenticated 
USING (shop_id IN (SELECT shop_id FROM public.users WHERE id = auth.uid()) OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin');

-- 4. appointments
ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User Select own appointments" ON public.appointments;
CREATE POLICY "User Select own appointments" ON public.appointments FOR SELECT 
USING (client_id::text = auth.uid()::text); 
DROP POLICY IF EXISTS "Shop Manage appointments" ON public.appointments;
CREATE POLICY "Shop Manage appointments" ON public.appointments FOR ALL TO authenticated 
USING (shop_id IN (SELECT shop_id FROM public.users WHERE id = auth.uid()) OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin');

-- 5. products
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Select products" ON public.products;
CREATE POLICY "Public Select products" ON public.products FOR SELECT USING (true);
DROP POLICY IF EXISTS "Shop Manage products" ON public.products;
CREATE POLICY "Shop Manage products" ON public.products FOR ALL TO authenticated 
USING (shop_id IN (SELECT shop_id FROM public.users WHERE id = auth.uid()) OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin');

-- 6. employees
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Select employees" ON public.employees;
CREATE POLICY "Public Select employees" ON public.employees FOR SELECT USING (true);
DROP POLICY IF EXISTS "Shop Manage employees" ON public.employees;
CREATE POLICY "Shop Manage employees" ON public.employees FOR ALL TO authenticated 
USING (shop_id IN (SELECT shop_id FROM public.users WHERE id = auth.uid()) OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin');

-- 7. financial_transactions
ALTER TABLE public.financial_transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Shop Manage financial_transactions" ON public.financial_transactions;
CREATE POLICY "Shop Manage financial_transactions" ON public.financial_transactions FOR ALL TO authenticated 
USING (shop_id IN (SELECT shop_id FROM public.users WHERE id = auth.uid()) OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin');

-- 8. bank_accounts
ALTER TABLE public.bank_accounts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Shop Manage bank_accounts" ON public.bank_accounts;
CREATE POLICY "Shop Manage bank_accounts" ON public.bank_accounts FOR ALL TO authenticated 
USING (shop_id IN (SELECT shop_id FROM public.users WHERE id = auth.uid() AND role IN ('admin', 'dono', 'business')));

-- 9. purchases
ALTER TABLE public.purchases ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Shop Manage purchases" ON public.purchases;
CREATE POLICY "Shop Manage purchases" ON public.purchases FOR ALL TO authenticated 
USING (shop_id IN (SELECT shop_id FROM public.users WHERE id = auth.uid()) OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin');

-- 10. stock_movements
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Shop Manage stock_movements" ON public.stock_movements;
CREATE POLICY "Shop Manage stock_movements" ON public.stock_movements FOR ALL TO authenticated 
USING (shop_id IN (SELECT shop_id FROM public.users WHERE id = auth.uid()) OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin');

-- 11. plans
ALTER TABLE public.plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Select plans" ON public.plans;
CREATE POLICY "Public Select plans" ON public.plans FOR SELECT USING (true);

-- 12. webhook_logs
ALTER TABLE public.webhook_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin Select logs" ON public.webhook_logs;
CREATE POLICY "Admin Select logs" ON public.webhook_logs FOR SELECT TO authenticated 
USING ((SELECT role FROM public.users WHERE id = auth.uid()) = 'admin');

-- 13. saved_cards
ALTER TABLE public.saved_cards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "User Manage own cards" ON public.saved_cards;
CREATE POLICY "User Manage own cards" ON public.saved_cards FOR ALL TO authenticated 
USING (user_id::text = auth.uid()::text);

