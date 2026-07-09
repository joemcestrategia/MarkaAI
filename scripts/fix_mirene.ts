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
    paid_amount: 140,
    remaining_amount: 0,
    payment_method: "Pix",
    pago_em: "2026-06-30T13:12:01.000Z",
    updated_at: new Date().toISOString(),
    metadata: {
      payment_id: "166463096664",
      advance_payment_id: "159130895822",
      completion_payment_id: "166463096664",
      completion_payment_method: "Pix",
      completion_paid_at: "2026-06-30T13:12:01.000Z",
      valor_pago: 140,
      restante_a_pagar: 0
    }
  }

  const { data, error } = await supabase
    .from('appointments')
    .update(updatePayload)
    .eq('id', '3097b47b-f7ac-47ae-a345-6545e50fc455')
    .select()

  if (error) {
    console.error("Erro ao atualizar Mirene:", error)
  } else {
    console.log("Sucesso ao atualizar Mirene:", JSON.stringify(data, null, 2))
  }
}

run()
