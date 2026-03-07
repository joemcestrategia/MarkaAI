import 'package:cloud_firestore/cloud_firestore.dart';

/// Verifica se o perfil do cliente está completo para permitir agendamento.
class ProfileCheckService {
  /// Campos obrigatórios para cliente: nome, email, telefone, tipo, endereço (cep, rua, numero, cidade).
  static Future<bool> isClientProfileComplete(String uid) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!doc.exists) return false;
    final d = doc.data();
    if (d == null) return false;

    final tipo = d['tipo']?.toString() ?? '';
    if (tipo != 'cliente') return true;

    if (_empty(d['nome']) || _empty(d['email']) || _empty(d['telefone'])) {
      return false;
    }
    final end = d['endereco'] as Map<String, dynamic>?;
    if (end == null) return false;
    if (_empty(end['cep']) ||
        _empty(end['rua']) ||
        _empty(end['numero']) ||
        _empty(end['cidade'])) {
      return false;
    }
    return true;
  }

  static bool _empty(dynamic v) => v == null || v.toString().trim().isEmpty;
}
