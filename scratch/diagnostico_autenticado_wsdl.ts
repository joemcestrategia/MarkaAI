async function diagnosticoWsdl() {
  const url = 'https://itabirito.atende.net/?pg=services&service=WNENotaFiscalEletronicaNfe&wsdl';
  const user = '41027409000189';
  const pass = 'Afroed2022*'; 
  
  console.log(`Buscando WSDL em: ${url}`);

  // FORMA 1: Basic Auth
  console.log('--- Testando Forma 1: Basic Auth ---');
  try {
    const auth = btoa(`${user}:${pass}`);
    const resp1 = await fetch(url, {
      headers: {
        'Authorization': `Basic ${auth}`,
        'User-Agent': 'Mozilla/5.0'
      }
    });
    console.log(`Status Forma 1: ${resp1.status}`);
    if (resp1.ok) {
      const content = await resp1.text();
      console.log('SUCESSO (Forma 1)');
      console.log('--- CONTEÚDO DO WSDL ---');
      console.log(content);
      return;
    }
  } catch (e) {
    console.log(`Erro na Forma 1: ${e.message}`);
  }

  // FORMA 2: Custom Headers
  console.log('--- Testando Forma 2: Custom Headers ---');
  try {
    const resp2 = await fetch(url, {
      headers: {
        'nfse-username': user,
        'nfse-password': pass,
        'User-Agent': 'Mozilla/5.0'
      }
    });
    console.log(`Status Forma 2: ${resp2.status}`);
    if (resp2.ok) {
      const content = await resp2.text();
      console.log('SUCESSO (Forma 2)');
      console.log('--- CONTEÚDO DO WSDL ---');
      console.log(content);
      return;
    }
  } catch (e) {
    console.log(`Erro na Forma 2: ${e.message}`);
  }
}

diagnosticoWsdl();
