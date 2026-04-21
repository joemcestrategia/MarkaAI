import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:flutter/foundation.dart';
import '_web_push.dart' if (dart.library.io) '_web_push_stub.dart';

import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';

// VAPID public key – NOT secret, safe to embed.
// Generate with: npx web-push generate-vapid-keys
// Then set VAPID_PUBLIC_KEY and VAPID_PRIVATE_KEY as Supabase secrets.
// Pass the public key at build time:
//   flutter build web --dart-define=VAPID_PUBLIC_KEY=<your_key>
const _kVapidPublicKey =
    String.fromEnvironment('VAPID_PUBLIC_KEY', defaultValue: '');

class NotificationService {
  static Future<void> initialize() async {
    debugPrint('🔔 NotificationService: Inicializado');
    if (kIsWeb) {
      await _tryRegisterExistingSubscription();
    }
  }

  static Future<String?> getToken() async {
    try {
      if (kIsWeb) {
        // Na web poderíamos obter o VAPID token via FCM da mesma forma se configurassemos Firebase na web
        // Mas como mantém-se o Web Push VAPID, deixamos retornar null e contar com push_subscriptions
        return null; 
      }
      // Mobile nativo — FCM
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        final token = await messaging.getToken();
        debugPrint('[FCM_TOKEN] Token obtido: $token');
        return token;
      }
      debugPrint('[FCM_TOKEN] Permissão negada pelo usuário');
      return null;
    } catch (e) {
      debugPrint('[FCM_TOKEN] Erro ao obter token: $e');
      return null;
    }
  }

  static Future<void> registerToken(String userId) async {
    debugPrint('ℹ️ registerToken: $userId');
  }

  // ── Web Push ──────────────────────────────────────────────────────────────

  /// Solicita permissão de notificação e salva a subscription no Supabase.
  /// Chame isto quando o usuário fizer login ou quando quiser ativar push.
  static Future<bool> requestWebPushPermission() async {
    if (!kIsWeb || _kVapidPublicKey.isEmpty) return false;
    try {
      final subJson = await subscribeWebPush(_kVapidPublicKey);
      if (subJson == null) return false;
      await _saveSubscription(subJson);
      debugPrint('✅ Web Push subscription salva');
      return true;
    } catch (e) {
      debugPrint('❌ requestWebPushPermission: $e');
      return false;
    }
  }

  /// Tenta re-registrar uma subscription existente (sem pedir permissão extra).
  static Future<void> _tryRegisterExistingSubscription() async {
    if (_kVapidPublicKey.isEmpty) return;
    try {
      final subJson = await subscribeWebPush(_kVapidPublicKey);
      if (subJson != null) await _saveSubscription(subJson);
    } catch (_) {}
  }

  /// Salva a subscription na tabela push_subscriptions do Supabase.
  static Future<void> _saveSubscription(String subJson) async {
    final supabase = sb.Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final sub = json.decode(subJson) as Map<String, dynamic>;
    final endpoint = sub['endpoint'] as String?;
    final keys = sub['keys'] as Map<String, dynamic>?;
    final p256dh = keys?['p256dh'] as String?;
    final auth = keys?['auth'] as String?;

    if (endpoint == null || p256dh == null || auth == null) return;

    await supabase.from('push_subscriptions').upsert({
      'user_id': user.id,
      'endpoint': endpoint,
      'p256dh': p256dh,
      'auth_key': auth,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id, endpoint');
  }

  /// Remove subscription ao fazer logout.
  static Future<void> removeToken() async {
    if (kIsWeb) {
      try {
        await unsubscribeWebPush();
      } catch (_) {}
    }
    final supabase = sb.Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      await supabase
          .from('push_subscriptions')
          .delete()
          .eq('user_id', user.id);
      debugPrint('🗑️ Push subscriptions removidas para ${user.id}');
    } catch (e) {
      debugPrint('❌ removeToken: $e');
    }
  }

  static Future<void> subscribeToTopic(String topic) async {}
  static Future<void> unsubscribeFromTopic(String topic) async {}
}
