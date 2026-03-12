import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

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
  String? shopId;
  bool _isLoading = true;
  bool _showTagEditor = false;
  List<String> _manualTags = [];
  final TextEditingController _customTagController = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadShopId();
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
      if (id != null) _loadTags(id);
    }
  }

  Future<void> _loadTags(String sid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(sid)
          .collection('clients')
          .doc(widget.clientId)
          .get();
      if (mounted && doc.exists) {
        final data = doc.data()!;
        final tags = List<String>.from(data['manualTags'] ?? []);
        setState(() => _manualTags = tags);
      }
    } catch (e) {
      debugPrint('Erro ao carregar tags: $e');
    }
  }

  Future<void> _saveTags() async {
    if (shopId == null) return;
    try {
      // Deriva a classificação oficial baseada nas tags manuais
      String? classification;
      if (_manualTags.contains('Problemático')) {
        classification = 'problematico';
      } else if (_manualTags.contains('VIP')) {
        classification = 'vip';
      } else if (_manualTags.contains('Sumido')) {
        classification = 'sumido';
      } else if (_manualTags.contains('Novo')) {
        classification = 'novo';
      }

      await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .collection('clients')
          .doc(widget.clientId)
          .set({
        'manualTags': _manualTags,
        if (classification != null) 'classification': classification,
        // Se houver uma classificação manual definida, marcamos como override
        'classificationOverride': classification != null,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Erro ao salvar tags: $e');
    }
  }

  void _togglePresetTag(String label) {
    setState(() {
      if (_manualTags.contains(label)) {
        _manualTags.remove(label);
      } else {
        // Regra de exclusividade: VIP e Problemático não podem coexistir
        if (label == 'VIP') {
          _manualTags.remove('Problemático');
        } else if (label == 'Problemático') {
          _manualTags.remove('VIP');
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

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    return text.toLowerCase().split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  Future<void> _editClientDetails() async {
    final TextEditingController nameEditController =
        TextEditingController(text: widget.clientData['nome']);

    // Máscara dinâmica para 10 ou 11 dígitos
    String initialPhone = widget.clientData['telefone'] ?? '';
    if (initialPhone == 'Não informado') initialPhone = '';
    initialPhone = initialPhone.replaceAll(RegExp(r'\D'), '');

    final phoneMask = MaskTextInputFormatter(
      mask: initialPhone.length > 10 ? '(##) #####-####' : '(##) ####-####',
      filter: {"#": RegExp(r'[0-9]')},
      initialText: initialPhone,
    );

    final TextEditingController phoneEditController =
        TextEditingController(text: phoneMask.maskText(initialPhone));

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryPurple.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_rounded,
                    color: AppColors.primaryPurple, size: 20),
              ),
              const SizedBox(width: 12),
              const Text(
                "Editar Cliente",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameEditController,
                decoration: InputDecoration(
                  labelText: "Nome Completo",
                  prefixIcon: const Icon(Icons.person_outline_rounded,
                      color: AppColors.primaryPurple),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneEditController,
                onChanged: (v) {
                  final unmasked = phoneMask.getUnmaskedText();
                  if (unmasked.length <= 10 &&
                      phoneMask.getMask() != '(##) ####-####') {
                    setDialogState(() {
                      phoneMask.updateMask(mask: '(##) ####-####');
                    });
                  } else if (unmasked.length > 10 &&
                      phoneMask.getMask() != '(##) #####-####') {
                    setDialogState(() {
                      phoneMask.updateMask(mask: '(##) #####-####');
                    });
                  }
                },
                inputFormatters: [phoneMask],
                decoration: InputDecoration(
                  labelText: "Telefone/WhatsApp",
                  prefixIcon: const Icon(Icons.phone_iphone_rounded,
                      color: AppColors.primaryPurple),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          actionsPadding:
              const EdgeInsets.only(right: 16, bottom: 16, left: 16),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text("Cancelar",
                        style: TextStyle(color: Colors.grey)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, {
                      'nome': nameEditController.text,
                      'telefone': phoneMask.getUnmaskedText(),
                    }),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text("SALVAR",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        );
      }),
    );

    if (result != null) {
      final String newName = _toTitleCase(result['nome']?.trim() ?? '');
      final String newPhone =
          result['telefone']?.trim().replaceAll(RegExp(r'[^0-9]'), '') ?? '';

      final bool nameChanged =
          newName.isNotEmpty && newName != widget.clientData['nome'];
      final bool phoneChanged = newPhone != widget.clientData['telefone'];

      if (nameChanged || phoneChanged) {
        setState(() => _isLoading = true);
        try {
          Map<String, dynamic> updateData = {};
          if (nameChanged) updateData['nome'] = newName;
          if (phoneChanged) {
            updateData['telefone'] = newPhone;
            updateData['whatsapp'] = newPhone;
          }

          // 1. Atualiza no perfil do cliente (subcoleção da loja)
          if (shopId != null) {
            await FirebaseFirestore.instance
                .collection('shops')
                .doc(shopId)
                .collection('clients')
                .doc(widget.clientId)
                .set(updateData, SetOptions(merge: true));
          }

          // 2. Atualiza no documento global do usuário (se existir)
          await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.clientId)
              .set(updateData, SetOptions(merge: true));

          if (mounted) {
            setState(() {
              if (nameChanged) widget.clientData['nome'] = newName;
              if (phoneChanged) widget.clientData['telefone'] = newPhone;
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text("Cadastro atualizado com sucesso!")));
          }
        } catch (e) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Erro ao atualizar cadastro: $e")));
          }
        }
      }
    }
  }

  // Stream de histórico (passado)
  Stream<QuerySnapshot> _getHistoryStream() {
    final query = FirebaseFirestore.instance
        .collection('appointments')
        .where('shopId', isEqualTo: shopId);

    if (widget.clientData['origem'] == 'manual') {
      final tel = widget.clientData['telefone'] ?? '';
      final nome = widget.clientData['nome'] ?? '';
      if (tel.isNotEmpty && tel != 'Não informado') {
        return query
            .where('client_phone', isEqualTo: tel)
            .orderBy('data_agendamento', descending: true)
            .snapshots();
      } else {
        return query
            .where('client_name', isEqualTo: nome)
            .orderBy('data_agendamento', descending: true)
            .snapshots();
      }
    }

    return query
        .where('clientId', isEqualTo: widget.clientId)
        .orderBy('data_agendamento', descending: true)
        .snapshots();
  }

  // Stream de próximos agendamentos
  Stream<QuerySnapshot> _getUpcomingStream() {
    final now = DateTime.now();
    final query = FirebaseFirestore.instance
        .collection('appointments')
        .where('shopId', isEqualTo: shopId)
        .where('data_agendamento',
            isGreaterThanOrEqualTo: Timestamp.fromDate(now));

    if (widget.clientData['origem'] == 'manual') {
      final tel = widget.clientData['telefone'] ?? '';
      if (tel.isNotEmpty && tel != 'Não informado') {
        return query
            .where('client_phone', isEqualTo: tel)
            .orderBy('data_agendamento', descending: false)
            .limit(5)
            .snapshots();
      }
    }

    return query
        .where('clientId', isEqualTo: widget.clientId)
        .orderBy('data_agendamento', descending: false)
        .limit(5)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primaryPurple));
    }

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
                          GestureDetector(
                            onTap: _launchWhatsApp,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.chat,
                                    size: 12, color: Colors.green),
                                const SizedBox(width: 4),
                                Text(telefone,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.green)),
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

        // ── KPI BAR ───────────────────────────────────────────────────
        StreamBuilder<QuerySnapshot>(
          stream: _getHistoryStream(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? [];
            final currency =
                NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

            // Calcula KPIs
            double totalGasto = 0;
            DateTime? lastVisit;
            int completed = 0;

            for (final doc in docs) {
              final d = doc.data() as Map<String, dynamic>;
              final val =
                  double.tryParse(d['valor_total']?.toString() ?? '0') ?? 0;
              final status = (d['status'] ?? '').toString().toLowerCase();
              if (status == 'concluido' || status == 'pago') {
                totalGasto += val;
                completed++;
              }
              final ts = d['data_agendamento'] as Timestamp?;
              if (ts != null) {
                final dt = ts.toDate();
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

            return Container(
              color: const Color(0xFFF8F9FD),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _kpiItem(
                      label: 'Última Visita',
                      value: lastVisitStr,
                      icon: Icons.history,
                      color: themeColor),
                  _kpiDivider(),
                  _kpiItem(
                      label: 'Ticket Médio',
                      value:
                          ticketMedio > 0 ? currency.format(ticketMedio) : '--',
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
                onTap: () => setState(() => _showTagEditor = !_showTagEditor),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.04),
                    border: Border(
                        top: BorderSide(
                            color: AppColors.primaryPurple
                                .withValues(alpha: 0.1))),
                  ),
                  child: Row(
                    children: [
                      Icon(_showTagEditor ? Icons.label : Icons.label_outline,
                          size: 16, color: AppColors.primaryPurple),
                      const SizedBox(width: 6),
                      Text(
                          _showTagEditor
                              ? 'Ocultar editor de tags'
                              : 'Gerenciar Tags',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primaryPurple,
                              fontWeight: FontWeight.w600)),
                      const Spacer(),
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
              StreamBuilder<QuerySnapshot>(
                stream: _getHistoryStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data?.docs ?? [];
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
                      final data = docs[i].data() as Map<String, dynamic>;
                      return _buildHistoryCard(data);
                    },
                  );
                },
              ),

              // ABA 2: PRÓXIMOS
              StreamBuilder<QuerySnapshot>(
                stream: _getUpcomingStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data?.docs ?? [];
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
                      final data = docs[i].data() as Map<String, dynamic>;
                      return _buildUpcomingCard(data);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ],
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
      date = (data['data_agendamento'] as Timestamp).toDate();
    } catch (_) {
      date = DateTime.now();
    }
    final double valor =
        double.tryParse(data['valor_total']?.toString() ?? '0') ?? 0.0;
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
      date = (data['data_agendamento'] as Timestamp).toDate();
    } catch (_) {
      date = DateTime.now();
    }
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final double valor =
        double.tryParse(data['valor_total']?.toString() ?? '0') ?? 0.0;
    final String servico = data['servico_nome'] ??
        data['nome_servico'] ??
        data['service_name'] ??
        'Serviço';
    final String horario = data['horario'] ?? DateFormat('HH:mm').format(date);
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
