-- 110_enable_replica_identity_full.sql
-- Habilita REPLICA IDENTITY FULL nas tabelas que usam .stream() no Flutter
-- Sem isso, o Supabase Realtime não emite UPDATE/DELETE events corretamente

ALTER TABLE public.services REPLICA IDENTITY FULL;
ALTER TABLE public.employees REPLICA IDENTITY FULL;
ALTER TABLE public.categories REPLICA IDENTITY FULL;
ALTER TABLE public.appointments REPLICA IDENTITY FULL;
ALTER TABLE public.financial_transactions REPLICA IDENTITY FULL;
