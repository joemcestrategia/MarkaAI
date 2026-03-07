import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Inicializa o serviço de notificações
  static Future<void> initialize() async {
    // Solicitar permissão (especialmente importante no iOS)
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint(
        'ðŸ”” Permissão de notificação: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('âœ… Usuário aceitou notificações');

      // Obter token FCM
      String? token = await _messaging.getToken();
      if (token != null) {
        debugPrint('ðŸ”‘ FCM Token obtido: ${token.substring(0, 20)}...');
        await _saveTokenToFirestore(token);
      }

      // Escutar quando o token for atualizado
      _messaging.onTokenRefresh.listen(_saveTokenToFirestore);

      // Configurar handlers de notificações
      _setupMessageHandlers();
    } else {
      debugPrint('âŒ Usuário negou permissão de notificações');
    }
  }

  /// Salva o token FCM no Firestore
  static Future<void> _saveTokenToFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Buscar o documento do usuário para ver se é dono de loja
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) return;

      final userData = userDoc.data()!;
      final shopId = userData['shopId'];

      // Se é dono de loja (tem shopId), salvar token na loja
      if (shopId != null && shopId.toString().isNotEmpty) {
        await FirebaseFirestore.instance.collection('shops').doc(shopId).set({
          'fcm_tokens': FieldValue.arrayUnion([token]),
          'fcm_updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        debugPrint('âœ… Token FCM salvo na loja: $shopId');
      }

      // Também salvar no documento do usuário
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcm_token': token,
        'fcm_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('âœ… Token FCM salvo no usuário: ${user.uid}');
    } catch (e) {
      debugPrint('âŒ Erro ao salvar token FCM: $e');
    }
  }

  /// Configura os handlers de mensagens
  static void _setupMessageHandlers() {
    // Mensagem quando o app está em foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('ðŸ“© Notificação recebida (foreground):');
      debugPrint('   Título: ${message.notification?.title}');
      debugPrint('   Corpo: ${message.notification?.body}');
      debugPrint('   Dados: ${message.data}');

      // Aqui você pode mostrar um dialog ou snackbar local
      // se quiser exibir a notificação mesmo com o app aberto
    });

    // Mensagem quando o usuário clica na notificação (app estava fechado)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('ðŸ“± App aberto via notificação:');
      debugPrint('   Dados: ${message.data}');

      // Aqui você pode navegar para uma página específica
      // baseado nos dados da notificação
      _handleNotificationTap(message.data);
    });

    // Verificar se o app foi aberto por uma notificação
    _messaging.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('ðŸš€ App iniciado via notificação:');
        debugPrint('   Dados: ${message.data}');
        _handleNotificationTap(message.data);
      }
    });
  }

  /// Processa o clique na notificação
  static void _handleNotificationTap(Map<String, dynamic> data) {
    // Aqui você pode implementar navegação baseada no tipo de notificação
    final type = data['type'];
    final id = data['id'];

    debugPrint('ðŸŽ¯ Notificação clicada - Tipo: $type, ID: $id');

    // Exemplo:
    // if (type == 'new_appointment') {
    //   Navigator.pushNamed(context, '/appointment-details', arguments: id);
    // }
  }

  /// Remove o token FCM ao fazer logout
  static Future<void> removeToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      String? token = await _messaging.getToken();
      if (token == null) return;

      // Buscar shopId do usuário
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final shopId = userDoc.data()?['shopId'];

        // Remover token da loja
        if (shopId != null) {
          await FirebaseFirestore.instance
              .collection('shops')
              .doc(shopId)
              .update({
            'fcm_tokens': FieldValue.arrayRemove([token]),
          });
        }
      }

      // Remover token do usuário
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'fcm_token': FieldValue.delete(),
      });

      // Deletar token do FCM
      await _messaging.deleteToken();

      debugPrint('ðŸ—‘ï¸ Token FCM removido');
    } catch (e) {
      debugPrint('âŒ Erro ao remover token FCM: $e');
    }
  }

  /// Subscrever a um tópico
  static Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      debugPrint('âœ… Inscrito no tópico: $topic');
    } catch (e) {
      debugPrint('âŒ Erro ao se inscrever no tópico $topic: $e');
    }
  }

  /// Cancelar inscrição de um tópico
  static Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      debugPrint('âœ… Desinscrição do tópico: $topic');
    } catch (e) {
      debugPrint('âŒ Erro ao se desinscrever do tópico $topic: $e');
    }
  }
}

/// Handler para mensagens em background
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('ðŸ“¬ Notificação recebida em background:');
  debugPrint('   Título: ${message.notification?.title}');
  debugPrint('   Corpo: ${message.notification?.body}');
  debugPrint('   Dados: ${message.data}');
}
