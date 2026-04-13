import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupportNewTicketPage extends StatefulWidget {
  const SupportNewTicketPage({super.key});

  @override
  State<SupportNewTicketPage> createState() => _SupportNewTicketPageState();
}

class _SupportNewTicketPageState extends State<SupportNewTicketPage> {
  final _supabase = Supabase.instance.client;
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedCategory = 'other';
  bool _sending = false;
  int _step = 0; // 0 = category, 1 = form

  static const _categories = [
    {'key': 'scheduling', 'label': 'Agendamentos', 'icon': Icons.calendar_today_rounded, 'desc': 'Problemas com horários, agenda ou marcações'},
    {'key': 'payment', 'label': 'Pagamentos', 'icon': Icons.payment_rounded, 'desc': 'Cobranças, PIX, cartão ou financeiro'},
    {'key': 'whatsapp', 'label': 'WhatsApp', 'icon': Icons.chat_rounded, 'desc': 'Integração ou mensagens automáticas'},
    {'key': 'nfse', 'label': 'NFS-e / Fiscal', 'icon': Icons.receipt_long_rounded, 'desc': 'Emissão de notas fiscais'},
    {'key': 'account', 'label': 'Conta e Acesso', 'icon': Icons.lock_outline_rounded, 'desc': 'Login, senha ou dados do perfil'},
    {'key': 'other', 'label': 'Outro Assunto', 'icon': Icons.help_outline_rounded, 'desc': 'Dúvida ou problema geral'},
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();
    if (title.isEmpty || desc.isEmpty) return;

    setState(() => _sending = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Não autenticado');

      // Busca dados do usuário e shop
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
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chamado criado com sucesso!'),
            backgroundColor: Colors.green,
          ),
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
        Text(
          'Sobre o que é seu chamado?',
          style: TextStyle(fontSize: 16, color: Colors.grey[600]),
        ),
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
              title: Text(cat['label'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(cat['desc'] as String,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              trailing: isSelected
                  ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
                  : null,
              onTap: () => setState(() {
                _selectedCategory = cat['key'] as String;
              }),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Categoria selecionada
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(_categories.firstWhere((c) => c['key'] == _selectedCategory)['icon'] as IconData,
                  size: 20, color: Theme.of(context).primaryColor),
              const SizedBox(width: 10),
              Text(
                _categories.firstWhere((c) => c['key'] == _selectedCategory)['label'] as String,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).primaryColor),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _step = 0),
                child: const Text('Alterar', style: TextStyle(fontSize: 12)),
              ),
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
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _sending || _titleController.text.trim().isEmpty || _descController.text.trim().isEmpty
                ? null
                : _submit,
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
