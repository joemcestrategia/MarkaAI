import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

    final shopDoc =
        await FirebaseFirestore.instance.collection('shops').doc(shopId).get();

    if (shopDoc.exists) {
      final data = shopDoc.data();
      final settings = data?['notification_settings'] as Map<String, dynamic>?;

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
      await FirebaseFirestore.instance.collection('shops').doc(shopId).set({
        'notification_settings': {
          'send_reminders': _sendReminders,
          'default_reminder_days': _defaultReminderDays,
          'email_template': 'default',
        }
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configurações salvas!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveSettings,
              tooltip: 'Salvar',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  const Text(
                    'Lembretes Automáticos',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Configure como seus clientes receberão lembretes de agendamentos',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 32),

                  // Enable/Disable Reminders
                  Card(
                    child: SwitchListTile(
                      value: _sendReminders,
                      onChanged: (value) {
                        setState(() => _sendReminders = value);
                      },
                      title: const Text('Ativar Lembretes Automáticos'),
                      subtitle: const Text(
                          'Enviar lembretes para clientes antes dos agendamentos'),
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryPurple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.notifications_active,
                            color: AppColors.primaryPurple),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Default Days Setting
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.schedule,
                                    color: Colors.orange),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Antecedência Padrão',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Dias antes para enviar o lembrete',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: SegmentedButton<int>(
                                  segments: const [
                                    ButtonSegment(
                                        value: 1, label: Text('1 dia')),
                                    ButtonSegment(
                                        value: 2, label: Text('2 dias')),
                                    ButtonSegment(
                                        value: 3, label: Text('3 dias')),
                                    ButtonSegment(
                                        value: 7, label: Text('7 dias')),
                                  ],
                                  selected: {_defaultReminderDays},
                                  onSelectionChanged: (Set<int> selection) {
                                    setState(() {
                                      _defaultReminderDays = selection.first;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Preview Card
                  if (_sendReminders)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.check_circle, color: Colors.green[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Lembretes Ativos',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[900],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Seus clientes receberão lembretes $_defaultReminderDays ${_defaultReminderDays == 1 ? 'dia' : 'dias'} antes dos agendamentos por email e notificação push.',
                                  style: TextStyle(
                                    color: Colors.green[900],
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (!_sendReminders)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange[200]!),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange[700]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Lembretes Desativados',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange[900],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Seus clientes não receberão lembretes automáticos. Ative para melhorar a taxa de comparecimento.',
                                  style: TextStyle(
                                    color: Colors.orange[900],
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 32),

                  // Save Button
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
