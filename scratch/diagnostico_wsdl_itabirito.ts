export {};
async function fetchWsdl() {
  const url = 'https://itabirito.atende.net/?pg=services&service=WNENotaFiscalEletronicaNfe&wsdl';
  console.log(`Buscando WSDL em: ${url}...`);
  
  const user = '41027409000189';
  const pass = 'Afroed2022*';
  const basicAuth = btoa(`${user}:${pass}`);
  
  try {
    const resp = await fetch(url, {
      headers: {
        'Authorization': `Basic ${basicAuth}`,
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
      }
    });
    
    if (!resp.ok) {
      console.error(`Erro ao buscar WSDL: ${resp.status} ${resp.statusText}`);
      const text = await resp.text();
      console.log('Corpo da resposta de erro:', text.substring(0, 1000));
      return;
    }
    
    const wsdl = await resp.text();
    console.log('--- CONTEÚDO DO WSDL ---');
    console.log(wsdl);
    console.log('--- FIM DO WSDL ---');
    
  } catch (err: any) {
    console.error('Falha na requisição:', err.message);
  }
}

fetchWsdl();
