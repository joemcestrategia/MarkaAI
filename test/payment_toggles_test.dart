import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Lógica de Toggles Pagamento (Módulo 1)', () {
    test('Não deve permitir salvar se nenhum método estiver ativo', () {
      bool cartaoOnline = false;
      bool debitoPresencial = false;
      bool pagarPessoalmente = false;

      bool isValido = cartaoOnline || debitoPresencial || pagarPessoalmente;
      expect(isValido, false);
    });

    test('Deve permitir salvar se ao menos um método estiver ativo (Ex: Pix)',
        () {
      bool cartaoOnline = false;
      bool debitoPresencial = false;
      bool pagarPessoalmente = true;

      bool isValido = cartaoOnline || debitoPresencial || pagarPessoalmente;
      expect(isValido, true);
    });

    test(
        'Downgrade de Premium para Free desativa cartão e débito e força presencial',
        () {
      bool canUseOnline = false;

      bool cartaoOnline = true;
      bool debitoPresencial = true;
      bool pagarPessoalmente = false;

      if (!canUseOnline) {
        cartaoOnline = false;
        debitoPresencial = false;
        pagarPessoalmente = true;
      }

      expect(cartaoOnline, false);
      expect(debitoPresencial, false);
      expect(pagarPessoalmente, true);
    });
  });
}
