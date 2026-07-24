import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/services/plan_features_service.dart';
import '../../core/constants/plan_features.dart';
import '../../widgets/upgrade_modal.dart';


// Tags pré-definidas para classificação de clientes
const _kPresetTags = [
  {'label': 'VIP', 'emoji': '👑', 'color': 0xFFFFAB00},
  {'label': 'Sumido', 'emoji': '💨', 'color': 0xFF757575},
  {'label': 'Problemático', 'emoji': '⚠️', 'color': 0xFFE53935},
  {'label': 'Novo', 'emoji': '🆕', 'color': 0xFF2E7D32},
];

class ClientDetailsPage extends StatefulWidget {
  final Map<String, dynamic> clientData;
  final String clientId;
  final VoidCallback onClose;
  final String? shopIdOverride;

  const ClientDetailsPage({
    super.key,
    required this.clientData,
    required this.clientId,
    required this.onClose,
    this.shopIdOverride,
  });

  @override
  State<ClientDetailsPage> createState() => _ClientDetailsPageState();
}

class _ClientDetailsPageState extends State<ClientDetailsPage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  String? shopId;
  bool _isLoading = true;
  bool _showTagEditor = false;
  List<String> _manualTags = [];
  final TextEditingController _customTagController = TextEditingController();
  late TabController _tabController;

  PlanFeatures _currentFeatures = planFeaturesConfig[PlanKey.free]!;

  Future<List<Map<String, dynamic>>>? _historyFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadShopId();
    _fetchFullClientData(); // Busca dados completos (CPF, Endereço, etc) ao iniciar
  }

  Future<void> _fetchFullClientData() async {
    try {
      // 1. Tenta buscar por ID (UUID)
      Map<String, dynamic>? doc;
      bool isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(widget.clientId);
      if (isUuid) {
        var query = _supabase.from('users').select().eq('id', widget.clientId);
        doc = await query.maybeSingle();
      }

      // 2. Se não achou por ID (pode ser cliente manual), tenta buscar pelo telefone
      if (doc == null) {
        String? phone = widget.clientData['telefone'] ?? widget.clientData['phone'];
        if (phone != null && phone.isNotEmpty) {
          final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
          if (cleanPhone.isNotEmpty) {
            doc = await _supabase.from('users').select().eq('phone', cleanPhone).maybeSingle();
          }
        }
      }

      final data = doc;
      if (data != null && mounted) {
        setState(() {
          // Mescla os dados encontrados no clientData local
          widget.clientData['cpf'] = data['cpf'] ?? widget.clientData['cpf'];
          widget.clientData['birthDate'] = data['birth_date'] ?? data['birthDate'] ?? widget.clientData['birthDate'];
          widget.clientData['zipCode'] = data['zip_code'] ?? data['zipCode'] ?? widget.clientData['zipCode'];
          widget.clientData['street'] = data['street'] ?? widget.clientData['street'];
          widget.clientData['neighborhood'] = data['neighborhood'] ?? widget.clientData['neighborhood'];
          widget.clientData['city'] = data['city'] ?? widget.clientData['city'];
          widget.clientData['state'] = data['state'] ?? widget.clientData['state'];
          widget.clientData['number'] = data['number'] ?? widget.clientData['number'];

          // Se o nome no banco for mais completo, atualiza também
          if ((data['name']?.toString() ?? '').isNotEmpty) {
            widget.clientData['nome'] = data['name'];
            widget.clientData['name'] = data['name'];
          }

          // Atualiza foto do Google / perfil (photo_url no banco users)
          final photoFromDb = data['photo_url']?.toString() ?? '';
          if (photoFromDb.isNotEmpty) {
            // Foto do Google tem prioridade — atualiza todos os campos de foto
            widget.clientData['photo_url'] = photoFromDb;
            widget.clientData['foto'] = photoFromDb;
            widget.clientData['foto_perfil'] = photoFromDb;
          }

          // Telefone também
          if ((data['phone']?.toString() ?? '').isNotEmpty) {
            widget.clientData['telefone'] = data['phone'];
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar perfil completo do cliente: $e');
    }
  }

  @override
  void dispose() {
    _customTagController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadShopId() async {
    final id = widget.shopIdOverride ?? await SessionService.getShopId();
    if (mounted) {
      setState(() {
        shopId = id;
        _isLoading = false;
      });
      if (id != null) {
        _loadTags(id);
        _loadFeatures(id);
        _refreshHistory();
      }
    }
  }

  Future<void> _loadFeatures(String sid) async {
    // Features are now handled by StreamBuilder in build()
  }

  void _refreshHistory() {
    if (shopId == null) return;
    setState(() {
      _historyFuture = _loadClientHistory();
    });
  }

  DateTime _parseEventDate(Map<String, dynamic> event) {
    try {
      final type = event['_type'] as String? ?? 'appointment';
      final raw = type == 'activity' ? event['created_at'] : event['scheduled_at'];
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.parse(raw);
    } catch (_) {}
    return DateTime(2000);
  }

  Future<List<Map<String, dynamic>>> _loadClientHistory() async {
    if (shopId == null) return [];
    final supabase = Supabase.instance.client;
    final List<Map<String, dynamic>> combined = [];

    try {
      // Monta os identificadores do cliente para o filtro server-side
      final tel = (widget.clientData['telefone'] ?? widget.clientData['phone'] ?? '')
          .toString()
          .replaceAll(RegExp(r'\D'), '');
      final aliases = (widget.clientData['ids'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .where((s) => s.isNotEmpty)
          .toList();

      // Monta filtro OR no Postgres — sem limit silencioso, sem descarte em memória
      // Campos reais da tabela: total_price, total_value, labor_value, service_name
      final orParts = <String>['client_id.eq.${widget.clientId}'];
      if (aliases.isNotEmpty) {
        orParts.add('client_id.in.(${aliases.join(',')})');
      }
      if (tel.isNotEmpty) {
        orParts.add('client_phone.eq.$tel');
      }

      final apptRows = await supabase
          .from('appointments')
          .select(
            'id, scheduled_at, status, service_name, professional_name, '
            'total_price, total_value, labor_value, '
            'payment_method, payment_status, paid_amount, '
            'client_id, client_phone, client_name, is_imported',
          )
          .eq('shop_id', shopId!)
          .or(orParts.join(','))
          .order('scheduled_at', ascending: false);

      for (final a in apptRows) {
        combined.add(Map<String, dynamic>.from(a as Map)..['_type'] = 'appointment');
      }

      // Busca log de atividades para estes agendamentos
      final apptIds = apptRows
          .map((a) => (a as Map)['id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .toList();

      if (apptIds.isNotEmpty) {
        final logs = await supabase
            .from('shop_activity_log')
            .select()
            .eq('shop_id', shopId!)
            .inFilter('appointment_id', apptIds)
            .order('created_at', ascending: false);

        for (final l in logs) {
          final et = (l['event_type'] as String? ?? '');
          if (et == 'reagendamento' || et == 'pagamento_confirmado') {
            combined.add(Map<String, dynamic>.from(l as Map)..['_type'] = 'activity');
          }
        }
      }
    } catch (e) {
      debugPrint('[ClientHistory] Erro ao carregar: $e');
    }

    combined.sort((a, b) => _parseEventDate(b).compareTo(_parseEventDate(a)));
    return combined;
  }

  static const _kTagNormalize = {
    'vip': 'VIP',
    'sumido': 'Sumido',
    'problemático': 'Problemático',
    'problematico': 'Problemático',
    'novo': 'Novo',
  };

  Future<void> _loadTags(String sid) async {
    try {
      final doc = await _supabase
          .from('shop_clients')
          .select()
          .eq('shop_id', sid)
          .eq('user_id', widget.clientId)
          .maybeSingle();
      if (mounted && doc != null) {
        final raw = List<String>.from(doc['manual_tags'] ?? doc['manualTags'] ?? []);
        final tags = raw.map((t) => _kTagNormalize[t.toLowerCase()] ?? t).toList();
        setState(() => _manualTags = tags);
      }
    } catch (e) {
      debugPrint('Erro ao carregar tags: $e');
    }
  }

  Future<void> _saveTags() async {
    if (shopId == null) return;
    // Clientes manuais (ID baseado em telefone) não podem ser salvos em shop_clients (FK para auth.users)
    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (!uuidRegex.hasMatch(widget.clientId)) return;

    try {
      // Deriva a classificação oficial baseada nas tags manuais
      String? classification;
      if (_manualTags.contains('Problemático') || _manualTags.contains('problematico')) {
        classification = 'problematico';
      } else if (_manualTags.contains('VIP') || _manualTags.contains('vip')) {
        classification = 'vip';
      } else if (_manualTags.contains('Sumido') || _manualTags.contains('sumido')) {
        classification = 'sumido';
      } else if (_manualTags.contains('Novo') || _manualTags.contains('novo')) {
        classification = 'novo';
      }

      await _supabase.from('shop_clients').upsert({
        'shop_id': shopId,
        'user_id': widget.clientId,
        'manual_tags': _manualTags.map((t) => t.trim()).toList(),
        'classification': classification ?? '',
        // Se houver uma classificação manual definida, marcamos como override
        'classification_override': classification != null,
        'last_updated': DateTime.now().toIso8601String(),
      }, onConflict: 'shop_id,user_id');
    } catch (e) {
      debugPrint('Erro ao salvar tags: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar classificação: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _togglePresetTag(String label) {
    setState(() {
      if (_manualTags.contains(label)) {
        _manualTags.remove(label);
      } else {
        // Regra de exclusividade: apenas uma classificação por vez
        final presets = ['VIP', 'Sumido', 'Problemático', 'Novo'];
        if (presets.contains(label)) {
          _manualTags.removeWhere((t) => presets.contains(t));
        }

        _manualTags.add(label);
      }
    });
    _saveTags();
  }

  void _addCustomTag(String tag) {
    final t = tag.trim();
    if (t.isEmpty || _manualTags.contains(t)) return;
    setState(() => _manualTags.add(t));
    _customTagController.clear();
    _saveTags();
  }

  void _removeCustomTag(String tag) {
    setState(() => _manualTags.remove(tag));
    _saveTags();
  }

  String _cleanServiceName(String name) {
    if (name.isEmpty || name == '--') return name;
    // Remove parênteses que contenham "leia" ou "informa" (ex: " (leia as informações)")
    return name.replaceAll(RegExp(r'\s*\([^)]*(leia|informa)[^)]*\)', caseSensitive: false), '').trim();
  }



  // Stream de histórico (passado) — filtra no servidor via .or() para não perder agendamentos antigos
  Stream<List<Map<String, dynamic>>> _getHistoryStream() {
    if (shopId == null) return const Stream.empty();

    // Monta os filtros do cliente uma vez
    final tel = (widget.clientData['telefone'] ?? widget.clientData['phone'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\D'), '');
    final aliases = (widget.clientData['ids'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();

    final orParts = <String>['client_id.eq.${widget.clientId}'];
    if (aliases.isNotEmpty) {
      orParts.add('client_id.in.(${aliases.join(',')})');
    }
    if (tel.isNotEmpty) {
      orParts.add('client_phone.eq.$tel');
    }

    // Usa StreamController para poder fazer query assíncrona filtrada
    // O stream do Supabase (.stream) não suporta .or(), então gerenciamos manualmente
    final controller = StreamController<List<Map<String, dynamic>>>();

    Future<void> fetchAndEmit() async {
      try {
        final rows = await _supabase
            .from('appointments')
            .select(
              'id, scheduled_at, status, service_name, professional_name, '
              'total_price, total_value, labor_value, '
              'payment_method, payment_status, paid_amount, '
              'client_id, client_phone, client_name, is_imported, shop_id',
            )
            .eq('shop_id', shopId!)
            .or(orParts.join(','))
            .order('scheduled_at', ascending: false);

        if (!controller.isClosed) {
          controller.add(List<Map<String, dynamic>>.from(rows));
        }
      } catch (e) {
        debugPrint('[HistoryStream] Erro: $e');
        if (!controller.isClosed) controller.add([]);
      }
    }

    fetchAndEmit();

    controller.onCancel = () => controller.close();
    return controller.stream;
  }


  // Stream de próximos agendamentos
  Stream<List<Map<String, dynamic>>> _getUpcomingStream() {
    if (shopId == null) return const Stream.empty();
    final now = DateTime.now();

    final query = _supabase
        .from('appointments')
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId!);

    return query.map((list) {
      final filtered = list.where((d) {
        final matchesShop = (d['shop_id'] ?? d['shopId']) == shopId;
        if (!matchesShop) return false;

        // Filtro de tempo
        final eventDate = _parseEventDate(d);
        if (eventDate.isBefore(now)) return false; // apenas futuros

        // Lógica unificada de match
        bool isMatch = false;
        if ((d['client_id'] ?? d['clientId']) == widget.clientId) isMatch = true;

        if (!isMatch) {
          final aliases = widget.clientData['ids'] as List<dynamic>?;
          final dId = (d['client_id'] ?? d['clientId'])?.toString();
          if (aliases != null && dId != null && aliases.contains(dId)) isMatch = true;
        }

        if (!isMatch) {
          final tel = (widget.clientData['telefone'] ?? widget.clientData['phone'] ?? '').toString();
          final cleanTel = tel.replaceAll(RegExp(r'\D'), '');
          if (cleanTel.isNotEmpty) {
            final aptPhone = (d['client_phone'] ?? d['client_telefone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
            if (aptPhone == cleanTel) isMatch = true;
          } else {
            final nome = (widget.clientData['nome'] ?? widget.clientData['name'] ?? '').toString().trim();
            final aptName = (d['client_name'] ?? d['client_nome'] ?? '').toString().trim();
            if (nome.isNotEmpty && aptName.isNotEmpty && aptName.toLowerCase() == nome.toLowerCase()) isMatch = true;
          }
        }

        return isMatch;
      }).toList();

      filtered.sort((a, b) {
        final dateA = DateTime.tryParse(a['scheduled_at'].toString()) ?? DateTime(2000);
        final dateB = DateTime.tryParse(b['scheduled_at'].toString()) ?? DateTime(2000);
        return dateA.compareTo(dateB); // ascending: true
      });

      return filtered.take(5).toList();
    });
  }

  /// Exibe a foto do cliente em tamanho maior via Dialog com fundo escuro
  void _showPhotoDialog(BuildContext context, String fotoUrl, String nome) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) {
        return GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                // Fundo escuro clicável para fechar
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Foto ampliada
                      Hero(
                        tag: 'client_photo_${widget.clientId}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            fotoUrl,
                            width: 260,
                            height: 260,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 260,
                              height: 260,
                              decoration: BoxDecoration(
                                color: Colors.grey[800],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(Icons.person, size: 80, color: Colors.white54),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Nome do cliente
                      Text(
                        nome,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(blurRadius: 8, color: Colors.black)],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SizedBox(height: 16),
                      const SizedBox(height: 8),
                      // Dica de fechar
                      const Text(
                        'Toque em qualquer lugar para fechar',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Botão X no canto
                Positioned(
                  top: MediaQuery.of(ctx).padding.top + 8,
                  right: 16,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 22),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primaryPurple));
    }

    return StreamBuilder<PlanFeatures>(
      stream: PlanFeaturesService.streamFeaturesByShopId(shopId!),
      builder: (context, snapshot) {
        if (snapshot.hasData) _currentFeatures = snapshot.data!;

        final nome = widget.clientData['nome'] ?? widget.clientData['name'] ?? 'Cliente';
        
        final foto =
            widget.clientData['photo_url']?.toString().isNotEmpty == true
                ? widget.clientData['photo_url'].toString()
                : widget.clientData['foto']?.toString().isNotEmpty == true
                    ? widget.clientData['foto'].toString()
                    : widget.clientData['foto_perfil']?.toString() ?? '';
        final bool isManual = widget.clientData['origem'] == 'manual';
        final Color themeColor = isManual ? Colors.orange : AppColors.primaryPurple;
        final initials = nome.isNotEmpty ? nome[0].toUpperCase() : '?';

        return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
        // ── HEADER COMPACTO ──────────────────────────────────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linha 1: Avatar, nome e botão fechar
              Row(
                children: [
                  // Avatar clicável para ver foto em tamanho maior
                  GestureDetector(
                    onTap: foto.isNotEmpty
                        ? () => _showPhotoDialog(context, foto, nome)
                        : null,
                    child: Hero(
                      tag: 'client_photo_${widget.clientId}',
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              themeColor.withValues(alpha: 0.8),
                              themeColor,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          image: foto.isNotEmpty
                              ? DecorationImage(
                                  image: NetworkImage(foto), fit: BoxFit.cover)
                              : null,
                          boxShadow: foto.isNotEmpty
                              ? [
                                  BoxShadow(
                                    color: themeColor.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        child: foto.isEmpty
                            ? Center(
                                child: Text(initials,
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)))
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Nome e tipo
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                nome,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if ((widget.clientData['email'] ?? '').toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.email_outlined, size: 13, color: Colors.blueGrey),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    widget.clientData['email'],
                                    style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (isManual)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                                color: Colors.orange[50],
                                borderRadius: BorderRadius.circular(4)),
                            child: const Text('MANUAL',
                                style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),

                  // Botoes Ação
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      // Botão fechar
                      IconButton(
                        icon: const Icon(Icons.close,
                            color: Colors.grey, size: 20),
                        onPressed: widget.onClose,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),

              // Linha 2: Tags ativas em destaque (se existirem)
              if (_manualTags.isNotEmpty) ...[
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _manualTags.map((tag) {
                      final preset = _kPresetTags.firstWhere(
                          (p) => p['label'] == tag,
                          orElse: () => {});
                      final color = preset.isNotEmpty
                          ? Color(preset['color'] as int)
                          : AppColors.primaryPurple;
                      final emoji = preset.isNotEmpty
                          ? (preset['emoji'] as String)
                          : '🏷️';
                      return Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: color.withValues(alpha: 0.5), width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(emoji, style: const TextStyle(fontSize: 11)),
                            const SizedBox(width: 4),
                            Text(tag,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: color)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (widget.clientData['ultimoServico'] != null &&
            widget.clientData['ultimoServico'].toString().isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.star_outline_rounded,
                    size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Último serviço: ${widget.clientData['ultimoServico']}",
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),

        // ── ENDEREÇO (se disponível) ──────────────────────────────────
        Builder(builder: (context) {
          final city = widget.clientData['city']?.toString() ?? '';
          final neighborhood = widget.clientData['neighborhood']?.toString() ?? '';

          if (city.isEmpty && neighborhood.isEmpty) return const SizedBox.shrink();

          String line1 = '';
          if (neighborhood.isNotEmpty) {
            line1 = neighborhood;
            if (city.isNotEmpty) line1 += ' - $city';
          } else if (city.isNotEmpty) {
            line1 = city;
          }
          
          String line2 = '';

          return Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined, size: 16, color: Colors.grey[500]),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (line1.isNotEmpty)
                        Text(line1,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87)),
                      if (line2.isNotEmpty)
                        Text(line2,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600])),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),

        // ── KPI BAR ───────────────────────────────────────────────────
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _getHistoryStream(),
          builder: (context, snap) {
            final docs = snap.data ?? [];
            final currency =
                NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

            // Calcula KPIs
            double totalGasto = 0;
            DateTime? lastVisit;
            int completed = 0;
            int cancelled = 0;
            String ultimoServico = '--';
            List<DateTime> completedDates = [];

            final today = DateTime.now();

            // Ordenar documentos para pegar o serviço mais recente corretamente
            final sortedDocs = List<Map<String, dynamic>>.from(docs);
            sortedDocs.sort((a, b) {
              final dateA = DateTime.tryParse(a['scheduled_at']?.toString() ?? '') ?? DateTime(2000);
              final dateB = DateTime.tryParse(b['scheduled_at']?.toString() ?? '') ?? DateTime(2000);
              return dateB.compareTo(dateA); // ascending: false
            });

            for (final d in sortedDocs) {
              // Resolução de valor: campos reais do banco
              // total_price = valor final (com descontos aplicados)
              // total_value = valor base do serviço
              // labor_value = fallback (mão de obra pura)
              final rawVal = (d['total_price'] ?? d['total_value'] ?? d['labor_value'] ?? '0').toString();
              final cleanVal = rawVal.replaceAll(RegExp(r'[^0-9.]'), '');
              final val = double.tryParse(cleanVal) ?? 0.0;

              final rawStatus = (d['status'] ?? '').toString().toLowerCase().trim();
              final dynDate = d['scheduled_at'];
              DateTime dt = DateTime.tryParse(dynDate?.toString() ?? '') ?? DateTime(2000);

              bool isPast = !dt.isAfter(today);
              // Status válidos: Setmore usa 'concluido'; MarkaAI usa 'concluido', 'pago', 'completed'
              bool isCompletedExplicit = rawStatus == 'concluido' ||
                  rawStatus == 'concluído' ||
                  rawStatus == 'pago' ||
                  rawStatus == 'completed';
              bool isCancelled = rawStatus.contains('cancel') ||
                  rawStatus.contains('show') ||
                  rawStatus == 'ausente';

              if (isCompletedExplicit || (isPast && !isCancelled)) {
                totalGasto += val;
                completed++;

                final dtDay = DateTime(dt.year, dt.month, dt.day);
                completedDates.add(dtDay);

                if (lastVisit == null || dt.isAfter(lastVisit)) {
                  lastVisit = dt;
                  // service_name existe tanto em Setmore quanto em MarkaAI nativo
                  ultimoServico = d['service_name']?.toString().isNotEmpty == true
                      ? _cleanServiceName(d['service_name'].toString())
                      : '--';
                }
              } else if (isCancelled) {
                cancelled++;
              }
            }

            final ticketMedio = completed > 0 ? totalGasto / completed : 0.0;
            final lastVisitStr = lastVisit != null
                ? DateFormat('dd/MM/yy').format(lastVisit)
                : '--';

            // Calcula o intervalo médio localmente
            int avgInterval = 0;
            if (completedDates.length > 1) {
              completedDates.sort((a, b) => a.compareTo(b));
              int totalDays = 0;
              int intervals = 0;
              for (int i = 1; i < completedDates.length; i++) {
                final diff = completedDates[i].difference(completedDates[i-1]).inDays;
                if (diff > 0) { // Ignora serviços no mesmo dia
                  totalDays += diff;
                  intervals++;
                }
              }
              if (intervals > 0) avgInterval = (totalDays / intervals).round();
            } else if (completedDates.length == 1) {
              final startOfToday = DateTime(today.year, today.month, today.day);
              avgInterval = startOfToday.difference(completedDates.first).inDays;
            }

            // Dados pré-calculados vindos do BusinessClientsScreen
            final prefService = _cleanServiceName(widget.clientData['servicoPreferido']?.toString() ?? '--');

            return Container(
              color: const Color(0xFFF8F9FD),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      _kpiItem(
                          label: 'Total Gasto',
                          value: totalGasto > 0 ? currency.format(totalGasto) : (completed > 0 ? currency.format(0) : '--'),
                          icon: Icons.monetization_on_outlined,
                          color: Colors.green),
                      _kpiDivider(),
                      _kpiItem(
                          label: 'Ticket Médio',
                          value: ticketMedio > 0 ? currency.format(ticketMedio) : (completed > 0 ? currency.format(0) : '--'),
                          icon: Icons.receipt_long,
                          color: Colors.teal),
                      _kpiDivider(),
                      _kpiItem(
                          label: 'Última Visita',
                          value: lastVisitStr,
                          icon: Icons.history,
                          color: themeColor),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kpiItem(
                          label: 'Visitas',
                          value: '$completed',
                          icon: Icons.calendar_today,
                          color: Colors.blue),
                      _kpiDivider(),
                      _kpiItem(
                          label: 'Cancelados',
                          value: '$cancelled',
                          icon: Icons.cancel_outlined,
                          color: Colors.red),
                      _kpiDivider(),
                      _kpiItem(
                          label: 'Intervalo Médio',
                          value: avgInterval > 0 ? '$avgInterval dias' : (completed > 0 ? '0 dias' : '--'),
                          icon: Icons.timer_outlined,
                          color: Colors.orange),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _kpiItem(
                          label: 'Serviço Preferido',
                          value: prefService,
                          icon: Icons.favorite_outline,
                          color: Colors.pink),
                      _kpiDivider(),
                      _kpiItem(
                          label: 'Último Serviço',
                          value: ultimoServico,
                          icon: Icons.cut_outlined,
                          color: Colors.purple),
                    ],
                  ),
                ],
              ),
            );
          },
        ),

        // ── TAB BAR ───────────────────────────────────────────────────
        Container(
          color: Colors.white,
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primaryPurple,
                indicatorWeight: 3,
                labelColor: AppColors.primaryPurple,
                unselectedLabelColor: Colors.grey,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                tabs: const [
                  Tab(text: 'Histórico'),
                  Tab(text: 'Próximos'),
                ],
              ),
              // Botão editar tags
              InkWell(
                onTap: () {
                  if (!_currentFeatures.clientClassification) {
                    UpgradeModal.show(
                      context,
                      featureName: "Classificação de Clientes",
                      requiredPlan: "Plus",
                    );
                    return;
                  }
                  setState(() => _showTagEditor = !_showTagEditor);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _currentFeatures.clientClassification 
                      ? AppColors.primaryPurple.withValues(alpha: 0.04)
                      : Colors.grey.withValues(alpha: 0.1),
                    border: Border(
                        top: BorderSide(
                            color: (_currentFeatures.clientClassification ? AppColors.primaryPurple : Colors.grey)
                                .withValues(alpha: 0.1))),
                  ),
                  child: Row(
                    children: [
                      Icon(
                          _currentFeatures.clientClassification
                              ? (_showTagEditor ? Icons.label : Icons.label_outline)
                              : Icons.lock,
                          size: 16,
                          color: _currentFeatures.clientClassification ? AppColors.primaryPurple : Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                          !_currentFeatures.clientClassification
                              ? 'Classificação (Bloqueado)'
                              : (_showTagEditor
                                  ? 'Ocultar editor de tags'
                                  : 'Gerenciar Tags'),
                          style: TextStyle(
                              fontSize: 12,
                              color: _currentFeatures.clientClassification ? AppColors.primaryPurple : Colors.grey,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (_currentFeatures.clientClassification)
                        Icon(
                            _showTagEditor
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 16,
                            color: AppColors.primaryPurple),
                    ],
                  ),
                ),
              ),
              if (_showTagEditor) _buildTagEditor(),
            ],
          ),
        ),

        // ── CONTEÚDO DAS ABAS ─────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // ABA 1: HISTÓRICO
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _historyFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
                  }
                  final events = snapshot.data ?? [];
                  if (events.isEmpty) {
                    return _emptyState(
                        icon: Icons.history,
                        message: 'Nenhum histórico encontrado');
                  }
                  return RefreshIndicator(
                    color: AppColors.primaryPurple,
                    onRefresh: () async => _refreshHistory(),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final ev = events[i];
                        if (ev['_type'] == 'activity') {
                          return _buildActivityEventCard(ev);
                        }
                        return _buildHistoryCard(ev);
                      },
                    ),
                  );
                },
              ),

              // ABA 2: PRÓXIMOS
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _getUpcomingStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data ?? [];
                  if (docs.isEmpty) {
                    return _emptyState(
                        icon: Icons.event_available,
                        message: 'Sem agendamentos futuros');
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      return _buildUpcomingCard(docs[i]);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ],
    ),
    );
  },
);
  }

  // ── WIDGETS AUXILIARES ────────────────────────────────────────────

  Widget _kpiItem(
      {required String label,
      required String value,
      required IconData icon,
      required Color color}) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _kpiDivider() => Container(
      width: 1, height: 36, color: Colors.grey.withValues(alpha: 0.2));

  Widget _buildTagEditor() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FD),
        border: Border(
            top: BorderSide(
                color: AppColors.primaryPurple.withValues(alpha: 0.08))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tags pré-definidas
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kPresetTags.map((tag) {
              final label = tag['label'] as String;
              final emoji = tag['emoji'] as String;
              final color = Color(tag['color'] as int);
              final isActive = _manualTags.contains(label);
              return GestureDetector(
                onTap: () => _togglePresetTag(label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color:
                        isActive ? color.withValues(alpha: 0.14) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isActive ? color : Colors.grey[300]!,
                      width: isActive ? 1.5 : 1,
                    ),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                                color: color.withValues(alpha: 0.12),
                                blurRadius: 6,
                                offset: const Offset(0, 2))
                          ]
                        : [],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(emoji, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 4),
                    Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isActive ? color : Colors.grey[600])),
                    if (isActive) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.check_circle, size: 13, color: color),
                    ],
                  ]),
                ),
              );
            }).toList(),
          ),

          // Tags customizadas existentes
          if (_manualTags.any((t) => !_kPresetTags.any((p) => p['label'] == t)))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _manualTags
                    .where((t) => !_kPresetTags.any((p) => p['label'] == t))
                    .map((t) => Chip(
                          label: Text(t, style: const TextStyle(fontSize: 11)),
                          backgroundColor:
                              AppColors.primaryPurple.withValues(alpha: 0.08),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () => _removeCustomTag(t),
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          side: BorderSide(
                              color: AppColors.primaryPurple
                                  .withValues(alpha: 0.3)),
                        ))
                    .toList(),
              ),
            ),

          // Campo para tag personalizada
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _customTagController,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Nova tag personalizada...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey[300]!)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey[300]!)),
                  isDense: true,
                ),
                onSubmitted: _addCustomTag,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _addCustomTag(_customTagController.text),
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: const BoxDecoration(
                    color: AppColors.primaryPurple, shape: BoxShape.circle),
                child: const Icon(Icons.add, size: 16, color: Colors.white),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildActivityEventCard(Map<String, dynamic> data) {
    final eventType = data['event_type'] as String? ?? '';
    final description = data['description'] as String? ?? '';
    final actorName = data['actor_name'] as String? ?? '';
    DateTime date;
    try {
      final raw = data['created_at'];
      date = raw is DateTime ? raw : DateTime.parse(raw.toString());
    } catch (_) {
      date = DateTime.now();
    }

    final bool isReschedule = eventType == 'reagendamento';
    final bool isPayment = eventType == 'pagamento_confirmado';

    final Color accentColor = isPayment
        ? Colors.green
        : isReschedule
            ? AppColors.primaryPurple
            : Colors.orange;

    final IconData icon = isPayment
        ? Icons.credit_card_rounded
        : isReschedule
            ? Icons.swap_horiz_rounded
            : Icons.info_outline;

    final String label = isPayment
        ? 'PAGAMENTO'
        : isReschedule
            ? 'REAGENDADO'
            : 'ATUALIZAÇÃO';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ícone de evento
          Container(
            width: 42,
            height: 48,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: accentColor),
                Text(DateFormat('dd').format(date),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: accentColor)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(label,
                          style: TextStyle(fontSize: 9, color: accentColor, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    Text(DateFormat('dd/MM/yy HH:mm').format(date),
                        style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(description,
                    style: const TextStyle(fontSize: 12, color: Colors.black87, decoration: TextDecoration.none)),
                if (actorName.isNotEmpty)
                  Text(actorName,
                      style: TextStyle(fontSize: 10, color: Colors.grey[500], decoration: TextDecoration.none)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(Map<String, dynamic> data) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    DateTime date;
    try {
      final dynDate = data['scheduled_at'];
      if (dynDate is DateTime) {
        date = dynDate;
      } else if (dynDate is String) {
        date = DateTime.parse(dynDate);
      } else {
        date = DateTime.now();
      }
    } catch (_) {
      date = DateTime.now();
    }
    final double valor = double.tryParse(
            (data['total_price'] ?? data['price'] ?? data['valor_total'] ?? '0')
                .toString()) ??
        0.0;
    final String servico = _cleanServiceName(data['servico_nome'] ??
        data['nome_servico'] ??
        data['service_name'] ??
        'Serviço');
    final String profissional = data['profissional_nome'] ?? '';
    final String rawStatus = (data['status'] ?? 'agendado').toLowerCase();

    // Lógica para tratar agendamentos passados não-cancelados como concluídos visualmente
    bool isPast = date.isBefore(DateTime.now().subtract(const Duration(hours: 4))); // Passado
    bool isCancelled = rawStatus.contains('cancel') || rawStatus.contains('show') || rawStatus == 'ausente';
    bool isCompletedExplicit = rawStatus == 'concluido' || rawStatus == 'concluído' || rawStatus == 'pago' || rawStatus == 'completed';
    
    String status = rawStatus;
    if (!isCompletedExplicit && isPast && !isCancelled) {
       status = 'concluido'; // Força para a UI
    }

    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.schedule;
    if (status == 'concluido' || status == 'concluído' || status == 'pago' || status == 'completed') {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (status == 'cancelado') {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
    } else if (status == 'agendado') {
      statusColor = Colors.blue;
      statusIcon = Icons.event;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Data no lado esquerdo
          Container(
            width: 42,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(DateFormat('dd').format(date),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                Text(DateFormat('MMM').format(date),
                    style: TextStyle(fontSize: 10, color: Colors.grey[600])),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Conteúdo
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(servico,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13, decoration: TextDecoration.none, color: Colors.black)),
                if (profissional.isNotEmpty)
                  Text(profissional,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500], decoration: TextDecoration.none)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(status.toUpperCase(),
                        style: TextStyle(
                            fontSize: 10,
                            color: statusColor,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),

          // Valor
          Text(currency.format(valor),
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildUpcomingCard(Map<String, dynamic> data) {
    DateTime date;
    try {
      final dynDate = data['scheduled_at'];
      if (dynDate is DateTime) {
        date = dynDate;
      } else if (dynDate is String) {
        date = DateTime.parse(dynDate);
      } else {
        date = DateTime.now();
      }
    } catch (_) {
      date = DateTime.now();
    }
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final double valor = double.tryParse(
            (data['total_price'] ?? data['price'] ?? data['valor_total'] ?? '0')
                .toString()) ??
        0.0;
    final String servico = data['servico_nome'] ??
        data['nome_servico'] ??
        data['service_name'] ??
        'Serviço';
    final String horario = DateFormat('HH:mm').format(date);
    final String profissional = data['profissional_nome'] ?? '';

    final bool isToday = DateFormat('yyyyMMdd').format(date) ==
        DateFormat('yyyyMMdd').format(DateTime.now());

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isToday
            ? AppColors.primaryPurple.withValues(alpha: 0.06)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isToday
                ? AppColors.primaryPurple.withValues(alpha: 0.3)
                : Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          // Datetime badge
          Container(
            width: 46,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: isToday ? AppColors.primaryPurple : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(DateFormat('dd').format(date),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isToday ? Colors.white : Colors.black)),
                Text(DateFormat('MMM').format(date),
                    style: TextStyle(
                        fontSize: 10,
                        color: isToday ? Colors.white70 : Colors.grey[600])),
              ],
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isToday)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: AppColors.primaryPurple,
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text('HOJE',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                    Expanded(
                      child: Text(servico,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13, decoration: TextDecoration.none, color: Colors.black),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 11, color: Colors.grey),
                    const SizedBox(width: 3),
                    Text(horario,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                    if (profissional.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.person_outline,
                          size: 11, color: Colors.grey),
                      const SizedBox(width: 3),
                      Text(profissional,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ],
                  ],
                ),
              ],
            ),
          ),

          Text(currency.format(valor),
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _emptyState({required IconData icon, required String message}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: Colors.grey[200]),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(color: Colors.grey[400], fontSize: 14)),
        ],
      ),
    );
  }
}
