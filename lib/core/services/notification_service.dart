import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:flutter/foundation.dart';

class NotificationService {
  /// Inicializa o serviço de notificações (Refatorado: FCM Removido)
  static Future<void> initialize() async {
    debugPrint('🔔 NotificationService: Inicializado (Push via Supabase pronto)');
  }

  /// Retorna o token de notificação (Stub: FCM desativado)
  static Future<String?> getToken() async => null;

  /// Registra o token do usuário no Supabase
  static Future<void> registerToken(String userId) async {
    // No-op ou implementação futura de Realtime push
    debugPrint('ℹ️ registerToken chamado para: $userId (Push desativado)');
  }

  /// Salva o token de notificação no Supabase
  static Future<void> _saveTokenToFirestore(String token) async {
    final supabase = sb.Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Buscar o documento do usuário para ver se é dono de loja
      final userData = await supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (userData == null) return;

      final shopId = userData['shop_id'] ?? userData['shopId'];

      // Se é dono de loja (tem shopId), salvar token na loja
      if (shopId != null && shopId.toString().isNotEmpty) {
        await supabase.from('shops').update({
          'fcm_token': token,
          'fcm_updated_at': DateTime.now().toIso8601String(),
        }).eq('id', shopId);

        debugPrint('✅ Token FCM salvo na loja: $shopId');
      }

      // Também salvar no documento do usuário
      await supabase.from('users').update({
        'fcm_token': token,
        'fcm_updated_at': DateTime.now().toIso8601String(),
      }).eq('id', user.id);

      debugPrint('✅ Token FCM salvo no usuário: ${user.id}');
    } catch (e) {
      debugPrint('❌ Erro ao salvar token FCM: $e');
    }
  }

  /// Processa o clique na notificação
  static void _handleNotificationTap(Map<String, dynamic> data) {
    debugPrint('🎯 Notificação clicada - Dados: $data');
  }

  /// Remove o token FCM ao fazer logout
  static Future<void> removeToken() async {
    final supabase = sb.Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Buscar shopId do usuário
      final userData = await supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (userData != null) {
        final shopId = userData['shop_id'] ?? userData['shopId'];

        // Remover token da loja
        if (shopId != null) {
          await supabase.from('shops').update({
            'fcm_token': null,
          }).eq('id', shopId);
        }
      }

      // Remover token do usuário
      await supabase.from('users').update({
        'fcm_token': null,
      }).eq('id', user.id);

      debugPrint('🗑️ Token de notificação removido das tabelas Supabase');
    } catch (e) {
      debugPrint('❌ Erro ao remover token: $e');
    }
  }

  static Future<void> subscribeToTopic(String topic) async {}
  static Future<void> unsubscribeFromTopic(String topic) async {}
}
