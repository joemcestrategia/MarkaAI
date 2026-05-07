import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const supabaseUrl = 'https://uhccgcojwqvkfyzrmebv.supabase.co'
// Usa a anon key apenas para ler, se o RLS permitir. 
// Mas a policy é `service_role` apenas.
// Vamos usar a service_key extraida da function
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Mzk2NjA0OCwiZXhwIjoyMDg5NTQyMDQ4fQ.aT38wj3fJkZSJFa7Ke7WqUSMPCy-zS4Q25kXPLtXwik'

const supabase = createClient(supabaseUrl, supabaseKey)

async function test() {
  const { data, error } = await supabase.from('whatsapp_qr_codes').select('*')
  console.log("QR Codes no banco:", data)
  console.log("Erro (se houver):", error)
}
test()
