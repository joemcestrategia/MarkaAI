import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/services/plan_features_service.dart';
import '../../core/constants/plan_features.dart';
import '../../widgets/upgrade_modal.dart';
import 'edit_client_page.dart';

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
      var query = _supabase.from('users').select().eq('id', widget.clientId);
      var doc = await query.maybeSingle();

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
      }
    }
  }

  Future<void> _loadFeatures(String sid) async {
    // Features are now handled by StreamBuilder in build()
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

  Future<void> _launchWhatsApp() async {
    String phone = widget.clientData['telefone'] ?? '';
    phone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Telefone não cadastrado.')));
      }
      return;
    }
    if (phone.length <= 11) phone = '55$phone';
    final url = Uri.parse('https://wa.me/$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _editClientDetails() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => EditClientPage(
          clientData: widget.clientData,
          clientId: widget.clientId,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        // Atualiza os dados locais com o que voltou da página de edição
        widget.clientData['nome'] = result['name'];
        widget.clientData['name'] = result['name'];
        widget.clientData['telefone'] = result['phone'];
        widget.clientData['cpf'] = result['cpf'];
        widget.clientData['birthDate'] = result['birth_date'];
        widget.clientData['zipCode'] = result['zip_code'];
        widget.clientData['street'] = result['street'];
        widget.clientData['neighborhood'] = result['neighborhood'];
        widget.clientData['city'] = result['city'];
        widget.clientData['state'] = result['state'];
        widget.clientData['number'] = result['number'];
      });
    }
  }

  // Stream de histórico (passado)
  Stream<List<Map<String, dynamic>>> _getHistoryStream() {
    if (shopId == null) return const Stream.empty();

    final query = _supabase
        .from('appointments')
        .stream(primaryKey: ['id']);

    return query.map((list) {
      final filtered = list.where((d) {
        final matchesShop = (d['shop_id'] ?? d['shopId']) == shopId;
        if (!matchesShop) return false;

        if (widget.clientData['origem'] == 'manual') {
          final tel = widget.clientData['telefone'] ?? '';
          final nome = widget.clientData['nome'] ?? '';
          if (tel.isNotEmpty && tel != 'Não informado') {
            return d['client_phone'] == tel;
          } else {
            return d['client_name'] == nome;
          }
        }
        return (d['client_id'] ?? d['clientId']) == widget.clientId;
      }).toList();

      // Ordenar manualmente já que não podemos usar .order() com filtros no stream
      filtered.sort((a, b) {
        final dateA = DateTime.tryParse(a['scheduled_at'].toString()) ?? DateTime(2000);
        final dateB = DateTime.tryParse(b['scheduled_at'].toString()) ?? DateTime(2000);
        return dateB.compareTo(dateA); // asscending: false
      });

      return filtered;
    });
  }

  // Stream de próximos agendamentos
  Stream<List<Map<String, dynamic>>> _getUpcomingStream() {
    if (shopId == null) return const Stream.empty();
    final now = DateTime.now();

    final query = _supabase
        .from('appointments')
        .stream(primaryKey: ['id']);

    return query.map((list) {
      final filtered = list.where((d) {
        final matchesShop = (d['shop_id'] ?? d['shopId']) == shopId;
        if (!matchesShop) return false;

        final appDate = DateTime.tryParse(d['scheduled_at'].toString()) ?? DateTime(2000);
        if (appDate.isBefore(now)) return false;

        if (widget.clientData['origem'] == 'manual') {
          final tel = widget.clientData['telefone'] ?? '';
          if (tel.isNotEmpty && tel != 'Não informado') {
            return d['client_phone'] == tel;
          }
        }
        return (d['client_id'] ?? d['clientId']) == widget.clientId;
      }).toList();

      filtered.sort((a, b) {
        final dateA = DateTime.tryParse(a['scheduled_at'].toString()) ?? DateTime(2000);
        final dateB = DateTime.tryParse(b['scheduled_at'].toString()) ?? DateTime(2000);
        return dateA.compareTo(dateB); // ascending: true
      });

      return filtered.take(5).toList();
    });
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

        final nome = widget.clientData['nome'] ?? 'Cliente';
        final telefone = widget.clientData['telefone'] ?? '';
        final foto =
            widget.clientData['foto'] ?? widget.clientData['foto_perfil'] ?? '';
        final bool isManual = widget.clientData['origem'] == 'manual';
        final Color themeColor = isManual ? Colors.orange : AppColors.primaryPurple;
        final initials = nome.isNotEmpty ? nome[0].toUpperCase() : '?';

        return Column(
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
                  // Avatar pequeno
                  Container(
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
                        if (telefone.isNotEmpty && telefone != 'Não informado')
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: ElevatedButton.icon(
                              onPressed: _launchWhatsApp,
                              icon: const Icon(Icons.chat_rounded, size: 14),
                              label: const Text("WhatsApp", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                                minimumSize: const Size(0, 32),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          )
                        else if ((widget.clientData['email'] ?? '').toString().isNotEmpty)
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
                      IconButton(
                        onPressed: _editClientDetails,
                        icon: const Icon(Icons.edit_outlined,
                            size: 20, color: AppColors.primaryPurple),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Editar cadastro',
                      ),
                      const SizedBox(width: 12),
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
          final state = widget.clientData['state']?.toString() ?? '';
          final street = widget.clientData['street']?.toString() ?? '';
          final number = widget.clientData['number']?.toString() ?? '';
          final neighborhood = widget.clientData['neighborhood']?.toString() ?? '';
          final zipCode = widget.clientData['zipCode']?.toString() ?? '';

          if (city.isEmpty && street.isEmpty) return const SizedBox.shrink();

          String line1 = '';
          if (street.isNotEmpty) {
            line1 = street;
            if (number.isNotEmpty) line1 += ', $number';
            if (neighborhood.isNotEmpty) line1 += ' - $neighborhood';
          }
          String line2 = '';
          if (city.isNotEmpty) {
            line2 = city;
            if (state.isNotEmpty) line2 += ', $state';
            if (zipCode.isNotEmpty) line2 += ' - CEP $zipCode';
          }

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

            for (final d in docs) {
              final val =
                  double.tryParse(d['valor_total']?.toString() ?? '0') ?? 0;
              final status = (d['status'] ?? '').toString().toLowerCase();
              if (status == 'concluido' || status == 'pago') {
                totalGasto += val;
                completed++;
              }
              
              final dynDate = d['scheduled_at'];
              if (dynDate != null) {
                DateTime dt;
                if (dynDate is DateTime) {
                  dt = dynDate;
                } else {
                  dt = DateTime.parse(dynDate.toString());
                }
                
                if (lastVisit == null || dt.isAfter(lastVisit)) {
                  // Only past dates for "last visit"
                  if (dt.isBefore(DateTime.now())) lastVisit = dt;
                }
              }
            }

            final ticketMedio = completed > 0 ? totalGasto / completed : 0.0;
            final lastVisitStr = lastVisit != null
                ? DateFormat('dd/MM/yy').format(lastVisit)
                : '--';

            // Dados pré-calculados vindos do BusinessClientsScreen
            final prefService = widget.clientData['servicoPreferido'] ?? '--';
            final int avgInterval = widget.clientData['intervaloMedio'] ?? 0;

            return Container(
              color: const Color(0xFFF8F9FD),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      _kpiItem(
                          label: 'Última Visita',
                          value: lastVisitStr,
                          icon: Icons.history,
                          color: themeColor),
                      _kpiDivider(),
                      _kpiItem(
                          label: 'Ticket Médio',
                          value: ticketMedio > 0 ? currency.format(ticketMedio) : '--',
                          icon: Icons.receipt_long,
                          color: Colors.green),
                      _kpiDivider(),
                      _kpiItem(
                          label: 'Visitas',
                          value: '${docs.length}',
                          icon: Icons.calendar_today,
                          color: Colors.blue),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _kpiItem(
                          label: 'Serviço Preferido',
                          value: prefService,
                          icon: Icons.favorite_outline,
                          color: Colors.pink),
                      _kpiDivider(),
                      _kpiItem(
                          label: 'Intervalo Médio',
                          value: avgInterval > 0 ? '$avgInterval dias' : '--',
                          icon: Icons.timer_outlined,
                          color: Colors.orange),
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
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _getHistoryStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data ?? [];
                  if (docs.isEmpty) {
                    return _emptyState(
                        icon: Icons.history,
                        message: 'Nenhum histórico encontrado');
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      return _buildHistoryCard(docs[i]);
                    },
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
    final String servico = data['servico_nome'] ??
        data['nome_servico'] ??
        data['service_name'] ??
        'Serviço';
    final String profissional = data['profissional_nome'] ?? '';
    final String status = (data['status'] ?? 'agendado').toLowerCase();

    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.schedule;
    if (status == 'concluido' || status == 'pago') {
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
                        fontWeight: FontWeight.bold, fontSize: 13)),
                if (profissional.isNotEmpty)
                  Text(profissional,
                      style: TextStyle(fontSize: 11, color: Colors.grey[500])),
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
                              fontWeight: FontWeight.bold, fontSize: 13),
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
