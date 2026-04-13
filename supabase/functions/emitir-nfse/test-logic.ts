import forge from 'npm:node-forge@1.3.1'
import { SignedXml } from 'npm:xml-crypto@4.0.1'
import { DOMParser } from 'npm:@xmldom/xmldom@0.8.x'

// Funções copiadas do index.ts para teste
function cleanXml(xml: string): string {
  return xml.replace(/>\s+</g, '><').trim();
}

function signXml(xmlString: string, keyPem: string, certPem: string, elementId: string, locationPath: string): string {
  const doc = new DOMParser().parseFromString(xmlString, 'text/xml');
  const sig = new SignedXml({
    privateKey: keyPem,
    publicCert: certPem,
    signatureAlgorithm: 'http://www.w3.org/2000/09/xmldsig#rsa-sha1',
    canonicalizationAlgorithm: 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315'
  });

  const certBody = certPem
    .replace('-----BEGIN CERTIFICATE-----', '')
    .replace('-----END CERTIFICATE-----', '')
    .replace(/[\n\r]/g, '');

  sig.addReference({
    xpath: `//*[@Id="${elementId}"]`,
    transforms: ['http://www.w3.org/2000/09/xmldsig#enveloped-signature', 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315'],
    digestAlgorithm: 'http://www.w3.org/2000/09/xmldsig#sha1'
  });

  sig.keyInfoProvider = {
    getKeyInfo: () => `<X509Data><X509Certificate>${certBody}</X509Certificate></X509Data>`,
    getKey: () => keyPem
  };

  sig.computeSignature(xmlString, {
    location: { reference: `//${locationPath}`, action: 'after' }
  });

  return sig.getSignedXml();
}

// 1. Gerar Certificado Fake para Teste
console.log("--- Gerando certificado de teste ---");
const keys = forge.pki.rsa.generateKeyPair(2048);
const cert = forge.pki.createCertificate();
cert.publicKey = keys.publicKey;
cert.serialNumber = '01';
cert.validity.notBefore = new Date();
cert.validity.notAfter = new Date();
cert.validity.notAfter.setFullYear(cert.validity.notBefore.getFullYear() + 1);
const attrs = [{ name: 'commonName', value: 'Test Cert' }];
cert.setSubject(attrs);
cert.setIssuer(attrs);
cert.sign(keys.privateKey);

const privateKeyPem = forge.pki.privateKeyToPem(keys.privateKey);
const certPem = forge.pki.certificateToPem(cert);

// 2. Simular XML do RPS
console.log("--- Gerando e Assinando XML ---");
const rpsId = "R123";
const rpsXml = cleanXml(`
  <Rps>
    <InfDeclaracaoPrestacaoServico Id="${rpsId}">
      <Servico>
        <Valores>
          <ValorServicos>150.50</ValorServicos>
          <Aliquota>2.00</Aliquota>
        </Valores>
        <ItemListaServico>06.01</ItemListaServico>
      </Servico>
    </InfDeclaracaoPrestacaoServico>
  </Rps>
`);

try {
  const rpsAssinado = signXml(rpsXml, privateKeyPem, certPem, rpsId, 'InfDeclaracaoPrestacaoServico');
  console.log("✅ XML Assinado com sucesso!");
  console.log("--- XML RESULTANTE (Bloco Contínuo) ---");
  console.log(rpsAssinado);
  
  if (rpsAssinado.includes("SignatureValue") && rpsAssinado.includes("X509Certificate")) {
    console.log("✅ Tags de assinatura presentes.");
  }
  if (!rpsAssinado.includes("\n") && !rpsAssinado.includes("> <")) {
    console.log("✅ Regra de Bloco Contínuo respeitada.");
  } else {
    console.warn("⚠️ O XML assinado contém espaços ou quebras de linha.");
  }

} catch (err) {
  console.error("❌ Erro no teste de assinatura:", err);
}
