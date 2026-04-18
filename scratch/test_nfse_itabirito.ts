/**
 * Script de Teste: Conexão NFSe Itabirito (Atende.Net)
 * FORMATO CUSTOMIZADO (NAMESPACE net.atende) - Baseado no WSDL
 */

export {};
const CNPJ = "41027409000189";
const IM = "1505602";
const USUARIO = "41027409000189";
const SENHA = "09142583624A_*b";

async function testarConexao() {
  const url = 'https://itabirito.atende.net/?pg=services&service=WNENotaFiscalEletronicaNfe&cidade=padrao';
  
  const valorServicos = 1.00;
  const aliquota = 0.05; 
  const valorIss = valorServicos * aliquota;
  const valorLiquido = valorServicos;

  // XML usando EXCLUSIVAMENTE o namespace net.atende conforme o WSDL
  const xmlNetAtende = `
    <net:LoteRps Id="L123" versao="2.01">
      <net:NumeroLote>123</net:NumeroLote>
      <net:Prestador>
        <net:CpfCnpj><net:Cnpj>${CNPJ}</net:Cnpj></net:CpfCnpj>
        <net:InscricaoMunicipal>${IM}</net:InscricaoMunicipal>
      </net:Prestador>
      <net:QuantidadeRps>1</net:QuantidadeRps>
      <net:ListaRps>
        <net:Rps>
            <net:InfDeclaracaoPrestacaoServico Id="R1">
              <net:Rps>
                <net:IdentificacaoRps>
                  <net:Numero>1</net:Numero>
                  <net:Serie>A</net:Serie>
                  <net:Tipo>1</net:Tipo>
                </net:IdentificacaoRps>
                <net:DataEmissao>2024-04-09</net:DataEmissao>
                <net:Status>1</net:Status>
              </net:Rps>
              <net:Competencia>2024-04-09</net:Competencia>
              <net:Servico>
                <net:Valores>
                  <net:ValorServicos>${valorServicos.toFixed(2)}</net:ValorServicos>
                  <net:ValorIss>${valorIss.toFixed(2)}</net:ValorIss>
                  <net:Aliquota>${aliquota.toFixed(4)}</net:Aliquota>
                </net:Valores>
                <net:IssRetido>2</net:IssRetido>
                <net:ItemListaServico>01.07</net:ItemListaServico>
                <net:CodigoTributacaoMunicipio>0107</net:CodigoTributacaoMunicipio>
                <net:Discriminacao>TESTE INTEGRACAO WEBSERVICE - ORDEM CORRETA</net:Discriminacao>
                <net:CodigoMunicipio>3131901</net:CodigoMunicipio>
                <net:ExigibilidadeISS>1</net:ExigibilidadeISS>
              </net:Servico>
            <net:Prestador>
              <net:CpfCnpj><net:Cnpj>${CNPJ}</net:Cnpj></net:CpfCnpj>
            </net:Prestador>
            <net:TomadorServico>
              <net:RazaoSocial>CONSUMIDOR TESTE</net:RazaoSocial>
            </net:TomadorServico>
            <net:OptanteSimplesNacional>1</net:OptanteSimplesNacional>
            <net:IncentivoFiscal>2</net:IncentivoFiscal>
          </net:InfDeclaracaoPrestacaoServico>
        </net:Rps>
      </net:ListaRps>
    </net:LoteRps>
  `.trim();

  const soapEnvelope = `
    <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:net="net.atende">
      <soapenv:Header/>
      <soapenv:Body>
        <net:EnviarLoteRpsSincronoEnvio>
          ${xmlNetAtende}
        </net:EnviarLoteRpsSincronoEnvio>
      </soapenv:Body>
    </soapenv:Envelope>
  `.trim();

  const authHeader = `Basic ${btoa(USUARIO + ":" + SENHA)}`;

  console.log("🚀 Iniciando teste com namespace net.atende...");
  
  try {
    const resp = await fetch(url, {
      method: "POST",
      headers: {
        "Authorization": authHeader,
        "Content-Type": "text/xml;charset=UTF-8",
        "SOAPAction": "net.atende#EnviarLoteRpsSincronoEnvio"
      },
      body: soapEnvelope
    });

    const text = await resp.text();
    console.log(`\n📡 Status HTTP: ${resp.status}`);
    console.log("📄 Resposta da Prefeitura:");
    console.log(text);

  } catch (err) {
    console.error("\n💥 Erro Fatal na requisição:", err);
  }
}

testarConexao();
