const { createClient } = require('@supabase/supabase-js');

const supabaseUrl = 'https://uhccgcojwqvkfyzrmebv.supabase.co';
const supabaseKey = 'sb_publishable_gmX2ol9O_y3XjHt8bJ-NgQ_b2nfxFmR'; // Usando anon key para teste (espero que RLS permita leitura se for public)
// Se falhar, usarei a service role se encontrar.

const supabase = createClient(supabaseUrl, supabaseKey);

async function checkShops() {
  console.log('--- Buscando Lojas ---');
  const { data, error } = await supabase
    .from('shops')
    .select('id, name, mercadopago')
    .limit(10);

  if (error) {
    console.error('Erro ao buscar lojas:', error);
    return;
  }

  console.log('Resultados:');
  data.forEach(shop => {
    console.log(`ID: ${shop.id} | Nome: ${shop.name} | MP Conectado: ${shop.mercadopago ? 'SIM' : 'NÃO'}`);
    if (shop.mercadopago) {
        console.log('Detalhes MP:', JSON.stringify(shop.mercadopago, null, 2));
    }
  });
}

checkShops();
