-- 137_enable_realtime_shop_clients.sql
-- Adiciona a tabela shop_clients no realtime do Supabase para que a dashboard de donos de estabelecimento 
-- seja atualizada em tempo real ao alterar classificações dos clientes.

BEGIN;
  DO $$
  BEGIN
      IF NOT EXISTS (
          SELECT 1
          FROM pg_publication_tables
          WHERE pubname = 'supabase_realtime'
            AND tablename = 'shop_clients'
      ) THEN
          ALTER PUBLICATION supabase_realtime ADD TABLE public.shop_clients;
      END IF;
  END
  $$;
COMMIT;
