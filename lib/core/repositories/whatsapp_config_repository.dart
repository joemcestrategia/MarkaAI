import 'package:supabase_flutter/supabase_flutter.dart';

class ShopWhatsappConfig {
  final String id;
  final String shopId;
  final String waPhoneNumberId;
  final String? waBusinessAccountId;
  final String waAccessToken;
  final String waWebhookVerifyToken;
  final String? waTemplateConfirmedName;
  final String? waTemplateReminderName;
  final bool isActive;

  ShopWhatsappConfig({
    required this.id,
    required this.shopId,
    required this.waPhoneNumberId,
    this.waBusinessAccountId,
    required this.waAccessToken,
    required this.waWebhookVerifyToken,
    this.waTemplateConfirmedName,
    this.waTemplateReminderName,
    this.isActive = false,
  });

  factory ShopWhatsappConfig.fromMap(Map<String, dynamic> map) {
    return ShopWhatsappConfig(
      id: map['id'],
      shopId: map['shop_id'],
      waPhoneNumberId: map['wa_phone_number_id'],
      waBusinessAccountId: map['wa_business_account_id'],
      waAccessToken: map['wa_access_token'],
      waWebhookVerifyToken: map['wa_webhook_verify_token'],
      waTemplateConfirmedName: map['wa_template_confirmed_name'],
      waTemplateReminderName: map['wa_template_reminder_name'],
      isActive: map['is_active'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'shop_id': shopId,
      'wa_phone_number_id': waPhoneNumberId,
      'wa_business_account_id': waBusinessAccountId,
      'wa_access_token': waAccessToken,
      'wa_webhook_verify_token': waWebhookVerifyToken,
      'wa_template_confirmed_name': waTemplateConfirmedName,
      'wa_template_reminder_name': waTemplateReminderName,
      'is_active': isActive,
    };
  }
}

class WhatsappConfigRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<ShopWhatsappConfig?> getConfig(String shopId) async {
    final response = await _supabase
        .from('shop_whatsapp_config')
        .select()
        .eq('shop_id', shopId)
        .maybeSingle();

    if (response != null) {
      return ShopWhatsappConfig.fromMap(response);
    }
    return null;
  }

  Future<void> saveConfig(ShopWhatsappConfig config) async {
    await _supabase.from('shop_whatsapp_config').upsert(
      config.toMap(),
      onConflict: 'shop_id',
    );
  }

  Future<bool> testConnection(String phoneNumberId, String accessToken) async {
    try {
      final response = await _supabase.functions.invoke(
        'whatsapp-send',
        body: {
          'action': 'test',
          'phone_number_id': phoneNumberId,
          'access_token': accessToken,
        },
      );
      
      return response.status == 200 && response.data['success'] == true;
    } catch (e) {
      print('Erro ao testar conexão: $e');
      return false;
    }
  }
}
