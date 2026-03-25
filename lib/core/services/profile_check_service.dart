import 'package:supabase_flutter/supabase_flutter.dart';

/// Verifica se o perfil do cliente está completo para permitir agendamento.
class ProfileCheckService {
  /// Campos obrigatórios para cliente: nome, email, telefone, tipo, endereço (cep, rua, numero, cidade).
  static Future<bool> isClientProfileComplete(String uid) async {
    try {
      final doc = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', uid)
          .maybeSingle();
          
      if (doc == null) return false;

      final tipo = doc['role']?.toString() ?? '';
      if (tipo != 'cliente') return true;

      // Para clientes, apenas nome e email são obrigatórios agora.
      // O telefone é coletado no cadastro mas não impedimos o agendamento se estiver ausente por algum motivo.
      if (_empty(doc['name']) || _empty(doc['email'])) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  static bool _empty(dynamic v) => v == null || v.toString().trim().isEmpty;
}
