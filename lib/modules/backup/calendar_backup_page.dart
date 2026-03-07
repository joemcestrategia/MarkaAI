import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../core/services/google_calendar_service.dart';
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
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (mounted) {
          setState(() {
            _calendarData = doc.data()?['googleCalendar'];
            _isConnected = _calendarData?['connected'] ?? false;
          });
        }
      }

      // Conta quantos agendamentos existem
      if (widget.isOwner && widget.shopId != null) {
        final count = await FirebaseFirestore.instance
            .collection('appointments')
            .where('shopId', isEqualTo: widget.shopId)
            .where('status', whereIn: ['confirmado', 'aguardando_confirmacao'])
            .count()
            .get();

        if (mounted) setState(() => _totalAppointments = count.count ?? 0);
      } else if (!widget.isOwner && widget.employeeId != null) {
        final count = await FirebaseFirestore.instance
            .collection('appointments')
            .where('profissionalId', isEqualTo: widget.employeeId)
            .where('status', whereIn: ['confirmado', 'aguardando_confirmacao'])
            .count()
            .get();

        if (mounted) setState(() => _totalAppointments = count.count ?? 0);
      }

      // Conta quantos já têm eventId (já sincronizados)
      if (widget.isOwner && widget.shopId != null) {
        final synced = await FirebaseFirestore.instance
            .collection('appointments')
            .where('shopId', isEqualTo: widget.shopId)
            .where('googleCalendarEventId', isNotEqualTo: null)
            .count()
            .get();

        if (mounted) setState(() => _syncedAppointments = synced.count ?? 0);
      } else if (!widget.isOwner && widget.employeeId != null) {
        final synced = await FirebaseFirestore.instance
            .collection('appointments')
            .where('profissionalId', isEqualTo: widget.employeeId)
            .where('googleCalendarEventId', isNotEqualTo: null)
            .count()
            .get();

        if (mounted) setState(() => _syncedAppointments = synced.count ?? 0);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Erro ao carregar status: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _connectGoogleCalendar() async {
    setState(() => _isLoading = true);

    try {
      final result = await GoogleCalendarService.authenticateUser();

      if (result != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('âœ… Conectado ao Google Calendar com sucesso!'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadCalendarStatus();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('âŒ Falha ao conectar. Tente novamente.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('âŒ Erro: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _disconnectGoogleCalendar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desconectar Google Calendar?'),
        content: const Text(
          'Seus agendamentos continuarão no Google Calendar, mas não serão mais sincronizados automaticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Desconectar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await GoogleCalendarService.disconnect();
      await _loadCalendarStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Desconectado do Google Calendar'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _syncAllAppointments() async {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Conecte-se ao Google Calendar primeiro!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSyncing = true);

    try {
      int synced = 0;

      if (widget.isOwner && widget.shopId != null) {
        synced =
            await GoogleCalendarService.syncAllShopAppointments(widget.shopId!);
      } else if (!widget.isOwner && widget.employeeId != null) {
        synced = await GoogleCalendarService.syncEmployeeAppointments(
            widget.employeeId!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('âœ… $synced agendamentos sincronizados!'),
            backgroundColor: Colors.green,
          ),
        );
      }

      await _loadCalendarStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('âŒ Erro ao sincronizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Backup no Google Calendar'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Card
                  _buildStatusCard(),

                  const SizedBox(height: 20),

                  // Informações
                  _buildInfoCard(),

                  const SizedBox(height: 20),

                  // Estatísticas
                  if (_isConnected) _buildStatsCard(),

                  const SizedBox(height: 20),

                  // Botões de Ação
                  if (!_isConnected)
                    _buildConnectButton()
                  else
                    Column(
                      children: [
                        _buildSyncButton(),
                        const SizedBox(height: 12),
                        _buildDisconnectButton(),
                      ],
                    ),

                  const SizedBox(height: 30),

                  // Dicas
                  _buildTipsCard(),
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
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _isConnected
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.orange.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isConnected ? Icons.check_circle : Icons.cloud_off,
              color: _isConnected ? Colors.green : Colors.orange,
              size: 30,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isConnected ? 'Conectado' : 'Não Conectado',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isConnected
                      ? 'Backup automático ativado'
                      : 'Configure o backup para proteger seus dados',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                  ),
                ),
                if (_isConnected && _calendarData?['connectedAt'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Conectado em: ${DateFormat('dd/MM/yyyy HH:mm').format((_calendarData!['connectedAt'] as Timestamp).toDate())}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.blue[700], size: 22),
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
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.isOwner
                      ? 'Todos os agendamentos da sua loja serão automaticamente salvos no seu Google Calendar. Assim, mesmo que mude de sistema, seus dados estarão seguros!'
                      : 'Seus agendamentos de trabalho serão automaticamente salvos no seu Google Calendar pessoal. Você terá controle total dos seus horários!',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue[800],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    final percentage = _totalAppointments > 0
        ? (_syncedAppointments / _totalAppointments * 100).toStringAsFixed(0)
        : '0';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estatísticas',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Total de Agendamentos',
                  _totalAppointments.toString(),
                  Icons.event,
                  Colors.purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  'Sincronizados',
                  '$_syncedAppointments ($percentage%)',
                  Icons.cloud_done,
                  Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _connectGoogleCalendar,
        icon: const Icon(Icons.link, color: Colors.white),
        label: const Text(
          'CONECTAR GOOGLE CALENDAR',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildSyncButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _isSyncing ? null : _syncAllAppointments,
        icon: _isSyncing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.sync, color: Colors.white),
        label: Text(
          _isSyncing ? 'SINCRONIZANDO...' : 'SINCRONIZAR AGORA',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildDisconnectButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _disconnectGoogleCalendar,
        icon: const Icon(Icons.link_off, color: Colors.red),
        label: const Text(
          'DESCONECTAR',
          style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Widget _buildTipsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates, color: Colors.amber[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Dicas Importantes',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.amber[900],
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTipItem(
              'Sincronização automática: novos agendamentos são adicionados automaticamente'),
          _buildTipItem(
              'Atualizações e cancelamentos também são sincronizados'),
          _buildTipItem(
              'Você pode desconectar a qualquer momento sem perder dados'),
          _buildTipItem(
              'Os eventos ficam no calendário "MarkaAI - Agendamentos"'),
        ],
      ),
    );
  }

  Widget _buildTipItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, color: Colors.amber[700], size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: Colors.amber[900],
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
