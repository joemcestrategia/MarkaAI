import 'dart:typed_data';
import 'package:flutter/material.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class SupportNewTicketPage extends StatefulWidget {
  const SupportNewTicketPage({super.key});

  @override
  State<SupportNewTicketPage> createState() => _SupportNewTicketPageState();
}

class _SupportNewTicketPageState extends State<SupportNewTicketPage> {
  final _supabase = Supabase.instance.client;
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedCategory = 'scheduling';
  bool _sending = false;
  bool _formValid = false;
  int _step = 0; // 0 = category, 1 = form

  final List<_PickedAttachment> _attachments = [];

  static const _categories = [
    {'key': 'scheduling', 'label': 'Agendamentos', 'icon': Icons.calendar_today_rounded, 'desc': 'Problemas com horários, agenda ou marcações'},
    {'key': 'payment', 'label': 'Pagamentos', 'icon': Icons.payment_rounded, 'desc': 'Cobranças, PIX, cartão ou financeiro'},
    {'key': 'account', 'label': 'Contas e Acesso', 'icon': Icons.lock_outline_rounded, 'desc': 'Login, senha ou dados do perfil'},
    {'key': 'suggestion', 'label': 'Sugestões', 'icon': Icons.lightbulb_outline_rounded, 'desc': 'Ideias de melhorias ou novas funcionalidades'},
    {'key': 'other', 'label': 'Outros', 'icon': Icons.help_outline_rounded, 'desc': 'Dúvida ou problema geral'},
  ];

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_checkFormValid);
    _descController.addListener(_checkFormValid);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _checkFormValid() {
    final valid = _titleController.text.trim().isNotEmpty && _descController.text.trim().isNotEmpty;
    if (valid != _formValid) setState(() => _formValid = valid);
  }

  Future<void> _pickImage() async {
    if (_attachments.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Máximo de 3 imagens.')),
      );
      return;
    }
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200, imageQuality: 80);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final name = picked.name;
      setState(() => _attachments.add(_PickedAttachment(name: name, bytes: bytes)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao selecionar imagem: $e')),
        );
      }
    }
  }

  String _mimeFromExt(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return 'image/jpeg';
    }
  }

  Future<List<Map<String, String>>> _uploadAttachments(String ticketId) async {
    final List<Map<String, String>> uploaded = [];
    for (final att in _attachments) {
      final ext = att.name.split('.').last.toLowerCase();
      final mime = _mimeFromExt(ext);
      final path = 'tickets/$ticketId/${DateTime.now().millisecondsSinceEpoch}_${att.name}';
      await _supabase.storage.from('ticket-attachments').uploadBinary(
        path,
        att.bytes,
        fileOptions: FileOptions(contentType: mime),
      );
      final url = _supabase.storage.from('ticket-attachments').getPublicUrl(path);
      uploaded.add({'name': att.name, 'url': url, 'type': mime});
    }
    return uploaded;
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();
    if (title.isEmpty || desc.isEmpty) return;

    setState(() => _sending = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Não autenticado');

      final userData = await _supabase
          .from('users')
          .select('name, shop_id')
          .eq('id', user.id)
          .maybeSingle();

      String? shopId;
      String? shopName;
      final userName = userData?['name'] ?? user.email ?? 'Usuário';

      if (userData?['shop_id'] != null) {
        shopId = userData!['shop_id'];
        final shop = await _supabase
            .from('shops')
            .select('name')
            .eq('id', shopId!)
            .maybeSingle();
        shopName = shop?['name'];
      }

      // Upload attachments
      List<Map<String, String>> attachmentsList = [];
      final ticketTempId = DateTime.now().millisecondsSinceEpoch.toString();
      if (_attachments.isNotEmpty) {
        attachmentsList = await _uploadAttachments(ticketTempId);
      }

      await _supabase.from('support_tickets').insert({
        'title': title,
        'description': desc,
        'category': _selectedCategory,
        'source': 'client_portal',
        'opened_by_user_id': user.id,
        'opened_by_name': userName,
        'reporter_email': user.email,
        'shop_id': shopId,
        'shop_name': shopName,
        if (attachmentsList.isNotEmpty) 'attachments': attachmentsList,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chamado criado com sucesso!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao criar chamado: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 0 ? 'Selecione a Categoria' : 'Descreva o Problema',
            style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: _step == 0 ? _buildCategoryStep() : _buildFormStep(),
    );
  }

  Widget _buildCategoryStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Sobre o que é seu chamado?', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
        const SizedBox(height: 16),
        ..._categories.map((cat) {
          final isSelected = _selectedCategory == cat['key'];
          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade200,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: isSelected
                    ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.1),
                child: Icon(cat['icon'] as IconData,
                    color: isSelected ? Theme.of(context).primaryColor : Colors.grey),
              ),
              title: Text(cat['label'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(cat['desc'] as String, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              trailing: isSelected ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor) : null,
              onTap: () => setState(() => _selectedCategory = cat['key'] as String),
            ),
          );
        }),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => setState(() => _step = 1),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Continuar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildFormStep() {
    final cat = _categories.firstWhere((c) => c['key'] == _selectedCategory);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(cat['icon'] as IconData, size: 20, color: Theme.of(context).primaryColor),
              const SizedBox(width: 10),
              Text(cat['label'] as String,
                  style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).primaryColor)),
              const Spacer(),
              TextButton(onPressed: () => setState(() => _step = 0), child: const Text('Alterar', style: TextStyle(fontSize: 12))),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('Título *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 6),
        TextField(
          controller: _titleController,
          maxLength: 120,
          decoration: InputDecoration(
            hintText: 'Resumo breve do problema',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Descrição *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 6),
        TextField(
          controller: _descController,
          maxLines: 5,
          maxLength: 2000,
          decoration: InputDecoration(
            hintText: 'Descreva o problema com detalhes. Inclua mensagens de erro, passos para reproduzir, etc.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
        const SizedBox(height: 16),
        // Attachment section
        Row(
          children: [
            const Text('Prints / Screenshots', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const Spacer(),
            Text('${_attachments.length}/3', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ..._attachments.asMap().entries.map((entry) {
              final i = entry.key;
              final att = entry.value;
              return Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(att.bytes, width: 80, height: 80, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: -4, right: -4,
                    child: GestureDetector(
                      onTap: () => setState(() => _attachments.removeAt(i)),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              );
            }),
            if (_attachments.length < 3)
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.grey.shade50,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, color: Colors.grey[400], size: 28),
                      Text('Adicionar', style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _sending || !_formValid ? null : _submit,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _sending
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Enviar Chamado', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}

class _PickedAttachment {
  final String name;
  final Uint8List bytes;
  _PickedAttachment({required this.name, required this.bytes});
}
