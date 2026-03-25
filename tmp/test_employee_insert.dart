import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  print("Iniciando inspeção...");
  await Supabase.initialize(
    url: 'https://uhccgcojwqvkfyzrmebv.supabase.co',
    anonKey: 'sb_publishable_gmX2ol9O_y3XjHt8bJ-NgQ_b2nfxFmR',
  );

  final client = Supabase.instance.client;

  try {
    // Tenta buscar um registro para ver a estrutura
    final response = await client.from('employees').select().limit(1);
    print("Sucesso ao ler employees: $response");
    
    // Tenta inserir um registro temporário com phone null para testar restrição
    print("Tentando inserir com phone null...");
    // Precisamos de um shop_id válido. Vamos tentar pegar um existente.
    final shops = await client.from('shops').select('id').limit(1);
    if (shops.isNotEmpty) {
      final shopId = shops[0]['id'];
      print("Usando shop_id: $shopId");
      
      try {
        final insertResponse = await client.from('employees').insert({
          'name': 'Teste Antigravity',
          'email': 'teste_antigravity@example.com',
          'shop_id': shopId,
          'phone': null, // Testando null
          'start_time': '08:00',
          'end_time': '18:00',
          'work_days': [1,2,3,4,5],
        }).select();
        print("Inserção com phone: null funcionou! Resposta: $insertResponse");
        
        // Limpa o teste
        if (insertResponse.isNotEmpty) {
          final id = insertResponse[0]['id'];
          await client.from('employees').delete().eq('id', id);
          print("Registro de teste removido.");
        }
      } catch (e) {
        print("Erro ao inserir com phone null: $e");
        print("Tentando com phone: '' (string vazia)...");
        try {
          final insertResponseVazio = await client.from('employees').insert({
            'name': 'Teste Antigravity 2',
            'email': 'teste_antigravity2@example.com',
            'shop_id': shopId,
            'phone': '', // Testando string vazia
            'start_time': '08:00',
            'end_time': '18:00',
            'work_days': [1,2,3,4,5],
          }).select();
          print("Inserção com phone: '' funcionou! Resposta: $insertResponseVazio");
          
          if (insertResponseVazio.isNotEmpty) {
            final id = insertResponseVazio[0]['id'];
            await client.from('employees').delete().eq('id', id);
            print("Registro de teste 2 removido.");
          }
        } catch (e2) {
          print("Erro ao inserir com string vazia: $e2");
        }
      }
    } else {
      print("Nenhum shop_id encontrado para teste.");
    }
  } catch (e) {
    print("Erro geral: $e");
  }
}
