import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !supabaseServiceKey) {
  console.error("Please set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY env vars");
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceKey);

async function apply() {
  const sql = `ALTER TABLE public.appointments ADD COLUMN IF NOT EXISTS cancellation_note text;`;
  const { error } = await supabase.rpc('exec_sql', { sql_query: sql });
  if (error) {
    console.error("Erro ao aplicar migration:", error);
  } else {
    console.log("Coluna cancellation_note adicionada com sucesso!");
  }
}

apply();
