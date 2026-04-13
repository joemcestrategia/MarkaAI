import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

void main() async {
  // Script rápido para depurar o motivo de não carregar notas pendentes
  try {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
       print('ERRO: Nenhum usuário logado.');
       return;
    }

    final userData = await client.from('users').select('shop_id').eq('id', user.id).maybeSingle();
    final shopId = userData?['shop_id'];
    
    if (shopId == null) {
      print('ERRO: Usuário não tem shop_id vinculado.');
      return;
    }

    print('DEBUG: Analisando Shop ID: $shopId');

    final config = await client.from('nfse_config').select().eq('shop_id', shopId).maybeSingle();
    print('DEBUG: Config Fiscal: $config');

    if (config == null || config['ativo'] != true) {
      print('AVISO: NFSe não está ativa para esta loja.');
    }

    final pendentes = await client
        .from('appointments')
        .select('id, status, total_value, total_price, total_payable')
        .eq('shop_id', shopId)
        .eq('status', 'concluido')
        .limit(10);
    
    print('DEBUG: Agendamentos Concluídos Encontrados: ${pendentes.length}');
    for (var ap in pendentes) {
       print(' - ID: ${ap['id']}, Valor: ${ap['total_value']} / ${ap['total_price']} / ${ap['total_payable']}');
    }

  } catch (e) {
    print('ERRO NO SCRIPT: $e');
  }
}
