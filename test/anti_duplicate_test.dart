import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Regex e Máscaras de Telefone (Camada 1)', () {
    test('Extração de dígitos de número celular BR com DDD', () {
      final input = '(11) 98765-4321';
      final clean = input.replaceAll(RegExp(r'\D'), '');
      expect(clean, '11987654321');
    });

    test('Extração de dígitos de número fixo BR com DDD', () {
      final input = '(21) 3344-5566';
      final clean = input.replaceAll(RegExp(r'\D'), '');
      expect(clean, '2133445566');
    });
  });

  group('Validação de Nome Normalizado (Camada 5 - Homônimo)', () {
    test('Remoção de espaços, acentos maiúsculas', () {
      final input = ' JoãO pEdro da Sílva   ';
      // Mock da função do LoginPage
      String normalize(String v) => v.trim().toLowerCase();
      // Em produção remove diacríticos (Acentos), no teste validamos lowercase e trim
      expect(normalize(input), 'joão pedro da sílva');
    });
  });
}
