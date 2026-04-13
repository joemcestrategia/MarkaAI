
const url = 'https://itabirito.atende.net/?pg=services&service=WNENotaFiscalEletronicaNfe&cidade=padrao';
const auth = btoa('41027409000189:09142583624A_*b');

async function testFinal() {
  const soap = `
    <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:net="net.atende">
      <soapenv:Header/>
      <soapenv:Body>
        <net:EnviarLoteRpsSincronoEnvio>
          <net:LoteRps Id="L1" versao="2.01">
            <net:NumeroLote>1</net:NumeroLote>
            <net:Prestador>
              <net:CpfCnpj><net:Cnpj>41027409000189</net:Cnpj></net:CpfCnpj>
              <net:InscricaoMunicipal>1505602</net:InscricaoMunicipal>
            </net:Prestador>
            <net:QuantidadeRps>1</net:QuantidadeRps>
            <net:ListaRps>
              <net:Rps>
                <net:InfDeclaracaoPrestacaoServico Id="R1">
                  <net:Rps>
                    <net:IdentificacaoRps><net:Numero>1</net:Numero><net:Serie>1</net:Serie><net:Tipo>1</net:Tipo></net:IdentificacaoRps>
                    <net:DataEmissao>2026-04-09</net:DataEmissao>
                    <net:Status>1</net:Status>
                  </net:Rps>
                  <net:Competencia>2026-04-09</net:Competencia>
                  <net:Servico>
                    <net:Valores>
                      <net:ValorServicos>10.00</net:ValorServicos>
                      <net:ValorIss>0.20</net:ValorIss>
                      <net:Aliquota>2.0000</net:Aliquota>
                    </net:Valores>
                    <net:IssRetido>2</net:IssRetido>
                    <net:ItemListaServico>06.01.01</net:ItemListaServico>
                    <net:CodigoCnae>9602501</net:CodigoCnae>
                    <net:CodigoTributacaoMunicipio>01</net:CodigoTributacaoMunicipio>
                    <net:Discriminacao>Teste Aliquota 2.00 e Subgrupo 06.01.01</net:Discriminacao>
                    <net:CodigoMunicipio>3131901</net:CodigoMunicipio>
                    <net:ExigibilidadeISS>1</net:ExigibilidadeISS>
                  </net:Servico>
                  <net:Prestador><net:CpfCnpj><net:Cnpj>41027409000189</net:Cnpj></net:CpfCnpj></net:Prestador>
                  <net:TomadorServico>
                    <net:RazaoSocial>CONSUMIDOR FINAL</net:RazaoSocial>
                  </net:TomadorServico>
                  <net:OptanteSimplesNacional>1</net:OptanteSimplesNacional>
                  <net:IncentivoFiscal>2</net:IncentivoFiscal>
                </net:InfDeclaracaoPrestacaoServico>
              </net:Rps>
            </net:ListaRps>
          </net:LoteRps>
        </net:EnviarLoteRpsSincronoEnvio>
      </soapenv:Body>
    </soapenv:Envelope>`.trim();

  try {
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Authorization': `Basic ${auth}`, 'Content-Type': 'text/xml;charset=UTF-8', 'SOAPAction': 'net.atende#EnviarLoteRpsSincronoEnvio' },
      body: soap
    });
    console.log(await r.text());
  } catch (e) { console.error('Erro:', e); }
}

await testFinal();
