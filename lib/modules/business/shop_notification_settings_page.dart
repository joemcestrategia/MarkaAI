import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_colors.dart';

class ShopNotificationSettingsPage extends StatefulWidget {
  const ShopNotificationSettingsPage({super.key});

  @override
  State<ShopNotificationSettingsPage> createState() =>
      _ShopNotificationSettingsPageState();
}

class _ShopNotificationSettingsPageState
    extends State<ShopNotificationSettingsPage> {
  bool _loading = true;
  bool _sendReminders = true;
  int _defaultReminderDays = 3;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final shopId = await SessionService.getShopId();
    if (shopId == null || shopId.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    final data = await Supabase.instance.client
        .from('shops')
        .select('notification_settings')
        .eq('id', shopId)
        .maybeSingle();

    if (data != null) {
      final settings = data['notification_settings'] as Map<String, dynamic>?;
      setState(() {
        _sendReminders = settings?['send_reminders'] ?? true;
        _defaultReminderDays = settings?['default_reminder_days'] ?? 3;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    final shopId = await SessionService.getShopId();
    if (shopId == null || shopId.isEmpty) return;

    setState(() => _loading = true);
    try {
      final currentShop = await Supabase.instance.client
          .from('shops')
          .select('config')
          .eq('id', shopId)
          .single();
          
      Map<String, dynamic> config = Map<String, dynamic>.from(currentShop['config'] ?? {});
      config['notificar_cliente_agendamento'] = _sendReminders;
      config['notificar_dias_antes'] = _defaultReminderDays;

      await Supabase.instance.client.from('shops').update({
        'notification_settings': {
          'send_reminders': _sendReminders,
          'default_reminder_days': _defaultReminderDays,
          'email_template': 'default',
        },
        'config': config,
      }).eq('id', shopId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configurações salvas!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações da Loja'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Enviar Lembretes aos Clientes'),
              value: _sendReminders,
              onChanged: (v) => setState(() => _sendReminders = v),
              activeColor: AppColors.primaryPurple,
            ),
            const SizedBox(height: 16),
            Text('Lembrete padrão (dias antes): $_defaultReminderDays'),
            Slider(
              value: _defaultReminderDays.toDouble(),
              min: 1,
              max: 7,
              divisions: 6,
              label: '$_defaultReminderDays dias',
              activeColor: AppColors.primaryPurple,
              onChanged: (v) =>
                  setState(() => _defaultReminderDays = v.round()),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save),
                label: const Text('Salvar Configurações'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
