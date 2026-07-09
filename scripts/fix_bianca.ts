import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'
import { load } from "https://deno.land/std@0.208.0/dotenv/mod.ts"

const env = await load({ envPath: "./scripts/tests/.env" })
const SUPABASE_URL = env["SUPABASE_URL"] || Deno.env.get("SUPABASE_URL")
const SUPABASE_KEY = env["SUPABASE_SERVICE_ROLE_KEY"] || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY)

async function run() {
  const updatePayload = {
    status: "confirmado",
    payment_status: "pago",
    paid_amount: 280,
    remaining_amount: 0,
    payment_id: "166983717246",
    payment_method: "Pix",
    pago_em: "2026-07-03T13:49:58.000Z",
    updated_at: new Date().toISOString(),
    metadata: { valor_pago: 280, restante_a_pagar: 0 }
  }

  const { data, error } = await supabase
    .from('appointments')
    .update(updatePayload)
    .eq('id', 'aaa5474e-0eaf-430a-8eaf-bb80af89f4b3')
    .select()

  if (error) {
    console.error("Erro ao atualizar Bianca:", error)
  } else {
    console.log("Sucesso ao atualizar Bianca:", data)
  }
}

run()
