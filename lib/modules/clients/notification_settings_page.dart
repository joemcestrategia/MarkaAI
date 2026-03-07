import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();

    if (userDoc.exists) {
      final data = userDoc.data();
      final prefs = data?['notification_preferences'] as Map<String, dynamic>?;

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
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'notification_preferences': {
          'email_enabled': _emailEnabled,
          'push_enabled': _pushEnabled,
          'reminder_days_before': _reminderDays,
        }
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preferências salvas!')),
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
              onPressed: _savePreferences,
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
                    'Lembretes de Agendamentos',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Configure como deseja receber lembretes dos seus agendamentos',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 32),

                  // Email Toggle
                  Card(
                    child: SwitchListTile(
                      value: _emailEnabled,
                      onChanged: (value) {
                        setState(() => _emailEnabled = value);
                      },
                      title: const Text('Email'),
                      subtitle: const Text('Receber lembretes por email'),
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.email, color: Colors.blue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Push Toggle
                  Card(
                    child: SwitchListTile(
                      value: _pushEnabled,
                      onChanged: (value) {
                        setState(() => _pushEnabled = value);
                      },
                      title: const Text('Notificações Push'),
                      subtitle: const Text('Receber lembretes no celular'),
                      secondary: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryPurple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.notifications,
                            color: AppColors.primaryPurple),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Reminder Days Selector
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
                                      'Antecedência do Lembrete',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Quantos dias antes do agendamento',
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
                                  selected: {_reminderDays},
                                  onSelectionChanged: (Set<int> selection) {
                                    setState(() {
                                      _reminderDays = selection.first;
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

                  const SizedBox(height: 32),

                  // Info Box
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Como funciona?',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[900],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Você receberá um lembrete automático $_reminderDays ${_reminderDays == 1 ? 'dia' : 'dias'} antes de cada agendamento, conforme suas preferências.',
                                style: TextStyle(
                                  color: Colors.blue[900],
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
