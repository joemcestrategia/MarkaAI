import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

class AdminTicketDetailPage extends StatefulWidget {
  final String ticketId;
  const AdminTicketDetailPage({super.key, required this.ticketId});

  @override
  State<AdminTicketDetailPage> createState() => _AdminTicketDetailPageState();
}

class _AdminTicketDetailPageState extends State<AdminTicketDetailPage> {
  final _supabase = Supabase.instance.client;
  final _replyController = TextEditingController();
  final _scrollController = ScrollController();

  Map<String, dynamic>? _ticket;
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _sending = false;
  bool _isInternal = false;
  bool _uploadingImage = false;
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _ticketChannel;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _messagesChannel?.unsubscribe();
    _ticketChannel?.unsubscribe();
    _replyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _subscribeRealtime() {
    _messagesChannel = _supabase
        .channel('admin-ticket-messages-${widget.ticketId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ticket_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'ticket_id', value: widget.ticketId),
          callback: (payload) {
            _loadMessages();
          },
        )
        .subscribe();

    _ticketChannel = _supabase
        .channel('admin-ticket-status-${widget.ticketId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'support_tickets',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: widget.ticketId),
          callback: (payload) {
            _loadTicket();
          },
        )
        .subscribe();
  }

  Future<void> _loadMessages() async {
    try {
      final data = await _supabase
          .from('ticket_messages')
          .select()
          .eq('ticket_id', widget.ticketId)
          .order('created_at', ascending: true);
      if (mounted) {
        setState(() => _messages = List<Map<String, dynamic>>.from(data));
        _scrollToBottom();
      }
    } catch (_) {}
  }

