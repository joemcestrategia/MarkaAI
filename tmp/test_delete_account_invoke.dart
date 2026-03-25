import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

void main() async {
  print('=== TESTE INVOCAR DELETE_USER_ACCOUNT ===');
  
  final url = 'https://uhccgcojwqvkfyzrmebv.supabase.co';
  final anonKey = 'sb_publishable_gmX2ol9O_y3XjHt8bJ-NgQ_b2nfxFmR';

  await Supabase.initialize(
    url: url,
    anonKey: anonKey,
    authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
  );

  final supabase = Supabase.instance.client;
  final rand = Random().nextInt(100000);
  final email = 'test_del_$rand@example.com';
  final password = 'Password@123';

  try {
    print('1. Criando usuário de teste: $email');
    final signUpRes = await supabase.auth.signUp(
      email: email,
      password: password,
    );

    if (signUpRes.user == null) {
      print('Erro ao criar usuário');
      return;
    }

    final userId = signUpRes.user!.id;
    print('Usuário criado com ID: $userId');

    // Opcional: Criar perfil na tabela 'users' se houver trigger ou manual
    // como a trigger geralmente cria, vamos esperar um pouco ou inserir
    await Future.delayed(const Duration(seconds: 2));

    print('2. Invocando deleteUserAccount...');
    print('Autenticado como: ${supabase.auth.currentUser?.email}');

    final response = await supabase.functions.invoke(
      'deleteUserAccount',
    );

    print('🎉 Status da Função: ${response.status}');
    print('🎉 Resposta da Função: ${response.data}');

  } on FunctionException catch (e) {
    print('❌ Erro da Função (FunctionException):');
    print('Status: ${e.status}');
    print('Mensagem: $e');
    print('Detalhes: ${e.details}');
  } catch (e) {
    print('❌ Erro Geral: $e');
  } finally {
    print('=== FIM DO TESTE ===');
  }
}
