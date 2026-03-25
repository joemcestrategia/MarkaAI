import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class ClientVerificationService {
  static final _supabase = Supabase.instance.client;



  /// Retorna se o cliente é VIP, Fiel ou tem classificação manual de confiança.
  static Future<Map<String, bool>> getClientStatus(
      String userId, String shopId) async {
    try {
      // 1. Verificação de classificação e configuração da loja
      final shopDoc = await _supabase
          .from('shops')
          .select('config')
          .eq('id', shopId)
          .maybeSingle();
      
      final shopConfig = (shopDoc?['config'] as Map?) ?? {};

      // 2. Cálculo de histórico (VIP automático e Sumido)
      final appointmentsList = await _supabase
          .from('appointments')
          .select()
          .eq('shop_id', shopId)
          .eq('client_id', userId)
          .order('scheduled_at', ascending: false);

      final validAppointments = appointmentsList.where((appt) {
        final status = (appt['status'] ?? '').toString().toLowerCase();
        return status != 'cancelado' &&
            status != 'recusado' &&
            status != 'excluido';
      }).toList();

      if (validAppointments.isEmpty) {
        return {
          'isVip': false,
          'isSumido': false,
          'isProblematic': false,
          'isNovo': true, // Primeiro agendamento
          'isTrusted': true,
        };
      }

      final int visits = validAppointments.length;
      final DateTime lastVisit = DateTime.parse(validAppointments.first['scheduled_at']);
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
        'isProblematic': false,
        'isNovo': isNovo,
        'isTrusted': !isSumido && (isVip || isNovo || visits > 1)
      };
    } catch (e) {
      debugPrint('Error in getClientStatus: $e');
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
      final currentYear = now.year;

      // 1. Verificação básica por ID de usuário nos agendamentos
      final startOfYear = DateTime(now.year, 1, 1).toIso8601String();
      final endOfYear = DateTime(now.year, 12, 31, 23, 59, 59).toIso8601String();

      final appointments = await _supabase
          .from('appointments')
          .select()
          .eq('shop_id', shopId)
          .eq('client_id', userId)
          .eq('birthday_discount_applied', true)
          .gte('scheduled_at', startOfYear)
          .lte('scheduled_at', endOfYear);

      if (appointments.isNotEmpty) return true;

      // 2. Verificação avançada no registro da loja por email/telefone (prevenção de multi-conta)
      final userDoc = await _supabase
          .from('users')
          .select('email, telefone')
          .eq('id', userId)
          .maybeSingle();
      
      if (userDoc == null) return false;

      final email = (userDoc['email'] ?? '').toString().toLowerCase().trim();
      final phone = (userDoc['telefone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

      if (email.isNotEmpty) {
        final registryEmail = await _supabase
            .from('birthday_discount_registry')
            .select()
            .eq('shop_id', shopId)
            .eq('identifier', 'email_$email')
            .eq('year', currentYear)
            .maybeSingle();
        if (registryEmail != null) return true;
      }

      if (phone.isNotEmpty) {
        final registryPhone = await _supabase
            .from('birthday_discount_registry')
            .select()
            .eq('shop_id', shopId)
            .eq('identifier', 'phone_$phone')
            .eq('year', currentYear)
            .maybeSingle();
        if (registryPhone != null) return true;
      }

      return false;
    } catch (e) {
      debugPrint('Error in hasUsedBirthdayDiscountInYear: $e');
      return false;
    }
  }

  /// Registra o uso do desconto de aniversário.
  static Future<void> registerBirthdayDiscountUsage(
      String userId, String shopId) async {
    try {
      final now = DateTime.now();
      final currentYear = now.year;
      
      final userDoc = await _supabase
          .from('users')
          .select('email, telefone')
          .eq('id', userId)
          .maybeSingle();
      
      if (userDoc == null) return;

      final email = (userDoc['email'] ?? '').toString().toLowerCase().trim();
      final phone = (userDoc['telefone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

      // 1. Registro no documento do usuário (Trava Global)
      await _supabase.from('users').update({
        'birthday_locked': true,
        'last_birthday_discount_year': currentYear,
      }).eq('id', userId);

      // 2. Registros na loja para evitar multi-conta
      final List<Map<String, dynamic>> registros = [];
      if (email.isNotEmpty) {
        registros.add({
          'shopId': shopId,
          'identifier': 'email_$email',
          'year': currentYear,
          'user_id': userId,
          'used_at': now.toIso8601String(),
        });
      }
      if (phone.isNotEmpty) {
        registros.add({
          'shopId': shopId,
          'identifier': 'phone_$phone',
          'year': currentYear,
          'user_id': userId,
          'used_at': now.toIso8601String(),
        });
      }

      if (registros.isNotEmpty) {
        await _supabase.from('birthday_discount_registry').upsert(registros);
      }
    } catch (e) {
      debugPrint('Erro ao registrar uso de desconto de aniversário: $e');
    }
  }

  /// Verifica se o mês alvo (ou atual) é o mês de aniversário do cliente.
  static Future<bool> isBirthdayMonth(String userId, {int? targetMonth}) async {
    try {
      final userDoc = await _supabase
          .from('users')
          .select('aniversario, data_nascimento, nascimento, birthDate')
          .eq('id', userId)
          .maybeSingle();
      
      if (userDoc == null) return false;

      final birthData = userDoc['aniversario'] ??
          userDoc['data_nascimento'] ??
          userDoc['nascimento'] ??
          userDoc['birthDate'];

      if (birthData == null) return false;

      DateTime? birthDate;
      if (birthData is String) {
        final cleanData = birthData.trim();
        try {
          birthDate = DateTime.tryParse(cleanData);
          if (birthDate == null) {
            // Tenta formatos comuns se o parse simples falhar
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
        } catch (_) {}
      } else if (birthData is DateTime) {
        birthDate = birthData;
      }

      if (birthDate == null) return false;

      final compareMonth = targetMonth ?? DateTime.now().month;
      return birthDate.month == compareMonth;
    } catch (e) {
      debugPrint('Error in isBirthdayMonth: $e');
      return false;
    }
  }

  /// Auxiliar para carregar config da loja
  static Future<Map<String, dynamic>> getShopConfig(String shopId) async {
    try {
      final shopDoc = await _supabase
          .from('shops')
          .select('config')
          .eq('id', shopId)
          .maybeSingle();
      return (shopDoc?['config'] as Map<String, dynamic>?) ?? {};
    } catch (e) {
      return {};
    }
  }

  /// Verifica se um agendamento pode ser modificado (cancelado ou reagendado)
  static Future<Map<String, dynamic>> canModifyAppointment(
      Map<String, dynamic> appointment) async {
    try {
      final shopId = (appointment['shop_id'] ?? appointment['shopId']) as String;
      final appointmentDate = DateTime.parse(appointment['scheduled_at']);
      final now = DateTime.now();

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
      return {'can': true};
    }
  }
}
