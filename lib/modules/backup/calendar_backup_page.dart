import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/google_calendar_service.dart';

/// Página para gerenciar backup automático no Google Calendar
class CalendarBackupPage extends StatefulWidget {
  final bool isOwner; // true para dono da loja, false para funcionário
  final String? shopId;
  final String? employeeId;

  const CalendarBackupPage({
    super.key,
    this.isOwner = false,
    this.shopId,
    this.employeeId,
  });

  @override
  State<CalendarBackupPage> createState() => _CalendarBackupPageState();
}

class _CalendarBackupPageState extends State<CalendarBackupPage> {
  bool _isConnected = false;
  bool _isLoading = true;
  bool _isSyncing = false;
  Map<String, dynamic>? _calendarData;
  int _totalAppointments = 0;
  int _syncedAppointments = 0;
  String? _shopName;

  @override
  void initState() {
    super.initState();
    _loadCalendarStatus();
  }

  Future<void> _loadCalendarStatus() async {
    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user != null) {
        final doc = await supabase
            .from('users')
            .select('google_calendar')
            .eq('id', user.id)
            .maybeSingle();

        if (mounted && doc != null) {
          setState(() {
            _calendarData = doc['google_calendar'] as Map<String, dynamic>?;
            _isConnected = _calendarData?['connected'] == true;
          });
        }
      }

      // Busca nome da loja e contagem de agendamentos
      if (widget.isOwner && widget.shopId != null) {
        final shopDoc = await supabase
            .from('shops')
            .select('name')
            .eq('id', widget.shopId!)
            .maybeSingle();
        _shopName = shopDoc?['name'] as String?;

        final countRes = await supabase
            .from('appointments')
            .select('id')
            .eq('shop_id', widget.shopId!)
            .filter('status', 'in', '("confirmado","aguardando_confirmacao")');

        final syncedRes = await supabase
            .from('appointments')
            .select('id')
            .eq('shop_id', widget.shopId!)
            .filter('status', 'in', '("confirmado","aguardando_confirmacao")')
            .not('google_calendar_event_id', 'is', null);

        if (mounted) {
          setState(() {
            _totalAppointments = (countRes as List).length;
            _syncedAppointments = (syncedRes as List).length;
          });
        }
      } else if (!widget.isOwner && widget.employeeId != null) {
        final countRes = await supabase
            .from('appointments')
            .select('id')
            .eq('professional_id', widget.employeeId!)
            .filter('status', 'in', '("confirmado","aguardando_confirmacao")');

        final syncedRes = await supabase
            .from('appointments')
            .select('id')
            .eq('professional_id', widget.employeeId!)
            .filter('status', 'in', '("confirmado","aguardando_confirmacao")')
            .not('google_calendar_event_id', 'is', null);

        if (mounted) {
          setState(() {
            _totalAppointments = (countRes as List).length;
            _syncedAppointments = (syncedRes as List).length;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao carregar status: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleConnect() async {
    setState(() => _isSyncing = true);
    try {
      final result = await GoogleCalendarService.authenticateUser();

      if (result != null && mounted) {
        setState(() {
          _isConnected = true;
          _calendarData = {
            'connected': true,
            'email': result['email'],
            'displayName': result['displayName'],
          };
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conectado ao Google Calendar! Toque em "Sincronizar" para enviar os agendamentos.'),
            duration: Duration(seconds: 4),
          ),
        );
        // Inicia sincronização automática após conectar
        await _handleSync();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conexão cancelada ou falhou. Tente novamente.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao conectar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _handleSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final supabase = Supabase.instance.client;

      // Busca agendamentos ainda não sincronizados
      List<dynamic> pending;
      if (widget.isOwner && widget.shopId != null) {
        pending = await supabase
            .from('appointments')
            .select('id, scheduled_at, end_at, duration_min, client_name, service_name, professional_name')
            .eq('shop_id', widget.shopId!)
            .filter('status', 'in', '("confirmado","aguardando_confirmacao")')
            .filter('google_calendar_event_id', 'is', null);
      } else if (!widget.isOwner && widget.employeeId != null) {
        pending = await supabase
            .from('appointments')
            .select('id, scheduled_at, end_at, duration_min, client_name, service_name, professional_name')
            .eq('professional_id', widget.employeeId!)
            .filter('status', 'in', '("confirmado","aguardando_confirmacao")')
            .filter('google_calendar_event_id', 'is', null);
      } else {
        pending = [];
      }

      if (pending.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nenhum agendamento pendente de sincronização.')),
          );
        }
        return;
      }

      final appointments = List<Map<String, dynamic>>.from(pending);
      final shopName = _shopName ?? 'MarkaAI';

      final synced = await GoogleCalendarService.syncAppointments(
        appointments: appointments,
        shopName: shopName,
      );

      if (mounted) {
        if (synced > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$synced agendamento(s) sincronizado(s) com sucesso!')),
          );
          await _loadCalendarStatus();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível sincronizar. Verifique sua conta Google.')),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao sincronizar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao sincronizar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _handleDisconnect() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desconectar?'),
        content: const Text('Deseja parar a sincronização com o Google Calendar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('NÃO')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SIM')),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await GoogleCalendarService.disconnect();
        if (mounted) {
          setState(() {
            _isConnected = false;
            _calendarData = null;
          });
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Erro ao desconectar: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup Google Calendar'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 24),
                  const Text(
                    'Como funciona?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoItem(
                    Icons.sync,
                    'Sincronização Automática',
                    'Seus agendamentos serão criados no seu Google Calendar.',
                  ),
                  _buildInfoItem(
                    Icons.notifications_active,
                    'Lembretes',
                    'Receba notificações nativas do Google no seu celular.',
                  ),
                  _buildInfoItem(
                    Icons.security,
                    'Segurança',
                    'Apenas agendamentos autorizados são sincronizados.',
                  ),
                  const SizedBox(height: 40),
                  if (_isConnected) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSyncing ? null : _handleSync,
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.sync),
                        label: Text(_isSyncing
                            ? 'Sincronizando...'
                            : 'SINCRONIZAR AGORA'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _isSyncing ? null : _handleDisconnect,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('DESCONECTAR CONTA GOOGLE'),
                      ),
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSyncing ? null : _handleConnect,
                        icon: _isSyncing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.login),
                        label: const Text('CONECTAR AO GOOGLE CALENDAR'),
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

  Widget _buildStatusCard() {
    final pending =
        (_totalAppointments - _syncedAppointments).clamp(0, 9999);
    final lastSync = _calendarData?['lastSync'] as String?;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_isConnected ? Colors.green : Colors.grey)
                      .withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isConnected ? Icons.check_circle : Icons.cloud_off,
                  color: _isConnected ? Colors.green : Colors.grey,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isConnected ? 'Conectado' : 'Não conectado',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (_isConnected && _calendarData?['email'] != null)
                      Text(_calendarData!['email'] as String,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13)),
                    if (_isConnected && lastSync != null)
                      Text(
                        'Última sync: ${_formatDate(lastSync)}',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSimpleStat('Total', _totalAppointments.toString()),
              _buildSimpleStat(
                  'Sincronizados', _syncedAppointments.toString()),
              _buildSimpleStat('Pendente', pending.toString(),
                  highlight: pending > 0),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  Widget _buildSimpleStat(String label, String value,
      {bool highlight = false}) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: highlight ? Colors.orange : null)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildInfoItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryPurple, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                Text(desc,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
