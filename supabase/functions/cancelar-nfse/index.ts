import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'
import { corsHeaders } from '../_shared/cors.ts'

const FOCUS_TOKEN = 'mX0IYhNV9zOndTCQPmjKttD6hXGPgV3z'
const FOCUS_API_URL = 'https://api.focusnfe.com.br/v2/nfse'

function digits(v: string | null | undefined): string {
  return v ? v.replace(/\D/g, '') : ''
}

function ascii(s: string): string {
  if (!s) return ''
  return s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^\x20-\x7E]/g, '')
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const supabase = createSupabaseAdminClient()

  try {
    const body = await req.json()
    const { nfse_id, motivo } = body as { nfse_id: string; motivo: string }

    if (!nfse_id || !motivo) {
      return new Response(
        JSON.stringify({ error: 'nfse_id e motivo são obrigatórios.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    if (motivo.trim().length < 15) {
      return new Response(
        JSON.stringify({ error: 'Motivo do cancelamento deve ter pelo menos 15 caracteres.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // 1. Buscar nota
    const { data: emissao, error: emissaoErr } = await supabase
      .from('nfse_emissoes')
      .select('id, status, shop_id, appointment_id, numero_nfse')
      .eq('id', nfse_id)
      .single()

    if (emissaoErr || !emissao) {
      return new Response(
        JSON.stringify({ error: 'Nota fiscal não encontrada.' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // Buscar configuração da loja para decidir o provedor
    const { data: cfg } = await supabase
      .from('nfse_config')
      .select('codigo_municipio, cnpj, inscricao_municipal, url_webservice, senha_prefeitura')
      .eq('shop_id', emissao.shop_id)
      .maybeSingle()

    if (emissao.status !== 'autorizada' && emissao.status !== 'processando') {
      return new Response(
        JSON.stringify({ error: `Não é possível cancelar uma nota com status "${emissao.status}".` }),
        { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const isItabirito = cfg?.codigo_municipio === '3131901' || (cfg?.url_webservice || '').includes('atende.net');

    if (isItabirito) {
      // ----------------------------------------------------
      // CANCELAMENTO ITABIRITO (IPM Atende.Net) via SOAP
      // ----------------------------------------------------
      if (!emissao.numero_nfse) {
        return new Response(JSON.stringify({ error: 'Nota de Itabirito não possui número salvo, impossível cancelar.' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
      
      const prestadorCnpj = digits(cfg.cnpj)
      const pass = cfg.senha_prefeitura
      const basicAuth = btoa(`${prestadorCnpj}:${pass}`)
      const codigoCancelamento = '1' // 1 - Erro na emissão, 2 - Serviço não prestado, etc.
      
      const soapEnvelope = `<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:net="net.atende">
  <soapenv:Header/>
  <soapenv:Body>
    <net:CancelarNfseEnvio>
      <net:Pedido>
        <net:InfPedidoCancelamento>
          <net:IdentificacaoNfse>
            <net:Numero>${emissao.numero_nfse}</net:Numero>
            <net:CpfCnpj><net:Cnpj>${prestadorCnpj}</net:Cnpj></net:CpfCnpj>
            <net:InscricaoMunicipal>${digits(cfg.inscricao_municipal)}</net:InscricaoMunicipal>
            <net:CodigoMunicipio>3131901</net:CodigoMunicipio>
          </net:IdentificacaoNfse>
          <net:CodigoCancelamento>1</net:CodigoCancelamento>
        </net:InfPedidoCancelamento>
      </net:Pedido>
    </net:CancelarNfseEnvio>
  </soapenv:Body>
</soapenv:Envelope>`

      const url = cfg.url_webservice || 'https://itabirito.atende.net/?pg=services&service=WNENotaFiscalEletronicaNfe'
      
      console.log('📡 [DEBUG] Enviando XML de Cancelamento (REVERTIDO + COD 2):', soapEnvelope)

      const resp = await fetch(url, {
        method: 'POST',
        headers: {
          'Authorization': `Basic ${basicAuth}`,
          'Content-Type': 'text/xml; charset=utf-8',
          'SOAPAction': 'net.atende#CancelarNfseEnvio'
        },
        body: soapEnvelope
      })

      const bodyResp = await resp.text()
      console.log('📡 [DEBUG] Resposta da Prefeitura (Cancelamento):', bodyResp)
      if (resp.status === 401 || bodyResp.includes('Acesso Negado')) {
        return new Response(JSON.stringify({ error: 'Acesso negado no IPM. Verifique a senha da prefeitura.' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }

      // Procura por tag <Cancelamento> que denota sucesso, ou <Mensagem> de erro
      const sucessoMatch = bodyResp.match(/<Cancelamento>(.*?)<\/Cancelamento>/s)
      const erroMatch = bodyResp.match(/<Mensagem[^>]*>([^<]+)<\/Mensagem>/i)
      const faultMatch = bodyResp.match(/<faultstring>([^<]+)<\/faultstring>/i)

      if (!sucessoMatch) {
         let erroMsg = 'Erro na comunicação de cancelamento com a Prefeitura.'
         if (erroMatch) erroMsg = erroMatch[1].replace(/&lt;/g, '<').replace(/&gt;/g, '>')
         else if (faultMatch) erroMsg = faultMatch[1]
         
         // Muitas vezes se retorna que a nota "já está cancelada"
         if (erroMsg.toLowerCase().includes('ja cancelada') || erroMsg.toLowerCase().includes('já cancelada')) {
            // considerar sucesso
         } else {
           return new Response(JSON.stringify({ sucesso: false, error: erroMsg }), { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
         }
      }

    } else {
      // ----------------------------------------------------
      // CANCELAMENTO FOCUS NFE (Outras Cidades)
      // ----------------------------------------------------
      const focusUrl = `${FOCUS_API_URL}/${emissao.appointment_id}`

      const focusResp = await fetch(focusUrl, {
        method: 'DELETE',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic ' + btoa(`${FOCUS_TOKEN}:`)
        },
        body: JSON.stringify({ justificativa: motivo })
      })

      const bodyResp = await focusResp.text()

      if (!focusResp.ok && focusResp.status !== 202) {
        let erroMotivo = `HTTP ${focusResp.status}`
        try {
          const jsonErro = JSON.parse(bodyResp)
          erroMotivo = jsonErro.message ?? jsonErro.errors?.[0]?.mensagem ?? bodyResp
        } catch (e) {
          // failed to parse
        }

        return new Response(
          JSON.stringify({ sucesso: false, error: erroMotivo }),
          { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        )
      }
    }

    // Se a Focus aceitou o cancelamento (200 OK), marcamos como cancelada
    await supabase.from('nfse_emissoes')
      .update({ status: 'cancelada', motivo_rejeicao: `Cancelada: ${motivo}` })
      .eq('id', nfse_id)

    return new Response(
      JSON.stringify({ sucesso: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
    
  } catch (err) {
    console.error('❌ cancelar-nfse:', err)
    return new Response(
      JSON.stringify({ error: `Erro interno: ${err instanceof Error ? err.message : String(err)}` }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
