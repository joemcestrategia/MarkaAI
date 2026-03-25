const url = 'https://uhccgcojwqvkfyzrmebv.supabase.co';
const anonKey = 'sb_publishable_gmX2ol9O_y3XjHt8bJ-NgQ_b2nfxFmR'; // usei de lib/main.dart

async function run() {
  const rand = Math.floor(Math.random() * 100000);
  const email = `test_del_${rand}@example.com`;
  const password = 'Password@123';

  console.log(`1. Criando usuário: ${email}`);
  const signUpRes = await fetch(`${url}/auth/v1/signup`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'apikey': anonKey,
    },
    body: JSON.stringify({
      email: email,
      password: password,
    }),
  });

  const signUpData = await signUpRes.json();
  if (!signUpRes.ok) {
    console.error('Erro ao criar usuário:', signUpData);
    return;
  }

  const token = signUpData.access_token;
  if (!token) {
    console.error('Token não retornado. É preciso confirmar e-mail?');
    console.log(signUpData);
    return;
  }

  console.log('Usuário criado. Token:', token.substring(0, 20) + '...');

  console.log('2. Invocando deleteUserAccount...');
  const funcRes = await fetch(`${url}/functions/v1/deleteUserAccount`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'apikey': anonKey,
    },
  });

  console.log(`🎉 Status da Função: ${funcRes.status}`);
  const funcData = await funcRes.text();
  console.log(`🎉 Resposta: ${funcData}`);
}

run().catch(console.error);
