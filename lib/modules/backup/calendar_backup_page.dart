import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';

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
            _isConnected = _calendarData?['connected'] ?? false;
          });
        }
      }

      // Contagem de agendamentos
      if (widget.isOwner && widget.shopId != null) {
        final countRes = await supabase
            .from('appointments')
            .select('id')
            .eq('shop_id', widget.shopId!)
            .filter('status', 'in', '("confirmado", "aguardando_confirmacao")');
        
        if (mounted) setState(() => _totalAppointments = countRes.length);

        final syncedRes = await supabase
            .from('appointments')
            .select('id')
            .eq('shop_id', widget.shopId!)
            .not('googleCalendarEventId', 'is', null);
            
        if (mounted) setState(() => _syncedAppointments = syncedRes.length);
      } else if (!widget.isOwner && widget.employeeId != null) {
        final countRes = await supabase
            .from('appointments')
            .select('id')
            .eq('professional_id', widget.employeeId!)
            .filter('status', 'in', '("confirmado", "aguardando_confirmacao")');
        
        if (mounted) setState(() => _totalAppointments = countRes.length);

        final syncedRes = await supabase
            .from('appointments')
            .select('id')
            .eq('professional_id', widget.employeeId!)
            .not('googleCalendarEventId', 'is', null);
            
        if (mounted) setState(() => _syncedAppointments = syncedRes.length);
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
      // Aqui integraria com GoogleAuth e GoogleCalendarService
      // Mock para fluxo de UI
      await Future.delayed(const Duration(seconds: 2));
      
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user != null) {
        final googleCalendar = {
          'connected': true,
          'email': user.email,
          'lastSync': DateTime.now().toIso8601String(),
        };
        await supabase.from('users').update({'google_calendar': googleCalendar}).eq('id', user.id);
        
        if (mounted) {
          setState(() {
            _isConnected = true;
            _calendarData = googleCalendar;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sincronizado com Google Calendar!')),
          );
        }
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
        final supabase = Supabase.instance.client;
        final user = supabase.auth.currentUser;
        if (user != null) {
          await supabase.from('users').update({'google_calendar': null}).eq('id', user.id);
          if (mounted) {
            setState(() {
              _isConnected = false;
              _calendarData = null;
            });
          }
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
                if (_isConnected)
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
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isSyncing ? null : _handleConnect,
                      icon: _isSyncing 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_isConnected ? Colors.green : Colors.grey).withValues(alpha: 0.1),
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
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (_isConnected && _calendarData?['email'] != null)
                      Text(_calendarData!['email'], style: const TextStyle(color: Colors.grey, fontSize: 13)),
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
              _buildSimpleStat('Sincronizados', _syncedAppointments.toString()),
              _buildSimpleStat('Pendente', (_totalAppointments - _syncedAppointments).clamp(0, 9999).toString()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