  Future<void> _loadTicket() async {
    try {
      final data = await _supabase.from('support_tickets').select().eq('id', widget.ticketId).single();
      if (mounted) setState(() => _ticket = data);
    } catch (_) {}
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _supabase.from('support_tickets').select().eq('id', widget.ticketId).single(),
        _supabase.from('ticket_messages').select().eq('ticket_id', widget.ticketId).order('created_at', ascending: true),
        _supabase.from('ticket_history').select().eq('ticket_id', widget.ticketId).order('created_at', ascending: false).limit(20),
      ]);
      if (mounted) {
        setState(() {
          _ticket = results[0] as Map<String, dynamic>;
          _messages = List<Map<String, dynamic>>.from(results[1] as List);
          _history = List<Map<String, dynamic>>.from(results[2] as List);
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar ticket admin: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendReply() async {
    final body = _replyController.text.trim();
    if (body.isEmpty) return;

    setState(() => _sending = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final userData = await _supabase.from('users').select('name').eq('id', user.id).maybeSingle();

      await _supabase.from('ticket_messages').insert({
        'ticket_id': widget.ticketId,
        'author_id': user.id,
        'author_name': userData?['name'] ?? 'Admin',
        'author_role': 'admin',
        'body': body,
        'is_internal': _isInternal,
      });

      // Mark as unread for client and update status
      final updates = <String, dynamic>{'has_unread_client': true};
      if (_ticket?['status'] == 'open') {
        updates['status'] = 'in_progress';
      }
      await _supabase.from('support_tickets').update(updates).eq('id', widget.ticketId);

      _replyController.clear();
      _isInternal = false;
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _mimeFromExt(String ext) {
    switch (ext) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'heic': return 'image/heic';
      case 'heif': return 'image/heif';
      default: return 'image/jpeg';
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 80);
      if (picked == null) return;

      setState(() => _uploadingImage = true);
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final mime = _mimeFromExt(ext);
      final path = 'tickets/${widget.ticketId}/${DateTime.now().millisecondsSinceEpoch}_${picked.name}';

      await _supabase.storage.from('ticket-attachments').uploadBinary(
        path, bytes,
        fileOptions: FileOptions(contentType: mime),
      );
      final url = _supabase.storage.from('ticket-attachments').getPublicUrl(path);

      final user = _supabase.auth.currentUser;
      final userData = await _supabase.from('users').select('name').eq('id', user?.id ?? '').maybeSingle();

      await _supabase.from('ticket_messages').insert({
        'ticket_id': widget.ticketId,
        'author_id': user?.id,
        'author_name': userData?['name'] ?? 'Admin',
        'author_role': 'admin',
        'body': '',
        'is_internal': _isInternal,
        'attachments': [{'name': picked.name, 'url': url, 'type': mime}],
      });

      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar imagem: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    try {
      await _supabase.from('support_tickets').update({'status': newStatus}).eq('id', widget.ticketId);

      final user = _supabase.auth.currentUser;
      final userData = await _supabase.from('users').select('name').eq('id', user?.id ?? '').maybeSingle();
      await _supabase.from('ticket_history').insert({
        'ticket_id': widget.ticketId,
        'actor_name': userData?['name'] ?? 'Admin',
        'actor_role': 'admin',
        'action': 'status_change',
        'old_value': _ticket?['status'],
        'new_value': newStatus,
      });

      if (newStatus == 'resolved') {
        await _supabase.from('support_tickets').update({'has_unread_client': true}).eq('id', widget.ticketId);
      }

      await _loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status alterado para: ${_statusLabel(newStatus)}'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updatePriority(String newPriority) async {
    try {
      await _supabase.from('support_tickets').update({'priority': newPriority}).eq('id', widget.ticketId);

      final user = _supabase.auth.currentUser;
      final userData = await _supabase.from('users').select('name').eq('id', user?.id ?? '').maybeSingle();
      await _supabase.from('ticket_history').insert({
        'ticket_id': widget.ticketId,
        'actor_name': userData?['name'] ?? 'Admin',
        'actor_role': 'admin',
        'action': 'priority_change',
        'old_value': _ticket?['priority'],
        'new_value': newPriority,
      });

      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    if (_loading && _ticket == null) {
      return Theme(
        data: ThemeData.dark(),
        child: Scaffold(
          backgroundColor: const Color(0xFF0F1117),
          appBar: AppBar(backgroundColor: const Color(0xFF0F1117), title: const Text('Ticket')),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_ticket == null) {
      return Theme(
        data: ThemeData.dark(),
        child: Scaffold(
          backgroundColor: const Color(0xFF0F1117),
          appBar: AppBar(backgroundColor: const Color(0xFF0F1117), title: const Text('Ticket')),
          body: const Center(child: Text('Ticket não encontrado.', style: TextStyle(color: Colors.white))),
        ),
      );
    }

    final status = _ticket!['status'] as String? ?? 'open';
    final priority = _ticket!['priority'] as String? ?? 'medium';
    final isClosed = status == 'closed';
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1117),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1117),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0F1117),
          title: Text('#${_ticket!['ticket_number']} — ${_ticket!['title'] ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              overflow: TextOverflow.ellipsis),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            if (!isClosed) ...[
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                color: const Color(0xFF1A1D27),
                onSelected: _updateStatus,
                itemBuilder: (_) => [
                  if (status != 'in_progress')
                    const PopupMenuItem(value: 'in_progress', child: Text('Marcar Em Andamento', style: TextStyle(color: Colors.white))),
                  if (status != 'waiting_client')
                    const PopupMenuItem(value: 'waiting_client', child: Text('Aguardando Cliente', style: TextStyle(color: Colors.white))),
                  if (status != 'resolved')
                    const PopupMenuItem(value: 'resolved', child: Text('Marcar Resolvido', style: TextStyle(color: Colors.white))),
                  const PopupMenuItem(value: 'closed', child: Text('Fechar Ticket', style: TextStyle(color: Colors.white))),
                ],
              ),
            ],
          ],
        ),
        body: isDesktop ? _buildDesktopLayout(status, priority) : _buildMobileLayout(status, priority, isClosed),
      ),
    );
  }

  Widget _buildDesktopLayout(String status, String priority) {
    final isClosed = status == 'closed';
    return Row(
      children: [
        // Chat area
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(child: _buildMessagesList()),
              if (!isClosed) _buildReplyBox(),
              if (isClosed) _buildClosedBanner(),
            ],
          ),
        ),
        // Side panel
        Container(width: 1, color: Colors.white.withValues(alpha: 0.05)),
        SizedBox(
          width: 320,
          child: _buildSidePanel(status, priority),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(String status, String priority, bool isClosed) {
    return Column(
      children: [
        // Info bar
        _buildMobileInfoBar(status, priority),
        Expanded(child: _buildMessagesList()),
        if (!isClosed) _buildReplyBox(),
        if (isClosed) _buildClosedBanner(),
      ],
    );
  }

  Widget _buildMobileInfoBar(String status, String priority) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _statusColor(status).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(_statusLabel(status),
                style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _priorityColor(priority).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(_priorityLabel(priority),
                style: TextStyle(color: _priorityColor(priority), fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          const Spacer(),
          Text(_ticket!['opened_by_name'] ?? '', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSidePanel(String status, String priority) {
    final createdAt = DateTime.tryParse(_ticket!['created_at'] ?? '');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Detalhes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),

          _buildSideField('Status', _statusLabel(status), _statusColor(status)),
          const SizedBox(height: 12),

          // Priority selector
          const Text('Prioridade', style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: ['low', 'medium', 'high', 'critical'].map((p) {
              final isSelected = priority == p;
              return ChoiceChip(
                label: Text(_priorityLabel(p), style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.grey)),
                selected: isSelected,
                selectedColor: _priorityColor(p),
                backgroundColor: const Color(0xFF1A1D27),
                side: BorderSide(color: _priorityColor(p).withValues(alpha: 0.3)),
                onSelected: (_) => _updatePriority(p),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          _buildSideField('Categoria', _ticket!['category'] ?? '—', null),
          const SizedBox(height: 12),
          _buildSideField('Aberto por', _ticket!['opened_by_name'] ?? '—', null),
          if (_ticket!['shop_name'] != null) ...[
            const SizedBox(height: 12),
            _buildSideField('Negócio', _ticket!['shop_name'], null),
          ],
          if (_ticket!['reporter_email'] != null) ...[
            const SizedBox(height: 12),
            _buildSideField('Email', _ticket!['reporter_email'], null),
          ],
          const SizedBox(height: 12),
          _buildSideField('Criado em',
              createdAt != null ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toLocal()) : '—', null),

          const SizedBox(height: 24),
          const Text('Descrição', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          Text(_ticket!['description'] ?? '', style: TextStyle(color: Colors.grey[400], fontSize: 13, height: 1.5)),

          if (_history.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Histórico', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            ..._history.map((h) {
              final ts = DateTime.tryParse(h['created_at'] ?? '');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.circle, size: 6, color: Colors.grey[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${h['actor_name'] ?? ''}: ${h['action'] ?? ''} ${h['old_value'] ?? ''} → ${h['new_value'] ?? ''}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 11),
                      ),
                    ),
                    if (ts != null)
                      Text(DateFormat('dd/MM HH:mm').format(ts.toLocal()),
                          style: TextStyle(color: Colors.grey[700], fontSize: 10)),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildSideField(String label, String value, Color? color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: color ?? Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Text('Nenhuma mensagem.', style: TextStyle(color: Colors.grey[600])),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, i) => _buildMessage(_messages[i]),
    );
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final isAdmin = msg['author_role'] == 'admin';
    final isInternal = msg['is_internal'] == true;
    final createdAt = DateTime.tryParse(msg['created_at'] ?? '');
    final timeStr = createdAt != null ? DateFormat('dd/MM HH:mm').format(createdAt.toLocal()) : '';
    final body = (msg['body'] ?? '').toString().trim();
    final attachments = _parseAttachments(msg['attachments']);

    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.70),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isInternal
              ? const Color(0xFF3B2E0A)
              : isAdmin
                  ? const Color(0xFF1E2A45)
                  : const Color(0xFF1A1D27),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isAdmin ? 14 : 4),
            bottomRight: Radius.circular(isAdmin ? 4 : 14),
          ),
          border: isInternal
              ? Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3))
              : null,
        ),
        child: Column(
          crossAxisAlignment: isAdmin ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg['author_name'] ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isAdmin ? const Color(0xFF4F8EF7) : Colors.grey[400],
                  ),
                ),
                if (isInternal) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Nota interna',
                        style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(body, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4)),
            ],
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...attachments.map((att) => _buildAttachmentPreview(att)),
            ],
            const SizedBox(height: 4),
            Text(timeStr, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _parseAttachments(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return [];
  }

  Widget _buildAttachmentPreview(Map<String, dynamic> att) {
    final url = att['url'] as String? ?? '';
    final type = (att['type'] as String? ?? '').toLowerCase();
    if (type.startsWith('image') && url.isNotEmpty) {
      return GestureDetector(
        onTap: () => _showFullImage(url),
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(url, width: 200, fit: BoxFit.cover,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return const SizedBox(width: 200, height: 100, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
              },
              errorBuilder: (_, __, ___) => Container(
                width: 200, height: 60,
                decoration: BoxDecoration(color: Colors.grey.shade800, borderRadius: BorderRadius.circular(8)),
                child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
              ),
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  void _showFullImage(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(child: Image.network(url)),
            Positioned(
              top: 8, right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyBox() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D27),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _isInternal = !_isInternal),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isInternal
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isInternal ? Icons.lock : Icons.public,
                          size: 14,
                          color: _isInternal ? const Color(0xFFF59E0B) : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isInternal ? 'Nota interna' : 'Resposta pública',
                          style: TextStyle(
                            color: _isInternal ? const Color(0xFFF59E0B) : Colors.grey,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: _uploadingImage ? null : _pickAndSendImage,
                  icon: _uploadingImage
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.attach_file_rounded, color: Colors.grey),
                  tooltip: 'Enviar imagem',
                ),
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    maxLines: 3,
                    minLines: 1,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _isInternal ? 'Nota interna (invisível ao cliente)...' : 'Responder ao cliente...',
                      hintStyle: TextStyle(color: Colors.grey[600], fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF0F1117),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sending ? null : _sendReply,
                  icon: _sending
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, color: Color(0xFF4F8EF7)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClosedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF1A1D27),
      child: const Text(
        'Este ticket foi encerrado.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
      ),
    );
  }
}
