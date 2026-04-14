import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

class SupportTicketDetailPage extends StatefulWidget {
  final String ticketId;
  const SupportTicketDetailPage({super.key, required this.ticketId});

  @override
  State<SupportTicketDetailPage> createState() => _SupportTicketDetailPageState();
}

class _SupportTicketDetailPageState extends State<SupportTicketDetailPage> {
  final _supabase = Supabase.instance.client;
  final _replyController = TextEditingController();
  final _scrollController = ScrollController();

  Map<String, dynamic>? _ticket;
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _uploadingImage = false;
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _ticketChannel;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _markRead();
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
        .channel('client-ticket-messages-${widget.ticketId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ticket_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'ticket_id', value: widget.ticketId),
          callback: (payload) {
            _loadMessages();
            _markRead();
          },
        )
        .subscribe();

    _ticketChannel = _supabase
        .channel('client-ticket-status-${widget.ticketId}')
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
        _supabase
            .from('ticket_messages')
            .select()
            .eq('ticket_id', widget.ticketId)
            .order('created_at', ascending: true),
      ]);
      if (mounted) {
        setState(() {
          _ticket = results[0] as Map<String, dynamic>;
          _messages = List<Map<String, dynamic>>.from(results[1] as List);
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar ticket: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  Future<void> _markRead() async {
    try {
      await _supabase
          .from('support_tickets')
          .update({'has_unread_client': false})
          .eq('id', widget.ticketId)
          .eq('opened_by_user_id', _supabase.auth.currentUser?.id ?? '');
    } catch (_) {}
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

      final userData = await _supabase
          .from('users')
          .select('name')
          .eq('id', user.id)
          .maybeSingle();

      await _supabase.from('ticket_messages').insert({
        'ticket_id': widget.ticketId,
        'author_id': user.id,
        'author_name': userData?['name'] ?? user.email ?? 'Usuário',
        'author_role': 'client',
        'body': body,
        'is_internal': false,
      });

      _replyController.clear();
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
        'author_name': userData?['name'] ?? user?.email ?? 'Usuário',
        'author_role': 'client',
        'body': '',
        'is_internal': false,
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

  Future<void> _confirmResolved() async {
    try {
      await _supabase.rpc('client_close_ticket', params: {'p_ticket_id': widget.ticketId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chamado fechado. Obrigado!'), backgroundColor: Colors.green),
        );
      }
      await _loadAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _reopenTicket() async {
    try {
      final user = _supabase.auth.currentUser;
      final userData = await _supabase
          .from('users')
          .select('name')
          .eq('id', user?.id ?? '')
          .maybeSingle();

      await _supabase.rpc('client_reopen_ticket', params: {
        'p_ticket_id': widget.ticketId,
        'p_author_name': userData?['name'] ?? 'Cliente',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chamado reaberto.'), backgroundColor: Colors.orange),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    if (_loading && _ticket == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chamado')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_ticket == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chamado')),
        body: const Center(child: Text('Chamado não encontrado.')),
      );
    }

    final status = _ticket!['status'] as String? ?? 'open';
    final isClosed = status == 'closed';
    final isResolved = status == 'resolved';

    return Scaffold(
      appBar: AppBar(
        title: Text('#${_ticket!['ticket_number'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Ticket header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_ticket!['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_statusLabel(status),
                          style: TextStyle(color: _statusColor(status), fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const Spacer(),
                    if (_ticket!['created_at'] != null)
                      Text(
                        DateFormat('dd/MM/yyyy').format(DateTime.parse(_ticket!['created_at']).toLocal()),
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Resolved banner
          if (isResolved)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.green.withValues(alpha: 0.08),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('O suporte marcou como resolvido. O problema foi solucionado?',
                        style: TextStyle(fontSize: 13)),
                  ),
                  TextButton(
                    onPressed: _confirmResolved,
                    child: const Text('Sim', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: _reopenTicket,
                    child: const Text('Não, reabrir', style: TextStyle(color: Colors.orange)),
                  ),
                ],
              ),
            ),

          // Messages
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text('Nenhuma mensagem ainda.',
                        style: TextStyle(color: Colors.grey[400])),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) => _buildMessage(_messages[index]),
                  ),
          ),

          // Reply box
          if (!isClosed)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _uploadingImage ? null : _pickAndSendImage,
                      icon: _uploadingImage
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.attach_file_rounded, color: Colors.grey[600]),
                      tooltip: 'Enviar print',
                    ),
                    Expanded(
                      child: TextField(
                        controller: _replyController,
                        maxLines: 3,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: 'Escreva sua mensagem...',
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
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
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.send_rounded, color: Theme.of(context).primaryColor),
                    ),
                  ],
                ),
              ),
            ),

          // Closed banner
          if (isClosed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.grey.shade100,
              child: const Text(
                'Este chamado foi encerrado.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final isClient = msg['author_role'] == 'client';
    final createdAt = DateTime.tryParse(msg['created_at'] ?? '');
    final timeStr = createdAt != null ? DateFormat('dd/MM HH:mm').format(createdAt.toLocal()) : '';
    final attachments = _parseAttachments(msg['attachments']);
    final body = (msg['body'] ?? '').toString().trim();

    return Align(
      alignment: isClient ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isClient ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isClient ? 14 : 4),
            bottomRight: Radius.circular(isClient ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: isClient ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg['author_name'] ?? '',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isClient ? Theme.of(context).primaryColor : Colors.grey[700],
              ),
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(body, style: const TextStyle(fontSize: 14, height: 1.4)),
            ],
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...attachments.map((att) => _buildAttachmentPreview(att)),
            ],
            const SizedBox(height: 4),
            Text(timeStr, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
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
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
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
}
