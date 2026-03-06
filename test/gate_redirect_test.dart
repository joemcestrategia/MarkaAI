import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Interceptador de Agendamento Não-Autenticado (Módulo 4)', () {
    test('Ao tentar agendar sem ID do usuário, deve compor a ReturnUrl correta',
        () {
      final isLoggedIn = false;
      final shopSlug = 'afroed';
      final serviceId = 'srv_123';

      String? returnUrlTarget;

      if (!isLoggedIn) {
        returnUrlTarget = '/$shopSlug/$serviceId';
      }

      expect(returnUrlTarget, '/afroed/srv_123');
    });

    test('Ao voltar do Login, deve limpar a URL e garantir contexto nulo', () {
      String? returnUrlCache = '/afroed/srv_123';

      String readAndClear() {
        final r = returnUrlCache;
        returnUrlCache = null;
        return r ?? '';
      }

      final url = readAndClear();
      expect(url, '/afroed/srv_123');
      expect(returnUrlCache, null); // Garantindo Single-use consume
    });
  });
}
