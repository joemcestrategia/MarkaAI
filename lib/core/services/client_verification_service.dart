import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class ClientVerificationService {
  static String _normalize(String text) {
    return text
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c');
  }

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
        final cleanClass = _normalize(classification);
        return {
          'isVip': cleanClass == 'vip' || cleanClass == 'fiel',
          'isSumido': cleanClass == 'sumido',
          'isProblematic': cleanClass == 'problematico',
          'isNovo': cleanClass == 'novo',
          'isTrusted': cleanClass == 'vip' || cleanClass == 'fiel' || cleanClass == 'novo'
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
        'isProblematic': _normalize(classification ?? '') == 'problematico',
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
  /// Agora verifica também pelo hash de e-mail e telefone para evitar abusos com múltiplas contas.
  static Future<bool> hasUsedBirthdayDiscountInYear(
      String userId, String shopId) async {
    try {
      final now = DateTime.now();
      final currentYear = now.year.toString();

      // 1. Verificação básica por ID de usuário nos agendamentos (rápida)
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

      if (query.docs.isNotEmpty) return true;

      // 2. Verificação avançada no registro da loja por email/telefone (prevenção de multi-conta)
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final userData = userDoc.data();
      final email = (userData?['email'] ?? '').toString().toLowerCase().trim();
      final phone = (userData?['telefone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

      if (email.isNotEmpty) {
        final registryEmail = await FirebaseFirestore.instance
            .collection('shops')
            .doc(shopId)
            .collection('birthday_discount_registry')
            .doc('email_$email')
            .get();
        if (registryEmail.exists && registryEmail.data()?['year'].toString() == currentYear) {
          return true;
        }
      }

      if (phone.isNotEmpty) {
        final registryPhone = await FirebaseFirestore.instance
            .collection('shops')
            .doc(shopId)
            .collection('birthday_discount_registry')
            .doc('phone_$phone')
            .get();
        if (registryPhone.exists && registryPhone.data()?['year'].toString() == currentYear) {
          return true;
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Registra o uso do desconto de aniversário para evitar reuso no mesmo ano.
  /// Trava também a data de nascimento globalmente no perfil do usuário.
  static Future<void> registerBirthdayDiscountUsage(
      String userId, String shopId) async {
    try {
      final now = DateTime.now();
      final currentYear = now.year.toString();
      
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final userData = userDoc.data();
      final email = (userData?['email'] ?? '').toString().toLowerCase().trim();
      final phone = (userData?['telefone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

      final batch = FirebaseFirestore.instance.batch();

      // 1. Registro no documento do usuário (Trava Global)
      batch.update(FirebaseFirestore.instance.collection('users').doc(userId), {
        'birthday_locked': true,
        'last_birthday_discount_year': currentYear,
      });

      // 2. Registro na loja por e-mail
      if (email.isNotEmpty) {
        batch.set(
          FirebaseFirestore.instance
              .collection('shops')
              .doc(shopId)
              .collection('birthday_discount_registry')
              .doc('email_$email'),
          {'year': currentYear, 'used_at': FieldValue.serverTimestamp(), 'userId': userId},
        );
      }

      // 3. Registro na loja por telefone
      if (phone.isNotEmpty) {
        batch.set(
          FirebaseFirestore.instance
              .collection('shops')
              .doc(shopId)
              .collection('birthday_discount_registry')
              .doc('phone_$phone'),
          {'year': currentYear, 'used_at': FieldValue.serverTimestamp(), 'userId': userId},
        );
      }

      await batch.commit();
    } catch (e) {
      debugPrint('Erro ao registrar uso de desconto de aniversário: $e');
    }
  }

  /// Verifica se o mês alvo (ou atual) é o mês de aniversário do cliente.
  static Future<bool> isBirthdayMonth(String userId, {int? targetMonth}) async {
    debugPrint('🎂 DEBUG isBirthdayMonth Entry: userId=$userId, targetMonth=$targetMonth');
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (!userDoc.exists) {
        debugPrint('   - USER DOC NOT FOUND in /users/$userId');
        return false;
      }

      final userData = userDoc.data();
      final birthData = userData?['aniversario'] ??
          userData?['data_nascimento'] ??
          userData?['nascimento'] ??
          userData?['birthDate'];

      debugPrint('🎂 DEBUG isBirthdayMonth Trace:');
      debugPrint('   - Raw birthData: $birthData (${birthData.runtimeType})');
      if (birthData == null) {
        debugPrint('   - birthData is NULL. Available fields: ${userData?.keys}');
        return false;
      }
      DateTime? birthDate;
      if (birthData is Timestamp) {
        birthDate = birthData.toDate();
      } else if (birthData is String) {
        final cleanData = birthData.trim();
        // Tenta vários formatos comuns
        try {
          birthDate = DateFormat('dd/MM/yyyy').parse(cleanData);
        } catch (_) {
          try {
            birthDate = DateFormat('yyyy-MM-dd').parse(cleanData);
          } catch (_) {
            try {
              birthDate = DateTime.parse(cleanData);
            } catch (_) {
               // Tenta formato ISO ou outros
               if (cleanData.contains('/')) {
                 final parts = cleanData.split('/');
                 if (parts.length == 3) {
                   if (parts[0].length == 4) { // yyyy/mm/dd
                      birthDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
                   } else if (parts[2].length == 4) { // dd/mm/yyyy
                      birthDate = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
                   }
                 }
               }
            }
          }
        }
      }

      debugPrint('   - Parsed birthDate: $birthDate');
      if (birthDate == null) return false;

      final compareMonth = targetMonth ?? DateTime.now().month;
      final match = birthDate.month == compareMonth;
      debugPrint('   - Month comparison: ${birthDate.month} == $compareMonth -> $match');
      return match;
    } catch (e) {
      return false;
    }
  }

  /// Auxiliar para carregar config da loja
  static Future<Map<String, dynamic>> getShopConfig(String shopId) async {
    try {
      final shopDoc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .get();
      return (shopDoc.data()?['config'] as Map<String, dynamic>?) ?? {};
    } catch (e) {
      return {};
    }
  }

  /// Verifica se um agendamento pode ser modificado (cancelado ou reagendado)
  /// baseado na política de cancelamento da loja.
  static Future<Map<String, dynamic>> canModifyAppointment(
      DocumentSnapshot appointment) async {
    try {
      final data = appointment.data() as Map<String, dynamic>;
      final shopId = data['shopId'] as String;
      final appointmentDate = (data['data_agendamento'] as Timestamp).toDate();
      final now = DateTime.now();

      // Se o agendamento já passou, não pode modificar
      if (appointmentDate.isBefore(now)) {
        return {'can': false, 'reason': 'Este agendamento já passou.'};
      }

      final config = await getShopConfig(shopId);
      final int cancelHours = config['tempo_cancelamento_horas'] ?? 2;

      final diff = appointmentDate.difference(now);
      if (diff.inHours < cancelHours) {
        return {
          'can': false,
          'reason':
              'Fora do prazo: a loja exige $cancelHours horas de antecedência para modificações.'
        };
      }

      return {'can': true};
    } catch (e) {
      return {'can': true}; // Fallback seguro se der erro na verificação
    }
  }
}
