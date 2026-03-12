import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ClientVerificationService {
  /// Retorna se o cliente é VIP, Fiel ou tem classificação manual de confiança.
  static Future<Map<String, bool>> getClientStatus(
      String userId, String shopId) async {
    try {
      // 1. Verificação de classificação e configuração da loja
      final shopDoc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .get();
      final shopConfig = (shopDoc.data()?['config'] as Map?) ?? {};

      final clientSettingDoc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .collection('clients')
          .doc(userId)
          .get();

      String? classification;
      bool hasOverride = false;

      if (clientSettingDoc.exists) {
        final data = clientSettingDoc.data();
        classification = data?['classification']?.toString().toLowerCase();
        hasOverride = data?['classificationOverride'] ?? false;
      }

      if (hasOverride && classification != null) {
        return {
          'isVip': classification == 'vip',
          'isSumido': classification == 'sumido',
          'isProblematic': classification == 'problematico',
          'isNovo': classification == 'novo',
          'isTrusted': classification == 'vip' || classification == 'novo'
        };
      }

      // 2. Cálculo de histórico (VIP automático e Sumido)
      final appointmentsSnap = await FirebaseFirestore.instance
          .collection('appointments')
          .where('shopId', isEqualTo: shopId)
          .where('clientId', isEqualTo: userId)
          .orderBy('data_agendamento', descending: true)
          .get();

      final validAppointments = appointmentsSnap.docs.where((doc) {
        final status = (doc.data()['status'] ?? '').toString().toLowerCase();
        return status != 'cancelado' &&
            status != 'recusado' &&
            status != 'excluido';
      }).toList();

      if (validAppointments.isEmpty) {
        return {
          'isVip': false,
          'isSumido': false,
          'isProblematic': classification == 'problematico',
          'isNovo': true, // Primeiro agendamento
          'isTrusted': true,
        };
      }

      final int visits = validAppointments.length;
      final DateTime lastVisit =
          (validAppointments.first.data()['data_agendamento'] as Timestamp)
              .toDate();
      final now = DateTime.now();

      // Thresholds da loja
      final int vipMinVisits = shopConfig['vip_min_visits'] ?? 15;
      final int sumidoMaxDays = shopConfig['sumido_max_days'] ?? 45;

      bool isSumido = now.difference(lastVisit).inDays > sumidoMaxDays;
      bool isVip = !isSumido && visits >= vipMinVisits;
      bool isNovo =
          !isSumido && visits == 1 && now.difference(lastVisit).inDays < 30;

      return {
        'isVip': isVip,
        'isSumido': isSumido,
        'isProblematic': classification == 'problematico',
        'isNovo': isNovo,
        'isTrusted': !isSumido && (isVip || isNovo || visits > 1)
      };
    } catch (e) {
      return {
        'isVip': false,
        'isSumido': false,
        'isProblematic': false,
        'isNovo': false,
        'isTrusted': true
      };
    }
  }

  /// Verifica se o cliente já usou o desconto de aniversário neste ano nesta loja.
  static Future<bool> hasUsedBirthdayDiscountInYear(
      String userId, String shopId) async {
    try {
      final now = DateTime.now();
      final startOfYear = DateTime(now.year, 1, 1);
      final endOfYear = DateTime(now.year, 12, 31, 23, 59, 59);

      final query = await FirebaseFirestore.instance
          .collection('appointments')
          .where('shopId', isEqualTo: shopId)
          .where('clientId', isEqualTo: userId)
          .where('birthday_discount_applied', isEqualTo: true)
          .where('data_agendamento',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfYear))
          .where('data_agendamento',
              isLessThanOrEqualTo: Timestamp.fromDate(endOfYear))
          .limit(1)
          .get();

      return query.docs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Verifica se o mês atual é o mês de aniversário do cliente.
  static Future<bool> isBirthdayMonth(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (!userDoc.exists) return false;

      final userData = userDoc.data();
      final birthData = userData?['data_nascimento'] ??
          userData?['nascimento'] ??
          userData?['birthDate'];

      if (birthData == null) return false;

      DateTime? birthDate;
      if (birthData is Timestamp) {
        birthDate = birthData.toDate();
      } else if (birthData is String) {
        // Tenta vários formatos comuns
        try {
          birthDate = DateFormat('dd/MM/yyyy').parse(birthData);
        } catch (_) {
          try {
            birthDate = DateFormat('yyyy-MM-dd').parse(birthData);
          } catch (_) {
            try {
              birthDate = DateTime.parse(birthData);
            } catch (_) {}
          }
        }
      }

      if (birthDate == null) return false;

      final now = DateTime.now();
      return birthDate.month == now.month;
    } catch (e) {
      return false;
    }
  }
}
