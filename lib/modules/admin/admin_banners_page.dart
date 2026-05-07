// ignore_for_file: use_build_context_synchronously
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';

// -----------------------------------------------------------------------------
// Proporção real do carousel no app mobile:
//   container height = 135 px  |  margin horizontal = 20 px por lado
//   num iPhone 14 (390px): largura real = 350 px  →  razão ≈ 2.59 : 1
//   Tamanho ideal para upload: 1080 × 432 px  (razão 2.5:1, até 2 MB)
// -----------------------------------------------------------------------------

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
    if (mounted) {
      setState(() {
        _banners = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    }
  }

  /// Soft-delete: apenas desativa o banner (pode ser reativado depois)
  Future<void> _archive(Map<String, dynamic> banner) async {
    final active = banner['is_active'] as bool? ?? false;
    // Se já está inativo, oferece reativar
    if (!active) {
      await _db.from('app_banners').update({'is_active': true}).eq('id', banner['id']);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Banner reativado!')),
        );
      }
      return;
    }
    // Se ativo, confirma desativação
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Desativar banner?'),
        content: const Text(
          'O banner será ocultado no app mas mantido no sistema.\n'
          'Você pode reativá-lo a qualquer momento.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[700]),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desativar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _db.from('app_banners').update({'is_active': false}).eq('id', banner['id']);
    _load();
  }

  /// Exclusão física permanente (apenas quando explicitamente solicitado)
  Future<void> _permanentDelete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir permanentemente?'),
        content: const Text('Esta ação não pode ser desfeita. Todo o histórico de métricas será perdido.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800]),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir permanentemente'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _db.from('app_banners').delete().eq('id', id);
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Novo Banner'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _banners.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_not_supported_outlined,
                          size: 60, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text('Nenhum banner cadastrado.',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      const Text(
                        'Tamanho ideal: 1080 × 432 px (proporção 2.5:1)',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: _banners.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _buildBannerCard(_banners[i]),
                ),
    );
  }

  Widget _buildBannerCard(Map<String, dynamic> b) {
    final active = b['is_active'] as bool? ?? false;
    final imgUrl = (b['image_url'] ?? '').toString();
    final title = (b['title'] ?? '').toString();
    final subtitle = (b['subtitle'] ?? '').toString();
    final ctaText = (b['cta_text'] ?? '').toString();
    final ctaUrl = (b['cta_url'] ?? '').toString();
    final impressions = (b['impressions'] as num?)?.toInt() ?? 0;
    final clicks = (b['clicks'] as num?)?.toInt() ?? 0;
    final ctr = impressions > 0 ? (clicks / impressions * 100).toStringAsFixed(1) : '0.0';
    final advertiser = (b['advertiser_name'] ?? '').toString();

    return Opacity(
      opacity: active ? 1.0 : 0.65,
      child: Card(
        elevation: active ? 3 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Preview mobile ─────────────────────────────────────────────
            Stack(
              children: [
                Container(
                  height: 135,
                  width: double.infinity,
                  color: const Color(0xFF4A148C),
                  child: imgUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imgUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              const Center(child: Icon(Icons.broken_image, color: Colors.white54)),
                        )
                      : null,
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: imgUrl.isNotEmpty
                            ? [
                                const Color(0xFF6A1B9A).withValues(alpha: 0.75),
                                const Color(0xFF1A0033).withValues(alpha: 0.75),
                              ]
                            : [const Color(0xFF6A1B9A), const Color(0xFF4A0080)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12, left: 12, right: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(blurRadius: 6, color: Colors.black54)])),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 6),
                      if (ctaText.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                              color: Colors.white, borderRadius: BorderRadius.circular(20)),
                          child: Text(ctaText,
                              style: const TextStyle(
                                  color: Color(0xFF6A1B9A),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11)),
                        ),
                    ],
                  ),
                ),
                // Badge status
                Positioned(
                  top: 10, right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: active ? Colors.green[600] : Colors.orange[700],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      active ? 'Ativo' : 'Arquivado',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const Positioned(
                  top: 10, left: 10,
                  child: Row(
                    children: [
                      Icon(Icons.phone_iphone, size: 13, color: Colors.white70),
                      SizedBox(width: 3),
                      Text('Preview',
                          style: TextStyle(fontSize: 11, color: Colors.white70)),
                    ],
                  ),
                ),
              ],
            ),

            // ── Métricas de performance ────────────────────────────────────
            Container(
              color: Colors.grey[50],
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  _metricChip(Icons.bar_chart_rounded, '$impressions', 'Impressões', Colors.blue[700]!),
                  const SizedBox(width: 8),
                  _metricChip(Icons.touch_app_rounded, '$clicks', 'Cliques', Colors.purple[700]!),
                  const SizedBox(width: 8),
                  _metricChip(Icons.percent_rounded, '$ctr%', 'CTR', Colors.teal[700]!),
                  const Spacer(),
                  if (advertiser.isNotEmpty)
                    Chip(
                      avatar: const Icon(Icons.business_outlined, size: 13),
                      label: Text(advertiser,
                          style: const TextStyle(fontSize: 10)),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),

            // ── Ações ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.link, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(ctaUrl,
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('Ordem: ${b['sort_order']}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Arquivar / Reativar (soft-delete)
                      OutlinedButton.icon(
                        onPressed: () => _archive(b),
                        icon: Icon(
                          active ? Icons.archive_outlined : Icons.unarchive_outlined,
                          size: 15,
                        ),
                        label: Text(
                          active ? 'Arquivar' : 'Reativar',
                          style: const TextStyle(fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: active ? Colors.orange[800] : Colors.green[700],
                          side: BorderSide(color: active ? Colors.orange[300]! : Colors.green[300]!),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _openForm(b),
                        icon: const Icon(Icons.edit, size: 15),
                        label: const Text('Editar', style: TextStyle(fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6)),
                      ),
                      const Spacer(),
                      // Menu de 3 pontos para ações destrutivas
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                        tooltip: 'Mais opções',
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_forever, color: Colors.red, size: 16),
                                SizedBox(width: 8),
                                Text('Excluir permanentemente',
                                    style: TextStyle(color: Colors.red, fontSize: 13)),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (v) {
                          if (v == 'delete') _permanentDelete(b['id']);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricChip(IconData icon, String value, String label, Color color) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
            Text(value,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
      ],
    );
  }
}


// =============================================================================
// Diálogo de criação / edição de banner
// =============================================================================


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
  late final TextEditingController _advertiserName;
  late final TextEditingController _advertiserEmail;
  bool _isActive = true;
  bool _saving = false;

  // Upload de imagem
  Uint8List? _pickedImageBytes;
  String? _pickedImageName;
  bool _uploadingImage = false;


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
    _advertiserName = TextEditingController(text: e?['advertiser_name'] ?? '');
    _advertiserEmail = TextEditingController(text: e?['advertiser_email'] ?? '');
    _isActive = e?['is_active'] as bool? ?? true;

    // Atualiza preview ao digitar
    for (final c in [_title, _subtitle, _ctaText, _imageUrl]) {
      c.addListener(() { if (mounted) setState(() {}); });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _imageUrl.dispose();
    _ctaText.dispose();
    _ctaUrl.dispose();
    _sortOrder.dispose();
    _advertiserName.dispose();
    _advertiserEmail.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    setState(() {
      _pickedImageBytes = file.bytes;
      _pickedImageName = file.name;
    });
  }

  Future<String?> _uploadImage(Uint8List bytes, String filename) async {
    setState(() => _uploadingImage = true);
    try {
      final ext = filename.split('.').last.toLowerCase();
      final path =
          'banners/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final contentType = (ext == 'jpg' || ext == 'jpeg')
          ? 'image/jpeg'
          : ext == 'png'
              ? 'image/png'
              : 'image/webp';
      await Supabase.instance.client.storage
          .from('app-banners')
          .uploadBinary(path, bytes,
              fileOptions: FileOptions(contentType: contentType));
      return Supabase.instance.client.storage
          .from('app-banners')
          .getPublicUrl(path);
    } catch (e) {
      debugPrint('[AdminBanners] erro no upload: $e');
      return null;
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    String finalImageUrl = _imageUrl.text.trim();

    // Faz upload se o admin escolheu um arquivo
    if (_pickedImageBytes != null && _pickedImageName != null) {
      final uploaded = await _uploadImage(_pickedImageBytes!, _pickedImageName!);
      if (uploaded != null) {
        finalImageUrl = uploaded;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Erro ao fazer upload da imagem. Tente novamente.'),
                backgroundColor: Colors.red),
          );
        }
        setState(() => _saving = false);
        return;
      }
    }

    final payload = {
      'title': _title.text.trim(),
      'subtitle': _subtitle.text.trim(),
      'image_url': finalImageUrl,
      'cta_text': _ctaText.text.trim(),
      'cta_url': _ctaUrl.text.trim(),
      'sort_order': int.tryParse(_sortOrder.text.trim()) ?? 0,
      'is_active': _isActive,
      'advertiser_name': _advertiserName.text.trim(),
      'advertiser_email': _advertiserEmail.text.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    };


    final db = Supabase.instance.client;
    if (widget.existing != null) {
      await db
          .from('app_banners')
          .update(payload)
          .eq('id', widget.existing!['id']);
    } else {
      await db.from('app_banners').insert(payload);
    }
    if (mounted) Navigator.pop(context, true);
  }

  // ---------------------------------------------------------------------------
  // Preview mobile ao vivo
  // ---------------------------------------------------------------------------
  Widget _buildMobilePreview() {
    final title =
        _title.text.trim().isEmpty ? 'Título do Banner' : _title.text.trim();
    final subtitle = _subtitle.text.trim();
    final ctaText =
        _ctaText.text.trim().isEmpty ? 'Saiba mais' : _ctaText.text.trim();
    final imgUrl = _imageUrl.text.trim();
    final hasImage = _pickedImageBytes != null || imgUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.phone_iphone, size: 15, color: Colors.grey),
            const SizedBox(width: 4),
            const Text('Preview mobile (tamanho real)',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber[300]!),
              ),
              child: const Text(
                '1080 × 432 px recomendado',
                style: TextStyle(fontSize: 10, color: Colors.orange),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            height: 135,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Imagem de fundo
                Container(color: const Color(0xFF4A148C)),
                if (_pickedImageBytes != null)
                  Image.memory(_pickedImageBytes!, fit: BoxFit.cover)
                else if (imgUrl.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: imgUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox(),
                  ),
                // Gradiente overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: hasImage
                          ? [
                              const Color(0xFF6A1B9A).withValues(alpha: 0.82),
                              const Color(0xFF1A0033).withValues(alpha: 0.82),
                            ]
                          : [
                              const Color(0xFF6A1B9A),
                              const Color(0xFF4A0080),
                            ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                // Conteúdo
                Positioned(
                  bottom: 12, left: 12, right: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(blurRadius: 6, color: Colors.black54)
                              ])),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 5),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(ctaText,
                            style: const TextStyle(
                                color: Color(0xFF6A1B9A),
                                fontWeight: FontWeight.bold,
                                fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Seção de imagem com upload + URL alternativa
  // ---------------------------------------------------------------------------
  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Imagem do Banner',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        // Guia de dimensões
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue[200]!),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 15, color: Colors.blue),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tamanho ideal: 1080 × 432 px  •  Proporção 2.5:1\n'
                  'Formatos: JPG, PNG ou WebP  •  Máximo: 2 MB',
                  style: TextStyle(fontSize: 11, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Estado: imagem escolhida ou botão de escolha
        if (_pickedImageBytes != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[300]!),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _pickedImageName ?? 'Imagem selecionada',
                    style: const TextStyle(fontSize: 12, color: Colors.green),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() {
                    _pickedImageBytes = null;
                    _pickedImageName = null;
                  }),
                  child: const Icon(Icons.close, size: 16, color: Colors.green),
                ),
              ],
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Escolher Imagem do Dispositivo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryPurple,
                side: BorderSide(color: AppColors.primaryPurple),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        const SizedBox(height: 10),
        // Alternativa: URL
        TextFormField(
          controller: _imageUrl,
          decoration: InputDecoration(
            labelText: 'ou cole uma URL de imagem',
            hintText: 'https://...',
            prefixIcon: const Icon(Icons.link, size: 18),
            border: const OutlineInputBorder(),
            isDense: true,
            helperText: _pickedImageBytes != null
                ? 'O arquivo escolhido acima terá prioridade sobre a URL'
                : null,
            helperStyle: const TextStyle(fontSize: 10, color: Colors.orange),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _saving || _uploadingImage;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Novo Banner' : 'Editar Banner'),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Preview ao vivo
                _buildMobilePreview(),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),
                // Seção de imagem
                _buildImageSection(),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),
                // Campos de texto
                _field(_title, 'Título', required: true),
                _field(_subtitle, 'Subtítulo (opcional)'),
                _field(_ctaText, 'Texto do botão', required: true),
                _field(_ctaUrl, 'Link ao clicar no banner', required: true),
                _field(_sortOrder, 'Ordem de exibição (número)'),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                // Seção anunciante
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purple[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.business_outlined, size: 14, color: Colors.purple),
                          SizedBox(width: 6),
                          Text('Dados do Anunciante (opcional)',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.purple)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _field(_advertiserName, 'Nome da empresa anunciante'),
                      _field(_advertiserEmail, 'E-mail do anunciante'),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Banner ativo', style: TextStyle(fontSize: 14)),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  activeThumbColor: AppColors.primaryPurple,
                ),
                const SizedBox(height: 4),
              ],

            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: isBusy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white),
          onPressed: isBusy ? null : _save,
          icon: isBusy
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined, size: 16),
          label: Text(
              _uploadingImage ? 'Enviando...' : _saving ? 'Salvando...' : 'Salvar'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label,
      {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null
            : null,
      ),
    );
  }
}
