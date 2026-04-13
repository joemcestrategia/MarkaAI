const fs = require('fs');

async function testAuth(url, user, pass) {
  try {
    const auth = Buffer.from(`${user}:${pass}`).toString('base64');
    const resp = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'text/xml; charset=utf-8'
      },
      body: '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/"></soapenv:Envelope>'
    });
    const text = await resp.text();
    console.log(`[${resp.status}] HTTP For URL: ${url}`);
    console.log(`User: ${user} | Pass: ${pass}`);
    console.log(`Response Snippet: ${text.substring(0, 150).replace(/\n/g, ' ')}\n`);
  } catch (err) {
    console.log(`ERROR: ${err.message}\n`);
  }
}

async function run() {
  const urls = [
    'https://itabirito.atende.net/?pg=services&service=WNENotaFiscalEletronicaNfe&cidade=padrao',
    'https://itabirito.atende.net/atende.php?pg=rest&service=WNERestServiceNFSe&cidade=padrao'
  ];
  const users = [
    '41027409000189',
    '41.027.409/0001-89'
  ];
  const pass = '09142583624A_*b';

  console.log("=== INICIANDO TESTES ===");
  for (const url of urls) {
    for (const u of users) {
      await testAuth(url, u, pass);
    }
  }
  console.log("=== FIM ===");
}

run();
