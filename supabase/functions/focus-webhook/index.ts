import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'

// Webhook payload from Focus NFe:
// {
//   "cnpj_prestador": "12345678000100",
//   "ref": "ID_DO_APPOINTMENT",
//   "status": "autorizado" | "erro_autorizacao" | "cancelado",
//   "numero": "123",
//   "codigo_verificacao": "A1B2C3D4",
//   "url": "https://...",
//   "caminho_xml_nota_fiscal": "...",
//   "erros": [{ "codigo": "", "mensagem": "" }]
// }

serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 })
  }

  const supabase = createSupabaseAdminClient()

  try {
    const payload = await req.json()
    console.log('[focus-webhook] Recebido payload:', payload)

    const ref = payload.ref
    if (!ref) {
      return new Response('Sem_referencia', { status: 400 })
    }

    // Buscar a emissão associada ao appointment (ref == appointment_id)
    const { data: emissao } = await supabase
      .from('nfse_emissoes')
      .select('id, status')
      .eq('appointment_id', ref)
      // Evita mexer se já foi arquivada, mas atualiza se era processando, pendente, ou atualizando notas pra cancelada.
      .maybeSingle()

    if (!emissao) {
      console.log(`[focus-webhook] Referência ${ref} não encontrada no banco.`)
      return new Response('Nao_encontrado', { status: 404 })
    }

    const { status, numero, codigo_verificacao, erros } = payload
    let updateData: Record<string, any> = {}

    if (status === 'autorizado') {
      updateData = {
        status: 'autorizada',
        numero_nfse: numero ? String(numero) : null,
        codigo_verificacao: codigo_verificacao || null,
        // chave_acesso pode ser o proprio codigo de verificacao em muitos municipios
        chave_acesso: codigo_verificacao || String(numero || ''),
        xml_nfse: JSON.stringify(payload)
      }
    } else if (status === 'erro_autorizacao') {
      let mensagemErro = 'Erro na autorização da nota na Focus.'
      if (erros && Array.isArray(erros) && erros.length > 0) {
        mensagemErro = erros.map((e: any) => e.mensagem).join('; ')
      }
      updateData = {
        status: 'rejeitada',
        motivo_rejeicao: mensagemErro,
        xml_nfse: JSON.stringify(payload)
      }
    } else if (status === 'cancelado') {
      updateData = {
        status: 'cancelada',
        xml_nfse: JSON.stringify(payload)
      }
    } else {
      // Outros status como "processando", não precisamos alterar muito
      return new Response('Ok', { status: 200 })
    }

    const { error: updateErr } = await supabase
      .from('nfse_emissoes')
      .update(updateData)
      .eq('id', emissao.id)

    if (updateErr) {
      console.error('[focus-webhook] Erro ao atualizar emissao', emissao.id, updateErr)
      return new Response('Erro_banco', { status: 500 })
    }

    return new Response('Ok', { status: 200 })
  } catch (err) {
    console.error('❌ focus-webhook:', err)
    return new Response('Internal_error', { status: 500 })
  }
})
