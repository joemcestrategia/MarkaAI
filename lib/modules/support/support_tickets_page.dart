import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'support_new_ticket_page.dart';
import 'support_ticket_detail_page.dart';

class SupportTicketsPage extends StatefulWidget {
  const SupportTicketsPage({super.key});

  @override
  State<SupportTicketsPage> createState() => _SupportTicketsPageState();
}

class _SupportTicketsPageState extends State<SupportTicketsPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;
  String _filter = 'all'; // all, open, resolved, closed

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    setState(() => _loading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      var query = _supabase
          .from('support_tickets')
          .select()
          .eq('opened_by_user_id', userId)
          .order('created_at', ascending: false);

      if (_filter == 'open') {
        query = _supabase
            .from('support_tickets')
            .select()
            .eq('opened_by_user_id', userId)
            .inFilter('status', ['open', 'in_progress', 'waiting_client'])
            .order('created_at', ascending: false);
      } else if (_filter == 'resolved') {
        query = _supabase
            .from('support_tickets')
            .select()
            .eq('opened_by_user_id', userId)
            .eq('status', 'resolved')
            .order('created_at', ascending: false);
      } else if (_filter == 'closed') {
        query = _supabase
            .from('support_tickets')
            .select()
            .eq('opened_by_user_id', userId)
            .eq('status', 'closed')
            .order('created_at', ascending: false);
      }

      final data = await query;
      if (mounted) setState(() => _tickets = List<Map<String, dynamic>>.from(data));
    } catch (e) {
      debugPrint('Erro ao carregar tickets: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open': return Colors.blue;
      case 'in_progress': return Colors.orange;
      case 'waiting_client': return Colors.amber;
      case 'resolved': return Colors.green;
      case 'closed': return Colors.grey;
      default: return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'open': return 'Aberto';
      case 'in_progress': return 'Em andamento';
      case 'waiting_client': return 'Aguardando você';
      case 'resolved': return 'Resolvido';
      case 'closed': return 'Fechado';
      default: return status;
    }
  }

  String _categoryLabel(String cat) {
    switch (cat) {
      case 'scheduling': return 'Agendamentos';
      case 'payment': return 'Pagamentos';
      case 'whatsapp': return 'WhatsApp';
      case 'nfse': return 'NFS-e';
      case 'account': return 'Conta';
      case 'other': return 'Outro';
      default: return cat;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meus Chamados', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filtros
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                _buildFilterChip('all', 'Todos'),
                const SizedBox(width: 8),
                _buildFilterChip('open', 'Abertos'),
                const SizedBox(width: 8),
                _buildFilterChip('resolved', 'Resolvidos'),
                const SizedBox(width: 8),
                _buildFilterChip('closed', 'Fechados'),
              ],
            ),
          ),

          // Lista
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _tickets.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.confirmation_number_outlined,
                                size: 48, color: Colors.grey[300]),
                            const SizedBox(height: 12),
                            Text('Nenhum chamado encontrado.',
                                style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadTickets,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _tickets.length,
                          itemBuilder: (context, index) => _buildTicketCard(_tickets[index]),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const SupportNewTicketPage()),
          );
          if (created == true) _loadTickets();
        },
        icon: const Icon(Icons.add),
        label: const Text('Novo Chamado'),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _filter = value);
        _loadTickets();
      },
      selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: isSelected ? Theme.of(context).primaryColor : Colors.grey[600],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 13,
      ),
    );
  }

  Widget _buildTicketCard(Map<String, dynamic> ticket) {
    final status = ticket['status'] as String? ?? 'open';
    final hasUnread = ticket['has_unread_client'] == true;
    final createdAt = DateTime.tryParse(ticket['created_at'] ?? '');
    final dateStr = createdAt != null ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toLocal()) : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: hasUnread ? Colors.blue.withValues(alpha: 0.4) : Colors.grey.shade200,
          width: hasUnread ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SupportTicketDetailPage(ticketId: ticket['id']),
            ),
          );
          _loadTickets();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _statusLabel(status),
                      style: TextStyle(
                        color: _statusColor(status),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _categoryLabel(ticket['category'] ?? ''),
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
                  ),
                  const Spacer(),
                  if (hasUnread)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Text('#${ticket['ticket_number'] ?? ''}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                ticket['title'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(dateStr, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
