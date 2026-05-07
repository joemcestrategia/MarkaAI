-- 161_shop_clients_self_read_rls.sql
-- Problema: clientes comuns não tinham nenhuma política de leitura na shop_clients.
-- A política existente (130) só permite acesso a donos/funcionários da loja.
-- Isso fazia _shopClientData = null no checkout, bypassando blocked_classifications
-- e fazendo o usuário parecer "novo cliente" mesmo com classificação definida.

-- Adiciona política de SELECT para que cada usuário leia o próprio registro.
CREATE POLICY "Users can read their own shop_clients record"
    ON public.shop_clients
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());
