// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';

class AdminBannersPage extends StatefulWidget {
  const AdminBannersPage({super.key});

  @override
  State<AdminBannersPage> createState() => _AdminBannersPageState();
}

class _AdminBannersPageState extends State<AdminBannersPage> {
  final _db = Supabase.instance.client;
  List<Map<String, dynamic>> _banners = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _db
        .from('app_banners')
        .select()
        .order('sort_order', ascending: true);
    if (mounted) setState(() { _banners = List<Map<String, dynamic>>.from(data); _loading = false; });
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir banner?'),
        content: const Text('Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _db.from('app_banners').delete().eq('id', id);
    _load();
  }

  Future<void> _toggleActive(Map<String, dynamic> banner) async {
    await _db.from('app_banners').update({'is_active': !(banner['is_active'] as bool)}).eq('id', banner['id']);
    _load();
  }

  Future<void> _openForm([Map<String, dynamic>? existing]) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BannerFormDialog(existing: existing),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Banners do Carousel'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Novo Banner'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _banners.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_not_supported_outlined, size: 60, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Nenhum banner cadastrado.', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _banners.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final b = _banners[i];
                    final active = b['is_active'] as bool? ?? false;
                    final imgUrl = (b['image_url'] ?? '').toString();
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (imgUrl.isNotEmpty)
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                              child: Image.network(
                                imgUrl,
                                height: 140,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 80,
                                  color: Colors.grey[200],
                                  child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        b['title'] ?? '',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: active ? Colors.green[50] : Colors.grey[100],
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: active ? Colors.green : Colors.grey),
                                      ),
                                      child: Text(
                                        active ? 'Ativo' : 'Inativo',
                                        style: TextStyle(fontSize: 12, color: active ? Colors.green[700] : Colors.grey, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                                if ((b['subtitle'] ?? '').toString().isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(b['subtitle'], style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                                ],
                                const SizedBox(height: 6),
                                Text('CTA: ${b['cta_text']}  →  ${b['cta_url']}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                Text('Ordem: ${b['sort_order']}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _toggleActive(b),
                                      icon: Icon(active ? Icons.visibility_off : Icons.visibility, size: 16),
                                      label: Text(active ? 'Desativar' : 'Ativar'),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: () => _openForm(b),
                                      icon: const Icon(Icons.edit, size: 16),
                                      label: const Text('Editar'),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      onPressed: () => _delete(b['id']),
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class _BannerFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _BannerFormDialog({this.existing});

  @override
  State<_BannerFormDialog> createState() => _BannerFormDialogState();
}

class _BannerFormDialogState extends State<_BannerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _subtitle;
  late final TextEditingController _imageUrl;
  late final TextEditingController _ctaText;
  late final TextEditingController _ctaUrl;
  late final TextEditingController _sortOrder;
  bool _isActive = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _title = TextEditingController(text: e?['title'] ?? 'MarkaAI');
    _subtitle = TextEditingController(text: e?['subtitle'] ?? '');
    _imageUrl = TextEditingController(text: e?['image_url'] ?? '');
    _ctaText = TextEditingController(text: e?['cta_text'] ?? 'Saiba mais');
    _ctaUrl = TextEditingController(text: e?['cta_url'] ?? 'https://markaai.com.br');
    _sortOrder = TextEditingController(text: (e?['sort_order'] ?? 0).toString());
    _isActive = e?['is_active'] as bool? ?? true;
  }

  @override
  void dispose() {
    _title.dispose(); _subtitle.dispose(); _imageUrl.dispose();
    _ctaText.dispose(); _ctaUrl.dispose(); _sortOrder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final payload = {
      'title': _title.text.trim(),
      'subtitle': _subtitle.text.trim(),
      'image_url': _imageUrl.text.trim(),
      'cta_text': _ctaText.text.trim(),
      'cta_url': _ctaUrl.text.trim(),
      'sort_order': int.tryParse(_sortOrder.text.trim()) ?? 0,
      'is_active': _isActive,
      'updated_at': DateTime.now().toIso8601String(),
    };
    final db = Supabase.instance.client;
    if (widget.existing != null) {
      await db.from('app_banners').update(payload).eq('id', widget.existing!['id']);
    } else {
      await db.from('app_banners').insert(payload);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Novo Banner' : 'Editar Banner'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_title, 'Título', required: true),
                _field(_subtitle, 'Subtítulo'),
                _field(_imageUrl, 'URL da Imagem (opcional)'),
                _field(_ctaText, 'Texto do botão', required: true),
                _field(_ctaUrl, 'URL de destino (CTA)', required: true),
                _field(_sortOrder, 'Ordem de exibição (número)'),
                const SizedBox(height: 10),
                SwitchListTile(
                  title: const Text('Ativo'),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  activeColor: AppColors.primaryPurple,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple, foregroundColor: Colors.white),
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Salvar'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null : null,
      ),
    );
  }
}
