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
  String _syncProgress = '';
  Map<String, dynamic>? _calendarData;
  int _totalAppointments = 0;
  int _syncedAppointments = 0;
  String? _shopName;
  List<Map<String, dynamic>> _lastFailures = [];

  @override
  void initState() {
    super.initState();
    _loadCalendarStatus();
  }

  void _logPage(String msg) => debugPrint('[CalendarBackup] $msg');

  Future<void> _loadCalendarStatus() async {
    setState(() => _isLoading = true);

    try {
      debugPrint('[CalendarBackup] _loadCalendarStatus: isOwner=${widget.isOwner}, shopId=${widget.shopId}, employeeId=${widget.employeeId}');
      final supabase = Supabase.instance.client;
      final currentUser = supabase.auth.currentUser;

      String? gcalEventIdCol = widget.isOwner ? 'google_calendar_event_id' : 'prof_gcal_event_id';

      if (!widget.isOwner && widget.employeeId != null) {
        // Fluxo para funcionário: lê dados EXCLUSIVAMENTE da tabela employees
        final doc = await supabase
            .from('employees')
            .select('google_calendar')
            .eq('id', widget.employeeId!)
            .maybeSingle();

        final data = doc?['google_calendar'] as Map<String, dynamic>?;
        final connected = data?['connected'] == true;

        _calendarData = data;
        _isConnected = connected;

      } else if (currentUser != null) {
        // Fluxo para dono ou sem employeeId
        final doc = await supabase
            .from('users')
            .select('google_calendar')
            .eq('id', currentUser.id)
            .maybeSingle();

        if (mounted && doc != null) {
          final data = doc['google_calendar'] as Map<String, dynamic>?;
          final connected = data?['connected'] == true;
          setState(() {
            _calendarData = data;
            _isConnected = connected;
          });
        }
      }

      // Busca nome da loja e contagem de agendamentos
      if (widget.isOwner && widget.shopId != null) {
        debugPrint('[CalendarBackup] Fluxo owner: buscando appointments para shopId=${widget.shopId}');
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
            .inFilter('status', ['agendado', 'confirmado', 'pendente', 'pendente_verificacao', 'pendente_pix', 'aguardando_confirmacao']);

        final syncedRes = await supabase
            .from('appointments')
            .select('id')
            .eq('shop_id', widget.shopId!)
            .inFilter('status', ['agendado', 'confirmado', 'pendente', 'pendente_verificacao', 'pendente_pix', 'aguardando_confirmacao'])
            .not('google_calendar_event_id', 'is', null);

        debugPrint('[CalendarBackup] Owner: total=${(countRes as List).length} synced=${(syncedRes as List).length}');

        if (mounted) {
          setState(() {
            _totalAppointments = (countRes as List).length;
            _syncedAppointments = (syncedRes as List).length;
          });
        }
      } else if (!widget.isOwner && widget.employeeId != null && widget.shopId != null) {
        debugPrint('[CalendarBackup] Fluxo employee: shopId=${widget.shopId}, employeeId=${widget.employeeId}');
        final countRes = await supabase
            .from('appointments')
            .select('id')
            .eq('shop_id', widget.shopId!)
            .eq('professional_id', widget.employeeId!)
            .inFilter('status', ['agendado', 'confirmado', 'pendente', 'pendente_verificacao', 'pendente_pix', 'aguardando_confirmacao']);

        final syncedRes = await supabase
            .from('appointments')
            .select('id')
            .eq('shop_id', widget.shopId!)
            .eq('professional_id', widget.employeeId!)
            .inFilter('status', ['agendado', 'confirmado', 'pendente', 'pendente_verificacao', 'pendente_pix', 'aguardando_confirmacao'])
            .not(gcalEventIdCol, 'is', null);

        debugPrint('[CalendarBackup] Employee: total=${(countRes as List).length} synced=${(syncedRes as List).length}');

        if (mounted) {
          setState(() {
            _totalAppointments = (countRes as List).length;
            _syncedAppointments = (syncedRes as List).length;
          });
        }
      }
    } catch (e, stack) {
      debugPrint('[CalendarBackup] Erro ao carregar status: $e');
      debugPrint('[CalendarBackup] Stack: $stack');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleConnect() async {
    setState(() => _isSyncing = true);
    try {
      debugPrint('[CalendarBackup] Iniciando conexão Google Calendar...');
      final String? empId = (!widget.isOwner && widget.employeeId != null) ? widget.employeeId : null;
      
      final result = await GoogleCalendarService.authenticateUser(employeeId: empId);

      if (result['success'] == true && mounted) {
        debugPrint('[CalendarBackup] Conexão OK: email=${result['email']}');

        await _loadCalendarStatus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conectado ao Google Calendar! Use "SINCRONIZAR AGORA" para enviar os agendamentos.'),
            duration: Duration(seconds: 4),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        final errorMsg = result['error'] as String? ?? 'Erro desconhecido';
        debugPrint('[CalendarBackup] Conexão falhou: $errorMsg');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            duration: const Duration(seconds: 8),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint('[CalendarBackup] Exceção ao conectar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao conectar: $e'),
            duration: const Duration(seconds: 8),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _handleSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    _syncProgress = 'Preparando...';

    try {
      final supabase = Supabase.instance.client;

      final activeStatuses = ['agendado', 'confirmado', 'pendente', 'pendente_verificacao', 'pendente_pix', 'aguardando_confirmacao'];
      final canceledStatuses = ['cancelado', 'rejeitado', 'recusado', 'excluido'];

      String eventIdCol = 'google_calendar_event_id';
      
      // Helper para construir a query base reaproveitável
      dynamic baseSelect() {
        if (widget.isOwner && widget.shopId != null) {
          eventIdCol = 'google_calendar_event_id';
          return supabase
              .from('appointments')
              .select('id, scheduled_at, end_at, duration_min, client_name, service_name, professional_name, google_calendar_event_id, prof_gcal_event_id, status')
              .eq('shop_id', widget.shopId!);
        } else if (!widget.isOwner && widget.employeeId != null && widget.shopId != null) {
          // Usa fallback pra event id antigo se estiver usando a conta global, senao usa o novo
          eventIdCol = (_calendarData != null && !_calendarData!.containsKey('tokenExpiry') && _calendarData!['connected'] == true) 
              ? 'google_calendar_event_id' 
              : 'prof_gcal_event_id';
          
          return supabase
              .from('appointments')
              .select('id, scheduled_at, end_at, duration_min, client_name, service_name, professional_name, google_calendar_event_id, prof_gcal_event_id, status')
              .eq('shop_id', widget.shopId!)
              .eq('professional_id', widget.employeeId!);
        } else {
          return supabase.from('appointments').select('id').eq('shop_id', 'none');
        }
      }

      // 1. Agendamentos ativos SEM event_id → criar
      final toCreateRaw = await (baseSelect() as dynamic)
          .inFilter('status', activeStatuses)
          .filter(eventIdCol, 'is', null);
      final toCreate = List<Map<String, dynamic>>.from(toCreateRaw);

      // 2. Agendamentos ativos COM event_id → atualizar
      final toUpdateRaw = await (baseSelect() as dynamic)
          .inFilter('status', activeStatuses)
          .not(eventIdCol, 'is', null);
      final toUpdate = List<Map<String, dynamic>>.from(toUpdateRaw);

      // 3. Agendamentos cancelados COM event_id → deletar do Google Calendar
      final toDeleteRaw = await (baseSelect() as dynamic)
          .inFilter('status', canceledStatuses)
          .not(eventIdCol, 'is', null);
      final toDeleteList = List<Map<String, dynamic>>.from(toDeleteRaw);
      final eventIdsToDelete = toDeleteList
          .map((a) => a[eventIdCol] as String?)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toList();

      final totalOps = toCreate.length + toUpdate.length + eventIdsToDelete.length;

      debugPrint('[CalendarBackup] Sync: criar=${toCreate.length} atualizar=${toUpdate.length} deletar=${eventIdsToDelete.length}');

      if (totalOps == 0) {
        _syncProgress = '';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tudo sincronizado! Nenhuma alteração pendente.')),
          );
        }
        return;
      }

      final shopName = _shopName ?? 'MarkaAI';

      final counters = await GoogleCalendarService.syncAll(
        toCreate: toCreate,
        toUpdate: toUpdate,
        eventIdsToDelete: eventIdsToDelete,
        shopName: shopName,
        eventIdCol: eventIdCol,
        employeeId: !widget.isOwner ? widget.employeeId : null,
        onProgress: (message, current, total) {
          if (mounted) setState(() => _syncProgress = '$message $current/$total');
        },
      );

      // Limpa event_id dos appointments cancelados que deletamos
      for (final appt in toDeleteList) {
        try {
          await supabase.from('appointments').update({
            eventIdCol: null,
          }).eq('id', appt['id']);
        } catch (_) {}
      }

      final created = (counters['created'] as int?) ?? 0;
      final updated = (counters['updated'] as int?) ?? 0;
      final deleted = (counters['deleted'] as int?) ?? 0;
      final failures = (counters['failures'] as List<Map<String, dynamic>>?) ?? [];

      if (mounted) {
        setState(() => _lastFailures = failures);
      }

      final parts = <String>[];
      if (created > 0) parts.add('$created criado(s)');
      if (updated > 0) parts.add('$updated atualizado(s)');
      if (deleted > 0) parts.add('$deleted removido(s)');
      if (failures.isNotEmpty) parts.add('${failures.length} com erro');

      if (mounted && parts.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sincronizado: ${parts.join(', ')}'),
            action: failures.isNotEmpty ? SnackBarAction(
              label: 'VER ERROS',
              textColor: Colors.yellow,
              onPressed: _showPendingDetails,
            ) : null,
            duration: failures.isNotEmpty ? const Duration(seconds: 6) : const Duration(seconds: 4),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível sincronizar. Verifique sua conta Google.')),
        );
      }
    } catch (e) {
      debugPrint('[CalendarBackup] Erro ao sincronizar: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao sincronizar: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncProgress = '';
        });
        _loadCalendarStatus();
      }
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
        final String? empId = (!widget.isOwner && widget.employeeId != null) ? widget.employeeId : null;
        await GoogleCalendarService.disconnect(employeeId: empId);
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
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Backup Google Calendar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.deepPurple,
        elevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: AppColors.border.withValues(alpha: 0.5), height: 1.0),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple))
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildStatusCard(),
                        const SizedBox(height: 32),
                        const Text(
                          'Como funciona?',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.deepPurple, letterSpacing: -0.5),
                        ),
                        const SizedBox(height: 16),
                        _buildInfoItem(
                          Icons.sync_rounded,
                          'Sincronização Automática',
                          'Seus agendamentos serão criados no seu Google Calendar.',
                        ),
                        _buildInfoItem(
                          Icons.notifications_active_rounded,
                          'Lembretes',
                          'Receba notificações nativas do Google no seu celular.',
                        ),
                        _buildInfoItem(
                          Icons.security_rounded,
                          'Segurança',
                          'Apenas agendamentos autorizados são sincronizados.',
                        ),
                      ],
                    ),
                  ),
                ),
                // RODAPÉ COM BOTÕES FIXOS
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -4),
                      )
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isConnected) ...[
                          if (_calendarData?['email'] != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Conectado: ${_calendarData!['email']}',
                                      style: const TextStyle(fontSize: 14, color: Colors.green, fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                                  : const Icon(Icons.sync_rounded),
                              label: Text(_isSyncing
                                  ? (_syncProgress.isNotEmpty ? _syncProgress : 'Sincronizando...')
                                  : 'SINCRONIZAR AGORA', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryPurple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                backgroundColor: Colors.red.withValues(alpha: 0.03),
                              ),
                              child: Text(_calendarData?['email'] != null
                                  ? 'DESCONECTAR CONTA'
                                  : 'DESCONECTAR CONTA GOOGLE', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                                  : const Icon(Icons.login_rounded),
                              label: const Text('CONECTAR AO GOOGLE CALENDAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryPurple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                elevation: 0,
                                shadowColor: AppColors.primaryPurple.withValues(alpha: 0.4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatusCard() {
    final pending =
        (_totalAppointments - _syncedAppointments).clamp(0, 9999);
    final lastSync = _calendarData?['lastSync'] as String?;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isConnected
              ? [Colors.blue[50]!, Colors.blue[100]!]
              : [Colors.grey[100]!, Colors.grey[200]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isConnected ? Colors.blue[200]! : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  _isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  color: _isConnected ? Colors.blue[700] : Colors.grey[500],
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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _isConnected ? Colors.blue[900] : Colors.grey[800],
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (_isConnected && _calendarData?['email'] != null)
                      Text(_calendarData!['email'] as String,
                          style: TextStyle(color: Colors.blue[700], fontSize: 13, fontWeight: FontWeight.w500)),
                    if (_isConnected && lastSync != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Última sync: ${_formatDate(lastSync)}',
                        style: TextStyle(color: Colors.blue[800]?.withValues(alpha: 0.7), fontSize: 12),
                      ),
                    ]
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildSimpleStat('Total', _totalAppointments.toString()),
                Container(width: 1, height: 40, color: AppColors.border.withValues(alpha: 0.5)),
                _buildSimpleStat('Enviados', _syncedAppointments.toString()),
                Container(width: 1, height: 40, color: AppColors.border.withValues(alpha: 0.5)),
                GestureDetector(
                  onTap: pending > 0 ? _showPendingDetails : null,
                  child: _buildSimpleStat('Pendente', pending.toString(),
                      highlight: pending > 0, tappable: pending > 0),
                ),
              ],
            ),
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
      {bool highlight = false, bool tappable = false}) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: highlight ? Colors.orange[700] : AppColors.textPrimary)),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            if (tappable) ...[
              const SizedBox(width: 4),
              Icon(Icons.open_in_new_rounded, size: 12, color: Colors.orange[700]),
            ],
          ],
        ),
      ],
    );
  }

  void _showPendingDetails() {
    final pending = (_totalAppointments - _syncedAppointments).clamp(0, 9999);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollCtrl) {
            return Column(
              children: [
                // Handle
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        '$pending Agendamento(s) Pendente(s)',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                if (_lastFailures.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Os itens abaixo falharam na última sincronização:',
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ),
                const Divider(),
                Expanded(
                  child: _lastFailures.isNotEmpty
                      ? ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _lastFailures.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final f = _lastFailures[i];
                            final scheduledAt = f['scheduled_at'] as String?;
                            String dateStr = '';
                            if (scheduledAt != null) {
                              try {
                                final dt = DateTime.parse(scheduledAt).toLocal();
                                dateStr = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                              } catch (_) {
                                dateStr = scheduledAt;
                              }
                            }
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                              leading: const CircleAvatar(
                                backgroundColor: Colors.orange,
                                radius: 18,
                                child: Icon(Icons.event_busy, color: Colors.white, size: 18),
                              ),
                              title: Text(
                                f['client_name'] as String? ?? 'Cliente',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (dateStr.isNotEmpty)
                                    Text('${f['service_name']} • $dateStr',
                                        style: const TextStyle(fontSize: 12)),
                                  const SizedBox(height: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '⚠ ${f['error']}',
                                      style: const TextStyle(fontSize: 11, color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 12),
                                Text(
                                  'Existem $pending agendamentos pendentes de sincronização.\n\nClique em "SINCRONIZAR AGORA" para sincronizá-los.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildInfoItem(IconData icon, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primaryPurple, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(desc,
                    style:
                        const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
