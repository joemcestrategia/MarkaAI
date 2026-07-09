import { Client } from "https://deno.land/x/postgres@v0.17.0/mod.ts";
import { load } from "https://deno.land/std@0.208.0/dotenv/mod.ts"

const env = await load({ envPath: "./scripts/tests/.env" })
// Pega a URL do banco (sem usar a API do Supabase que não aceita raw SQL)
const DB_URL = env["DATABASE_URL"] || Deno.env.get("DATABASE_URL")

async function run() {
  const client = new Client(DB_URL);
  await client.connect();
  console.log("Connected to DB");

  const sql = `
    DO $$ 
    BEGIN 
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='mp_processed_payments' AND column_name='orphan_reason') THEN
            ALTER TABLE public.mp_processed_payments ADD COLUMN orphan_reason text;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='mp_processed_payments' AND column_name='reconciliation_status') THEN
            ALTER TABLE public.mp_processed_payments ADD COLUMN reconciliation_status text;
        END IF;
    END $$;

    SELECT cron.schedule(
      'detect-orphan-payments-cron',
      '*/15 * * * *',
      $$
        SELECT net.http_post(
          url:='https://uhccgcojwqvkfyzrmebv.supabase.co/functions/v1/detectOrphanPayments',
          headers:='{"Content-Type": "application/json", "Authorization": "Bearer ' || current_setting('app.settings.service_role_key', true) || '"}'::jsonb,
          body:='{}'::jsonb
        ) as request_id;
      $$
    );
  `;

  try {
    await client.queryArray(sql);
    console.log("Migration aplicada com sucesso via PG driver");
  } catch (e) {
    console.error("Erro ao aplicar migration:", e);
  } finally {
    await client.end();
  }
}

run()
