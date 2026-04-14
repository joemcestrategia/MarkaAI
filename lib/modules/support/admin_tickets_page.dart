import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'admin_ticket_detail_page.dart';

class AdminTicketsPage extends StatefulWidget {
  final bool embedded;
  const AdminTicketsPage({super.key, this.embedded = false});

  @override
  State<AdminTicketsPage> createState() => _AdminTicketsPageState();
}

class _AdminTicketsPageState extends State<AdminTicketsPage> with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;

  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;
  String _statusFilter = 'all';
  String _priorityFilter = 'all';
  String _searchQuery = '';
  String? _metricFilter;

  // Metrics
  int _openCount = 0;
  int _inProgressCount = 0;
  int _waitingCount = 0;
  int _resolvedTodayCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _statusFilter = ['all', 'open', 'closed'][_tabController.index];
        _loadTickets();
      }
    });
    _loadTickets();
    _loadMetrics();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMetrics() async {
    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

      final results = await Future.wait([
        _supabase.from('support_tickets').select('id').eq('status', 'open'),
        _supabase.from('support_tickets').select('id').eq('status', 'in_progress'),
        _supabase.from('support_tickets').select('id').eq('status', 'waiting_client'),
        _supabase.from('support_tickets').select('id').eq('status', 'resolved').gte('updated_at', todayStart),
      ]);
      if (mounted) {
        setState(() {
          _openCount = (results[0] as List).length;
          _inProgressCount = (results[1] as List).length;
          _waitingCount = (results[2] as List).length;
          _resolvedTodayCount = (results[3] as List).length;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadTickets() async {
    setState(() => _loading = true);
    try {
      var query = _supabase
          .from('support_tickets')
          .select()
          .order('created_at', ascending: false);

      if (_statusFilter == 'open') {
        query = _supabase
            .from('support_tickets')
            .select()
            .inFilter('status', ['open', 'in_progress', 'waiting_client'])
            .order('created_at', ascending: false);
      } else if (_statusFilter == 'closed') {
        query = _supabase
            .from('support_tickets')
            .select()
            .inFilter('status', ['resolved', 'closed'])
            .order('created_at', ascending: false);
      }

      final data = await query;
      var tickets = List<Map<String, dynamic>>.from(data);

      if (_metricFilter != null) {
        tickets = tickets.where((t) => t['status'] == _metricFilter).toList();
      }
      if (_priorityFilter != 'all') {
        tickets = tickets.where((t) => t['priority'] == _priorityFilter).toList();
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        tickets = tickets.where((t) {
          final title = (t['title'] ?? '').toString().toLowerCase();
          final number = (t['ticket_number'] ?? '').toString();
          final name = (t['opened_by_name'] ?? '').toString().toLowerCase();
          return title.contains(q) || number.contains(q) || name.contains(q);
        }).toList();
      }

      if (mounted) setState(() => _tickets = tickets);
    } catch (e) {
      debugPrint('Erro ao carregar tickets admin: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open': return const Color(0xFF3B82F6);
      case 'in_progress': return const Color(0xFFF59E0B);
      case 'waiting_client': return const Color(0xFFEAB308);
      case 'resolved': return const Color(0xFF22C55E);
      case 'closed': return const Color(0xFF6B7280);
      default: return const Color(0xFF6B7280);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'open': return 'Aberto';
      case 'in_progress': return 'Em andamento';
      case 'waiting_client': return 'Aguardando cliente';
      case 'resolved': return 'Resolvido';
      case 'closed': return 'Fechado';
      default: return status;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'critical': return const Color(0xFFEF4444);
      case 'high': return const Color(0xFFF97316);
      case 'medium': return const Color(0xFFF59E0B);
      case 'low': return const Color(0xFF6B7280);
      default: return const Color(0xFF6B7280);
    }
  }

  String _priorityLabel(String priority) {
    switch (priority) {
      case 'critical': return 'Crítico';
      case 'high': return 'Alta';
      case 'medium': return 'Média';
      case 'low': return 'Baixa';
      default: return priority;
    }
  }

  String _categoryLabel(String cat) {
    switch (cat) {
      case 'scheduling': return 'Agendamentos';
      case 'payment': return 'Pagamentos';
      case 'account': return 'Contas e Acesso';
      case 'suggestion': return 'Sugestões';
      case 'whatsapp': return 'WhatsApp';
      case 'nfse': return 'NFS-e';
      case 'other': return 'Outros';
      default: return cat;
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: [
        // Tab bar (when embedded, we show it inline)
        Material(
          color: const Color(0xFF0F1117),
          child: TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF4F8EF7),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: 'Todos (${_openCount + _inProgressCount + _waitingCount})'),
              const Tab(text: 'Abertos'),
              const Tab(text: 'Fechados'),
            ],
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );

    if (widget.embedded) {
      return Theme(
        data: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0F1117),
          cardColor: const Color(0xFF1A1D27),
        ),
        child: Container(color: const Color(0xFF0F1117), child: body),
      );
    }

    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        cardColor: const Color(0xFF1A1D27),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F1117),
          title: const Text('Tickets de Suporte', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: body,
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Metrics row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              _buildMetricChip('Abertos', _openCount, const Color(0xFF3B82F6), 'open'),
              const SizedBox(width: 8),
              _buildMetricChip('Em andamento', _inProgressCount, const Color(0xFFF59E0B), 'in_progress'),
              const SizedBox(width: 8),
              _buildMetricChip('Aguardando', _waitingCount, const Color(0xFFEAB308), 'waiting_client'),
              const SizedBox(width: 8),
              _buildMetricChip('Resolvidos hoje', _resolvedTodayCount, const Color(0xFF22C55E), 'resolved'),
            ],
          ),
        ),
        // Search & filter
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Buscar por título, nº ou nome...',
                    hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[600], size: 20),
                    filled: true,
                    fillColor: const Color(0xFF1A1D27),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: (v) {
                    _searchQuery = v;
                    _loadTickets();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1D27),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _priorityFilter,
                    dropdownColor: const Color(0xFF1A1D27),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Prioridade')),
                      DropdownMenuItem(value: 'critical', child: Text('Crítico')),
                      DropdownMenuItem(value: 'high', child: Text('Alta')),
                      DropdownMenuItem(value: 'medium', child: Text('Média')),
                      DropdownMenuItem(value: 'low', child: Text('Baixa')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        _priorityFilter = v;
                        _loadTickets();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        // Tickets list
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _tickets.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_rounded, size: 48, color: Colors.grey[700]),
                          const SizedBox(height: 12),
                          Text('Nenhum ticket encontrado.', style: TextStyle(color: Colors.grey[600])),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        await _loadTickets();
                        await _loadMetrics();
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _tickets.length,
                        itemBuilder: (context, i) => _buildTicketRow(_tickets[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildMetricChip(String label, int count, Color color, String statusKey) {
    final isSelected = _metricFilter == statusKey;
    return GestureDetector(
      onTap: () {
        setState(() {
          _metricFilter = isSelected ? null : statusKey;
        });
        _loadTickets();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.25) : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color.withValues(alpha: isSelected ? 1.0 : 0.8), fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketRow(Map<String, dynamic> ticket) {
    final status = ticket['status'] as String? ?? 'open';
    final priority = ticket['priority'] as String? ?? 'medium';
    final createdAt = DateTime.tryParse(ticket['created_at'] ?? '');
    final dateStr = createdAt != null ? DateFormat('dd/MM HH:mm').format(createdAt.toLocal()) : '';

    return Card(
      color: const Color(0xFF1A1D27),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminTicketDetailPage(ticketId: ticket['id']),
            ),
          );
          _loadTickets();
          _loadMetrics();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Priority dot
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: _priorityColor(priority),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _statusLabel(status),
                      style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _categoryLabel(ticket['category'] ?? ''),
                      style: TextStyle(color: Colors.grey[500], fontSize: 10),
                    ),
                  ),
                  const Spacer(),
                  Text('#${ticket['ticket_number'] ?? ''}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                ticket['title'] ?? '',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(ticket['opened_by_name'] ?? ticket['reporter_email'] ?? '—',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                  if (ticket['shop_name'] != null) ...[
                    const SizedBox(width: 10),
                    Icon(Icons.storefront, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(ticket['shop_name'],
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  const Spacer(),
                  Text(dateStr, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
