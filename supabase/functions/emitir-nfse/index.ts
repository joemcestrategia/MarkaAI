import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createSupabaseAdminClient, createSupabaseClient } from '../_shared/supabase.ts'
import { corsHeaders } from '../_shared/cors.ts'

function digits(v: string): string { return v.replace(/\D/g, '') }
function ascii(s: string): string {
  if (!s) return ''
  return s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^\x20-\x7E]/g, '')
}

/**
 * Emite ou Simula NFS-e pelo WebService de Itabirito (IPM / Atende.Net)
 */
async function emitirItabirito(supabase: any, cfg: any, apptData: any, emissaoId: string | null, isDryRun = false) {
  const prestadorCnpj = digits(cfg.cnpj)
  const pass = cfg.senha_prefeitura
  const basicAuth = btoa(`${prestadorCnpj}:${pass}`)

  // 1. Validação de Dados (Motor de Checklist)
  const checklist: any[] = []
  const erros: string[] = []

  const validar = (campo: string, valor: any, msgErro: string) => {
    const ok = !!valor && valor.toString().trim() !== ''
    checklist.push({ campo, status: ok ? 'ok' : 'erro', mensagem: ok ? 'Preenchido corretamente' : msgErro })
    if (!ok) erros.push(msgErro)
    return ok
  }

  validar('CNPJ Prestador', cfg.cnpj, 'CNPJ da empresa não configurado.')
  validar('Inscrição Municipal', cfg.inscricao_municipal, 'Inscrição municipal do prestador ausente.')
  validar('Item da Lista (LC 116)', cfg.codigo_servico_lc116, 'Código de serviço LC 116 não configurado.')
  validar('Código Município', cfg.codigo_municipio, 'Código IBGE do município ausente.')
  validar('Nome do Cliente', apptData.client_name, 'Nome do cliente não informado.')
  validar('CPF do Cliente', apptData.client_user_cpf, 'O CPF do cliente é obrigatório para emissão de nota.')
  validar('Endereço', apptData.logradouro, 'Endereço (logradouro) do cliente não informado.')
  validar('CEP', apptData.cep, 'CEP do cliente ausente.')
  // validar('Código NBS', cfg.codigo_nbs, 'Código NBS não configurado (obrigatório para Itabirito).')

  // Mapeamentos Dinâmicos (Banco de Dados)
  let itemListaServico = (cfg.codigo_servico_lc116 || "06.01.01").toString().trim()
  // Auto-formatação para padrão LC 116 (XX.YY ou XX.YY.ZZ) se vierem apenas dígitos
  if (/^\d+$/.test(itemListaServico)) {
    if (itemListaServico.length === 4) {
      itemListaServico = `${itemListaServico.substring(0, 2)}.${itemListaServico.substring(2, 4)}`
    } else if (itemListaServico.length === 6) {
      itemListaServico = `${itemListaServico.substring(0, 2)}.${itemListaServico.substring(2, 4)}.${itemListaServico.substring(4, 6)}`
    }
  }
  const codigoCnae = cfg.codigo_cnae || "9602501"
  const codigoTributacao = cfg.codigo_tributacao_municipio || "960250100"
  
  // Formata NBS para padrão X.XXXX.XX.XX (exigido por Itabirito)
  function formatNbs(v: string): string {
    const d = v.replace(/\D/g, "")
    if (d.length !== 9) return v 
    return `${d[0]}.${d.substring(1, 5)}.${d.substring(5, 7)}.${d.substring(7, 9)}`
  }

  const rawNbs = (cfg.codigo_nbs || (itemListaServico === '06.01.01' ? '126021000' : "")).toString()
  const codigoNbs = formatNbs(rawNbs)
  
  const aliquota = (Number(cfg.aliquota_iss) || 2.01)
  
  const valorServico = Number(apptData.total_value ?? apptData.total_price ?? 0).toFixed(2)
  const valorIss = (Number(valorServico) * (aliquota / 100)).toFixed(2)
  
  const discriminacao = ascii(apptData.service_name || 'Servicos de Estetica')
  const nomeTomador = ascii(apptData.client_name || 'CONSUMIDOR FINAL')
  const cpfTomador = digits(apptData.client_user_cpf || '')
  
  const hoje = new Date().toISOString().split('T')[0]
  const numeroRps = (Number(cfg.proximo_numero_rps) || Math.floor(Date.now() / 1000))

  // GERAÇÃO DO XML ABRASF 2.04
  const abrasfXml = `<EnviarLoteRpsSincronoEnvio xmlns="http://www.abrasf.org.br/nfse.xsd">
  <LoteRps Id="L1" versao="2.01">
    <NumeroLote>1</NumeroLote>
    <Prestador>
      <CpfCnpj><Cnpj>${prestadorCnpj}</Cnpj></CpfCnpj>
      <InscricaoMunicipal>${digits(cfg.inscricao_municipal || '')}</InscricaoMunicipal>
    </Prestador>
    <QuantidadeRps>1</QuantidadeRps>
    <ListaRps>
      <Rps>
        <InfDeclaracaoPrestacaoServico Id="R${numeroRps}">
          <Rps>
            <IdentificacaoRps>
              <Numero>${numeroRps}</Numero>
              <Serie>${cfg.serie_rps || '1'}</Serie>
              <Tipo>1</Tipo>
            </IdentificacaoRps>
            <DataEmissao>${hoje}</DataEmissao>
            <Status>1</Status>
          </Rps>
          <Competencia>${hoje}</Competencia>
          <Servico>
            <Valores>
              <ValorServicos>${valorServico}</ValorServicos>
              <ValorDeducoes>0.00</ValorDeducoes>
              <ValorPis>0.00</ValorPis>
              <ValorCofins>0.00</ValorCofins>
              <ValorInss>0.00</ValorInss>
              <ValorIr>0.00</ValorIr>
              <ValorCsll>0.00</ValorCsll>
              <OutrasRetencoes>0.00</OutrasRetencoes>
              <ValorIss>${valorIss}</ValorIss>
              <Aliquota>${aliquota}</Aliquota>
              <DescontoIncondicionado>0.00</DescontoIncondicionado>
              <DescontoCondicionado>0.00</DescontoCondicionado>
            </Valores>
            <IssRetido>2</IssRetido>
            <ItemListaServico>${itemListaServico}</ItemListaServico>
            <CodigoCnae>${codigoCnae}</CodigoCnae>
            <CodigoTributacaoMunicipio>${codigoTributacao}</CodigoTributacaoMunicipio>
            ${(codigoNbs) ? `<CodigoNbs>${codigoNbs}</CodigoNbs>` : ''}
            <Discriminacao>${discriminacao}</Discriminacao>
            <CodigoMunicipio>${cfg.codigo_municipio || '3131901'}</CodigoMunicipio>
            <ExigibilidadeISS>1</ExigibilidadeISS>
            <MunicipioIncidencia>${cfg.codigo_municipio || '3131901'}</MunicipioIncidencia>
          </Servico>
          <Prestador>
            <CpfCnpj><Cnpj>${prestadorCnpj}</Cnpj></CpfCnpj>
            <InscricaoMunicipal>${digits(cfg.inscricao_municipal || '')}</InscricaoMunicipal>
          </Prestador>
          <TomadorServico>
            ${cpfTomador ? `
            <IdentificacaoTomador>
              <CpfCnpj>
                <Cpf>${cpfTomador}</Cpf>
              </CpfCnpj>
            </IdentificacaoTomador>` : ''}
            <RazaoSocial>${nomeTomador}</RazaoSocial>
            <Endereco>
              <Endereco>${ascii(apptData.logradouro || 'Rua não informada')}</Endereco>
              <Numero>${apptData.numero || 'SN'}</Numero>
              ${apptData.complemento ? `<Complemento>${ascii(apptData.complemento)}</Complemento>` : ''}
              <Bairro>${ascii(apptData.bairro || 'Centro')}</Bairro>
              <CodigoMunicipio>${cfg.codigo_municipio || '3131901'}</CodigoMunicipio>
              <Uf>MG</Uf>
              <Cep>${digits(apptData.cep || '31319000')}</Cep>
            </Endereco>
            ${(apptData.telefone || apptData.email) ? `
            <Contato>
              ${apptData.telefone ? `<Telefone>${digits(apptData.telefone).substring(0, 11)}</Telefone>` : ''}
              ${apptData.email ? `<Email>${apptData.email}</Email>` : ''}
            </Contato>` : ''}
          </TomadorServico>
          <OptanteSimplesNacional>1</OptanteSimplesNacional>
          <IncentivoFiscal>2</IncentivoFiscal>
        </InfDeclaracaoPrestacaoServico>
      </Rps>
    </ListaRps>
  </LoteRps>`

  if (isDryRun) {
    return {
      sucesso: erros.length === 0,
      erros,
      checklist,
      xml_preview: abrasfXml
    }
  }

  // Se houver erros críticos, bloqueia a emissão real
  if (erros.length > 0) {
    throw new Error(`Dados insuficientes para emissão: ${erros.join(', ')}`)
  }

  const soapEnvelope = `<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:net="net.atende">
  <soapenv:Header/>
  <soapenv:Body>
    <net:EnviarLoteRpsSincronoEnvio>
      ${abrasfXml}
    </net:EnviarLoteRpsSincronoEnvio>
  </soapenv:Body>
</soapenv:Envelope>`

  const url = cfg.url_webservice || 'https://itabirito.atende.net/?pg=services&service=WNENotaFiscalEletronicaNfe'

  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Basic ${basicAuth}`,
      'Content-Type': 'text/xml; charset=utf-8',
      'SOAPAction': 'net.atende#EnviarLoteRpsSincronoEnvio'
    },
    body: soapEnvelope
  })

  const bodyResp = await resp.text()
  
  if (resp.status === 401 || bodyResp.includes('Acesso Negado')) {
    throw new Error('Acesso negado pela prefeitura — verifique credenciais')
  }

  const numeroMatch = bodyResp.match(/<Numero[^>]*>(\d+)<\/Numero>/i)
  const codVerifMatch = bodyResp.match(/<CodigoVerificacao[^>]*>([^<]+)<\/CodigoVerificacao>/i)
  const erroMatch = bodyResp.match(/<Mensagem[^>]*>([^<]+)<\/Mensagem>/i)
  const faultMatch = bodyResp.match(/<faultstring>([^<]+)<\/faultstring>/)

  if ((erroMatch || faultMatch) && !numeroMatch) {
    const msg = erroMatch ? (erroMatch[1].includes('&lt;') ? erroMatch[1].replace(/&lt;/g, '<').replace(/&gt;/g, '>') : erroMatch[1]) : (faultMatch ? faultMatch[1] : 'Erro na prefeitura')
    throw new Error(msg)
  }

  if (numeroMatch && emissaoId) {
    await supabase.from('nfse_emissoes').update({
      status: 'autorizada',
      numero_nfse: numeroMatch[1],
      codigo_verificacao: codVerifMatch ? codVerifMatch[1] : null,
      xml_dps: abrasfXml,
      xml_nfse: bodyResp
    }).eq('id', emissaoId)

    await supabase.rpc('incrementar_rps', { shop_id_param: cfg.shop_id })
    return { sucesso: true, nfse_id: emissaoId, numero: numeroMatch[1], cod_verificacao: codVerifMatch ? codVerifMatch[1] : null }
  }

  return { sucesso: false, error: 'Resposta inesperada do servidor.', raw: bodyResp.substring(0, 500) }
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  // ── Autenticação dual-mode (OWASP U3) ────────────────────────────────
  // Aceita: (1) JWT de usuário autenticado, ou (2) service_role (chamada
  // interna de outra Edge Function, como mpPaymentWebhook auto-emissão).
  const authHeader = req.headers.get('Authorization') ?? ''
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const isServiceRole = serviceRoleKey.length > 0 && authHeader.includes(serviceRoleKey)

  if (!isServiceRole) {
    // Chamada de usuário — validar JWT
    const supabaseAuth = createSupabaseClient(req)
    const { data: { user }, error: authErr } = await supabaseAuth.auth.getUser()
    if (authErr || !user) {
      return new Response(JSON.stringify({ error: 'Não autenticado' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Pré-parse do body para verificar ownership (body será re-lido abaixo)
    // Precisamos clonar o request pois o body só pode ser lido uma vez
    const clonedReq = req.clone()
    try {
      const bodyCheck = await clonedReq.json()
      const targetShopId = bodyCheck.shop_id
      if (targetShopId) {
        const adminClient = createSupabaseAdminClient()
        const { data: shop } = await adminClient
          .from('shops')
          .select('owner_id')
          .eq('id', targetShopId)
          .maybeSingle()
        if (!shop || shop.owner_id !== user.id) {
          return new Response(JSON.stringify({ error: 'Acesso negado — você não é dono desta loja' }), {
            status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          })
        }
      }
    } catch (_) {
      // Se o body não for JSON válido, o try principal vai capturar
    }
  }
  // ── Fim Autenticação ─────────────────────────────────────────────────

  const supabase = createSupabaseAdminClient()
  try {
    const { appointment_id, shop_id, dry_run = false } = await req.json()

    // 0. Trava de Segurança: Verificar se já existe nota autorizada
    if (!dry_run) {
      const { data: notaExistente } = await supabase
        .from('nfse_emissoes')
        .select('id, numero_nfse')
        .eq('appointment_id', appointment_id)
        .eq('status', 'autorizada')
        .maybeSingle()

      if (notaExistente) {
        return new Response(JSON.stringify({ 
          error: `Este agendamento já possui a nota fiscal nº ${notaExistente.numero_nfse} autorizada.`,
          ja_emitida: true 
        }), { status: 400, headers: corsHeaders })
      }
    }

    // 1. Buscar Dados do Agendamento (Sem JOIN direto por causa de FK ausente no PostgREST)
    const { data: appt, error: apptErr } = await supabase
      .from('appointments')
      .select('*')
      .eq('id', appointment_id)
      .single()

    if (apptErr) throw new Error(`Erro ao buscar agendamento: ${JSON.stringify(apptErr)}`);
    if (!appt) throw new Error('Agendamento não encontrado');

    // Buscar dados do cliente separadamente se o client_id estiver preenchido
    let client = null;
    if (appt.client_id) {
      const { data: clientData } = await supabase
        .from('users')
        .select('*')
        .eq('id', appt.client_id)
        .maybeSingle()
      client = clientData;
    }
    appt.client = client;

    const apptData = {
      ...appt,
      client_user_cpf: appt.client_user_cpf || appt.client?.cpf || appt.client?.document_cpf,
      logradouro: appt.logradouro || appt.client?.street || appt.client?.address || 'Rua não informada',
      numero: appt.numero || appt.client?.number || appt.client?.address_number || 'SN',
      complemento: appt.complemento || appt.client?.complement || appt.client?.address_complement || '',
      bairro: appt.bairro || appt.client?.neighborhood || 'Centro',
      cep: appt.cep || appt.client?.zip_code || '31319000',
      telefone: appt.telefone || appt.client_phone || appt.client?.phone || '',
      email: appt.email || appt.client?.email || ''
    }

    // 2. Buscar Configuração Fiscal
    const { data: cfg, error: cfgErr } = await supabase
      .from('nfse_config')
      .select('*')
      .eq('shop_id', shop_id)
      .eq('ativo', true)
      .maybeSingle()

    if (cfgErr || !cfg) throw new Error('Configuração NFS-e não encontrada ou inativa')

    // 3. Gerador de Emissão (ou apenas Simulação)
    let emissaoId = null
    if (!dry_run) {
      const { data: emissao } = await supabase.from('nfse_emissoes').insert({
        shop_id,
        appointment_id,
        status: 'processando',
        valor_servico: appt.total_value ?? appt.total_price ?? 0,
        tomador_nome: appt.client_name ?? 'CONSUMIDOR FINAL'
      }).select('id').single()
      emissaoId = emissao.id
    }

    // 4. Disparar Simulação ou Emissão Real
    const result = await emitirItabirito(supabase, cfg, apptData, emissaoId, dry_run)
    return new Response(JSON.stringify(result), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: corsHeaders })
  }
})
