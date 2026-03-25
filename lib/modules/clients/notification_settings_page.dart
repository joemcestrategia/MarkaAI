import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/session_service.dart';
import '../../core/theme/app_colors.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _loading = true;
  bool _emailEnabled = true;
  bool _pushEnabled = true;
  int _reminderDays = 3;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final userId = await SessionService.getUserId();
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }

    final data = await Supabase.instance.client
        .from('users')
        .select('notification_preferences')
        .eq('id', userId)
        .maybeSingle();

    if (data != null) {
      final prefs = data['notification_preferences'] as Map<String, dynamic>?;
      setState(() {
        _emailEnabled = prefs?['email_enabled'] ?? true;
        _pushEnabled = prefs?['push_enabled'] ?? true;
        _reminderDays = prefs?['reminder_days_before'] ?? 3;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _savePreferences() async {
    final userId = await SessionService.getUserId();
    if (userId == null) return;

    setState(() => _loading = true);
    try {
      await Supabase.instance.client.from('users').update({
        'notification_preferences': {
          'email_enabled': _emailEnabled,
          'push_enabled': _pushEnabled,
          'reminder_days_before': _reminderDays,
        }
      }).eq('id', userId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preferências salvas!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
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
        title: const Text('Preferências de Notificação'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Notificações por E-mail'),
              value: _emailEnabled,
              onChanged: (v) => setState(() => _emailEnabled = v),
              activeColor: AppColors.primaryPurple,
            ),
            SwitchListTile(
              title: const Text('Notificações Push'),
              value: _pushEnabled,
              onChanged: (v) => setState(() => _pushEnabled = v),
              activeColor: AppColors.primaryPurple,
            ),
            const SizedBox(height: 16),
            Text('Lembrete (dias antes): $_reminderDays'),
            Slider(
              value: _reminderDays.toDouble(),
              min: 1,
              max: 7,
              divisions: 6,
              label: '$_reminderDays dias',
              activeColor: AppColors.primaryPurple,
              onChanged: (v) => setState(() => _reminderDays = v.round()),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _savePreferences,
                icon: const Icon(Icons.save),
                label: const Text('Salvar Preferências'),
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
