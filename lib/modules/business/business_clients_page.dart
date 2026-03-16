import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rxdart/rxdart.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/string_utils.dart';
import '../clients/client_register_page.dart';
import '../clients/client_details_page.dart';
import 'subscription_service.dart';
import '../../core/services/client_cache_service.dart';
import '../../core/services/plan_features_service.dart';
import '../../core/constants/plan_features.dart';
import '../../widgets/upgrade_modal.dart';

class BusinessClientsScreen extends StatefulWidget {
  const BusinessClientsScreen({super.key});

  @override
  State<BusinessClientsScreen> createState() => _BusinessClientsScreenState();
}

class _BusinessClientsScreenState extends State<BusinessClientsScreen> {
  String? shopId;
  bool _isLoadingId = true;

  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";

  // 0 = App (Vinculados), 1 = Manual (Walk-in)
  int _selectedTabIndex = 0;

  // Filtro de Tags: "Todos", "VIP", "Sumido", "Problematico"
  String _selectedTagFilter = "Todos";

  // --- CONTROLE DA COLUNA 3 (PC) ---
  Map<String, dynamic>? _selectedClientData;
  String? _selectedClientId;
  bool _showAddPanel = false;

  // --- CACHE LOCAL ---
  Map<String, List<Map<String, dynamic>>>? _cachedData;

  PlanFeatures _currentFeatures = planFeaturesConfig[PlanKey.free]!;

  @override
  void initState() {
    super.initState();
    _loadShopId();
  }

  Future<void> _loadShopId() async {
    final id = await SessionService.getShopId();
    if (mounted) {
      if (id != null) {
        _loadFromCache(id);
        _loadFeatures(id);
      }
      setState(() {
        shopId = id;
        if (id == null) {
          debugPrint("Erro: ShopID é null ao carregar BusinessClientsScreen");
        }
        _isLoadingId = false;
      });
    }
  }

  Future<void> _loadFeatures(String sid) async {
    // Features are now handled by StreamBuilder in build()
  }

  Future<void> _loadFromCache(String id) async {
    final data = await ClientCacheService.getCachedClients(id);
    if (data != null && mounted) {
      setState(() {
        _cachedData = data;
      });
    }
  }

  // ?? LÓGICA INTELIGENTE DE NAVEGAÇÃO
  void _handleClientTap(BuildContext context, Map<String, dynamic> client,
      String id, bool isMobile) {
    if (isMobile) {
      // ?? MODO CELULAR: Navega para nova tela
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
                title: Text(client['nome']),
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                elevation: 0),
            body: ClientDetailsPage(
              clientData: client,
              clientId: id,
              onClose: () => Navigator.pop(context),
            ),
          ),
        ),
      );
    } else {
      // ?? MODO PC: Abre na lateral
      setState(() {
        _showAddPanel = false;
        _selectedClientData = client;
        _selectedClientId = id;
      });
    }
  }

  void _handleNewClientTap(bool isMobile) async {
    // ?? GATING: Verifica se o plano permite adicionar mais clientes

    // Nota: Isso conta agendamentos, o que é um proxy ruim para "clientes únicos".
    // Mas como a arquitetura atual não tem uma coleção 'clients' isolada para o business,
    // vamos assumir que o limite é checado contra a INTENÇÃO.
    // Melhor abordagem: Verificar o plano diretamente. Se for GRATUITO, faz uma verificação mais estrita.

    // Vamos usar uma contagem baseada na lista processada em memória se possível, mas aqui estamos fora do build.
    // Vamos confiar no SubscriptionService. A contagem passada será 50 (exemplo) se quisermos bloquear.
    // O correto seria:
    // int currentClients = ...;
    // bool canAdd = await SubscriptionService.canAddClient(currentClients);

    // Como identificar clientes únicos no Firestore seria custoso (leitura de todos docs),
    // vamos assumir que se o plano é Starter, a gente puxa os ultimos 50 e ve se tem 50 unicos.
    // Se tiver, bloqueia.

    // Verificação de limite de plano
    final snapshot = await FirebaseFirestore.instance
        .collection('appointments')
        .where('shopId', isEqualTo: shopId)
        .get();

    final uniqueClients =
        snapshot.docs.map((d) => d['clientId'] ?? d['client_phone']).toSet();

    final canAdd = await SubscriptionService.canAddClient(uniqueClients.length);

    if (!canAdd) {
      if (mounted) {
        UpgradeModal.show(
          context,
          featureName: "Limite de Clientes",
          requiredPlan: "Start",
        );
      }
      return;
    }

    if (!mounted) return;

    if (isMobile) {
      // ?? MODO CELULAR: Navega para nova tela
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
                title: const Text("Novo Cliente"),
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                elevation: 0),
            body: const ClientRegisterPage(isBusinessAdding: true),
          ),
        ),
      );
    } else {
      // ?? MODO PC: Abre na lateral
      setState(() {
        _selectedClientData = null;
        _selectedClientId = null;
        _showAddPanel = true;
      });
    }
  }

  void _closePanel() {
    setState(() {
      _selectedClientData = null;
      _selectedClientId = null;
      _showAddPanel = false;
    });
  }

  Future<void> _launchWhatsApp(String telefone) async {
    // Remove caracteres não numéricos
    final phone = telefone.replaceAll(RegExp(r'[^0-9]'), '');

    if (phone.isEmpty || phone == "Nãoinformado") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cliente não possui telefone cadastrado'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final uri = Uri.parse('https://wa.me/55$phone');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Não foi possível abrir o WhatsApp'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir WhatsApp: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // ?? STREAM REATIVO COMBINADO
  Stream<Map<String, dynamic>> _buildCombinedStream() {
    if (shopId == null) return const Stream.empty();

    final appointmentsStream = FirebaseFirestore.instance
        .collection('appointments')
        .where('shopId', isEqualTo: shopId)
        .orderBy('data_agendamento', descending: true)
        .snapshots();

    final clientSettingsStream = FirebaseFirestore.instance
        .collection('shops')
        .doc(shopId)
        .collection('clients')
        .snapshots();
        
    final shopStream = FirebaseFirestore.instance
        .collection('shops')
        .doc(shopId)
        .snapshots();

    final featuresStream = PlanFeaturesService.streamFeaturesByShopId(shopId!);

    return Rx.combineLatest4(
      appointmentsStream,
      clientSettingsStream,
      shopStream,
      featuresStream,
      (appointmentsSnap, clientsSnap, shopSnap, features) {
        return {
          'appointments': appointmentsSnap.docs,
          'clients': clientsSnap.docs,
          'shop': shopSnap.data() ?? {},
          'features': features,
        };
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingId) return const Center(child: CircularProgressIndicator());

    return StreamBuilder<Map<String, dynamic>>(
      stream: _buildCombinedStream(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final data = snapshot.data!;
          _currentFeatures = data['features'] as PlanFeatures;
        }

        // ??? O GUARDIÃO DO LAYOUT: Verifica a largura da tela
        return LayoutBuilder(
          builder: (context, constraints) {
            // Se a largura for menor que 850px, consideramos "Mobile/Tablet Pequeno"
            bool isMobile = constraints.maxWidth < 850;

            if (isMobile) {
              // --- LAYOUT MOBILE (Apenas Lista) ---
              return Material(
                color: const Color(0xFFF2F4F8),
                child: _buildListContent(isMobile),
              );
            } else {
              // --- LAYOUT DESKTOP (Split View) ---
              return Material(
                color: const Color(0xFFF2F4F8),
                child: Row(
                  children: [
                    // COLUNA 2: LISTA DE CLIENTES
                    Expanded(
                      flex: 3,
                      child: _buildListContent(isMobile),
                    ),
                    // COLUNA 3: PAINEL LATERAL
                    VerticalDivider(width: 1, color: Colors.grey[300]),
                    Expanded(
                      flex: 2,
                      child: Container(
                        color: Colors.white,
                        child: _showAddPanel
                            ? const ClientRegisterPage(isBusinessAdding: true)
                            : (_selectedClientData != null
                                ? ClientDetailsPage(
                                    key: ValueKey(_selectedClientId),
                                    clientData: _selectedClientData!,
                                    clientId: _selectedClientId!,
                                    onClose: _closePanel,
                                  )
                                : _buildPlaceholder()),
                      ),
                    ),
                  ],
                ),
              );
            }
          },
        );
      },
    );
  }

  // ?? WIDGET EXTRAÍDO: Conteúdo da Lista (Reusável)
  Widget _buildListContent(bool isMobile) {
    return Column(
      children: [
        // 1. BARRA DE PESQUISA
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) =>
                      setState(() => _searchText = value.toLowerCase()),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Buscar por nome...",
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.primaryPurple, size: 20),
                    suffixIcon: _searchText.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => setState(() {
                                  _searchController.clear();
                                  _searchText = "";
                                }))
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF5F7FA),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              ElevatedButton.icon(
                onPressed: () => _handleNewClientTap(isMobile),
                icon: const Icon(Icons.person_add, size: 18),
                label: Text(isMobile
                    ? "NOVO"
                    : "NOVO CLIENTE"), // Texto menor no mobile
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),

        // 2. ABAS (TABS) CUSTOMIZADAS
        Container(
          width: double.infinity, // Garante largura total
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
            ],
          ),
          child: SingleChildScrollView(
            // Permite rolar as abas em telas muito pequenas
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTabButton(0, "Pelo App", Icons.smartphone),
                const SizedBox(width: 15),
                _buildTabButton(1, "Manuais", Icons.edit_note),
              ],
            ),
          ),
        ),

        // 2.5 FILTROS DE TAGS (VIP, SUMIDO, PROBLEMATICO)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          color: Colors.white,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTagFilterChip("Todos"),
                const SizedBox(width: 8),
                _buildTagFilterChip("VIP", icon: Icons.star, color: Colors.amber, isLocked: !_currentFeatures.clientFilter),
                const SizedBox(width: 8),
                _buildTagFilterChip("Novo", icon: Icons.new_releases, color: Colors.green, isLocked: !_currentFeatures.clientFilter),
                const SizedBox(width: 8),
                _buildTagFilterChip("Sumido",
                    icon: Icons.timer_off_outlined, color: Colors.grey, isLocked: !_currentFeatures.clientFilter),
                const SizedBox(width: 8),
                _buildTagFilterChip("Problemático",
                    icon: Icons.warning_amber_rounded, color: Colors.red, isLocked: !_currentFeatures.clientFilter),
              ],
            ),
          ),
        ),

        // 3. LISTA FILTRADA
        shopId == null
            ? const Center(child: Text("Erro: ID da Loja não encontrado"))
            : Expanded(
                child: StreamBuilder<Map<String, dynamic>>(
                  stream: _buildCombinedStream(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      debugPrint("Erro no stream combinado: ${snapshot.error}");
                      return const Center(child: Text("Erro ao carregar dados"));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final data = snapshot.data!;
                    final appointmentDocs = data['appointments'] as List<QueryDocumentSnapshot>;
                    final clientSettingsDocs = data['clients'] as List<QueryDocumentSnapshot>;
                    final shopConfig = (data['shop'] as Map?)?['config'] as Map? ?? {};
                    _currentFeatures = data['features'] as PlanFeatures;

                    final Map<String, Map<String, dynamic>> clientSettings = {
                      for (var doc in clientSettingsDocs)
                        doc.id: doc.data() as Map<String, dynamic>
                    };

                    _cachedData = _processAppointments(
                        appointmentDocs,
                        clientSettings,
                        shopConfig);

                    List<Map<String, dynamic>> targetList =
                        _selectedTabIndex == 0
                            ? _cachedData!['app']!
                            : _cachedData!['manual']!;

                    final filteredDocs = targetList.where((client) {
                      // Filtro de Texto
                      final nome = (client['nome'] ?? "").toString();
                      final normalizedNome =
                          StringUtils.removeDiacritics(nome)
                              .toLowerCase();
                      final normalizedSearch =
                          StringUtils.removeDiacritics(_searchText)
                              .toLowerCase();
                      bool matchesSearch = normalizedNome.contains(normalizedSearch);

                      if (!matchesSearch) return false;

                      // Filtro de Tags
                      if (_selectedTagFilter == "Todos") return true;

                      final List tags = client['tags'] as List? ?? [];
                      final String? classification = client['classification']?.toString().toLowerCase();

                      if (_selectedTagFilter == "VIP") {
                        return tags.contains('vip') || classification == 'vip';
                      }
                      if (_selectedTagFilter == "Novo") {
                        return tags.contains('novo') || classification == 'novo';
                      }
                      if (_selectedTagFilter == "Sumido") {
                        return tags.contains('sumido') || classification == 'sumido';
                      }
                      if (_selectedTagFilter == "Problemático") {
                        return classification == 'problematico' || tags.contains('problematico');
                      }

                      return true;
                    }).toList();

                    if (filteredDocs.isEmpty) return _buildEmptyState();

                    return ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, index) {
                        final client = filteredDocs[index];
                        bool isSelected = !isMobile &&
                            _selectedClientId == client['id'];

                        return _buildClientListItem(
                            client, isSelected, isMobile);
                      },
                    );
                  },
                ),
              ),
      ],
    );
  }

  // ... (Mantenha o _processAppointments IGUAL ao anterior, não mudei nada nele) ...
  Map<String, List<Map<String, dynamic>>> _processAppointments(
      List<QueryDocumentSnapshot> docs,
      Map<String, Map<String, dynamic>> clientSettings,
      Map<dynamic, dynamic> shopConfig) {
    Map<String, Map<String, dynamic>> appClientsMap = {};
    Map<String, Map<String, dynamic>> manualClientsMap = {};

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;

      String nome = data['client_nome'] ??
          data['client_name'] ??
          data['clientName'] ??
          data['cliente_nome'] ??
          "Cliente Desconhecido";
      String telefone =
          data['client_phone'] ?? data['telefone'] ?? data['whatsapp'] ?? "";
      String? userId = data['clientId'];

      bool isManual = (userId == null || userId.isEmpty);

      String key;
      if (!isManual) {
        key = userId;
      } else {
        key = telefone.isNotEmpty ? telefone : "doc_${doc.id}";
      }

      double valor =
          double.tryParse(data['valor_total']?.toString() ?? "0") ?? 0.0;
      DateTime dataVisita;
      try {
        dataVisita = (data['data_agendamento'] as Timestamp).toDate();
      } catch (e) {
        dataVisita = DateTime.now();
      }

      var targetMap = isManual ? manualClientsMap : appClientsMap;

      if (!targetMap.containsKey(key)) {
        targetMap[key] = {
          'id': key,
          'nome': nome,
          'telefone': telefone.isNotEmpty ? telefone : "Não informado",
          'foto': null,
          'origem': isManual ? 'manual' : 'app',
          'totalGasto': valor,
          'visitas': 1,
          'primeiraVisita': dataVisita, // Keep track for avg interval
          'ultimaVisita': dataVisita,
          'email': "",
          'birthDate':
              data['data_nascimento'] ?? data['nascimento'] ?? data['birthDate']
        };
      } else {
        targetMap[key]!['totalGasto'] += valor;
        targetMap[key]!['visitas'] += 1;

        // Update range
        if (dataVisita.isBefore(targetMap[key]!['primeiraVisita'])) {
          targetMap[key]!['primeiraVisita'] = dataVisita;
        }
        if (dataVisita.isAfter(targetMap[key]!['ultimaVisita'])) {
          targetMap[key]!['ultimaVisita'] = dataVisita;
        }

        if (nome != "Cliente Desconhecido") {
          targetMap[key]!['nome'] = nome;
        }
      }
    }

    final allApps = appClientsMap.values.toList();

    // 2. Add 'Vip', 'Novo', 'Sumido' tags AND Manual Classification Override
    final now = DateTime.now();

    // Configurações da loja
    final int vipMinVisits = shopConfig['vip_min_visits'] ?? 15;
    final int vipAvgInterval = shopConfig['vip_avg_interval'] ?? 30;
    final int sumidoMaxDays = shopConfig['sumido_max_days'] ?? 45;

    for (var c in allApps) {
      final settings = clientSettings[c['id']];
      
      // 1. Calcular tag automática
      String? autoTag;
      final int visits = c['visitas'] as int;
      final DateTime lastVisit = c['ultimaVisita'] as DateTime;
      final DateTime firstVisit = c['primeiraVisita'] as DateTime;

      double avgInterval = 0;
      if (visits > 1) {
        final totalDays = lastVisit.difference(firstVisit).inDays;
        avgInterval = totalDays / (visits - 1);
      }

      final daysSinceLast = now.difference(lastVisit).inDays;
      if (daysSinceLast > sumidoMaxDays) {
        autoTag = 'sumido';
      } else {
        bool meetsVisits = visits >= vipMinVisits;
        bool meetsInterval = visits == 1 || avgInterval <= vipAvgInterval;

        if (meetsVisits && meetsInterval && _currentFeatures.clientClassification) {
          autoTag = 'vip';
        } else if (visits == 1 && daysSinceLast < 30 && _currentFeatures.clientClassification) {
          autoTag = 'novo';
        }
      }

      // 2. Classificação Manual tem PRIORIDADE ABSOLUTA
      String? manualClass = settings?['classification']?.toString().toLowerCase().trim();
      String finalClassification = manualClass ?? autoTag ?? '';
      
      // 3. Mesclar manualTags com a classification
      List<String> displayTags = [];
      if (settings?['manualTags'] != null) {
        // Normaliza tags manuais para lowercase e remove acentos do problematico
        displayTags = (settings!['manualTags'] as List)
            .map((t) => StringUtils.removeDiacritics(t.toString().toLowerCase().trim()))
            .toList();
      }
      
      // Garante que o problematico esteja normalizado na classification também
      if (finalClassification == 'problemático' || finalClassification == 'problematico') {
        finalClassification = 'problematico';
      }

      if (finalClassification.isNotEmpty && !displayTags.contains(finalClassification)) {
        displayTags.insert(0, finalClassification); // Principal primeiro
      }

      c['classification'] = finalClassification;
      c['tags'] = displayTags;
    }

    return {
      'app': allApps,
      // ?? FILTRO DE LIMPEZA: Remove clientes manuais sem telefone
      'manual': manualClientsMap.values
          .where((c) =>
              c['telefone'] != null &&
              c['telefone'].toString().isNotEmpty &&
              c['telefone'] != "Não informado")
          .toList()
    };
  }

  Widget _buildTagFilterChip(String label, {IconData? icon, Color? color, bool isLocked = false}) {
    bool isSelected = _selectedTagFilter == label;
    Color activeColor = color ?? AppColors.primaryPurple;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      avatar: isLocked 
          ? const Icon(Icons.lock, size: 14, color: Colors.grey)
          : (icon != null
              ? Icon(icon, size: 14, color: isSelected ? Colors.white : color)
              : null),
      selectedColor: activeColor,
      backgroundColor: Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(
          color: isSelected ? Colors.transparent : Colors.grey[300]!),
      onSelected: (selected) {
        if (isLocked) {
          UpgradeModal.show(
            context,
            featureName: "Filtros de Clientes",
            requiredPlan: "Plus",
          );
          return;
        }
        if (selected) {
          setState(() => _selectedTagFilter = label);
        }
      },
    );
  }


  Widget _buildTabButton(int index, String label, IconData icon) {
    bool isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() {
        _selectedTabIndex = index;
        _selectedTagFilter = "Todos"; // Reseta filtro ao mudar aba
      }),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (index == 0 ? AppColors.primaryPurple : Colors.orange)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? Border.all(color: Colors.transparent)
              : Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16, color: isSelected ? Colors.white : Colors.grey[600]),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey[600],
                    fontWeight: FontWeight.bold,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildClientListItem(
      Map<String, dynamic> client, bool isSelected, bool isMobile) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    bool isManual = client['origem'] == 'manual';
    Color themeColor = isManual ? Colors.orange : AppColors.primaryPurple;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected ? themeColor.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isSelected
            ? Border.all(color: themeColor, width: 1.5)
            : Border.all(color: Colors.transparent),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 5)
        ],
      ),
      child: ListTile(
        onTap: () => _handleClientTap(
            context, client, client['id'], isMobile), // <--- AQUI A MÁGICA
        leading: CircleAvatar(
          backgroundColor: themeColor.withValues(alpha: 0.1),
          child: Text((client['nome'] ?? "?").substring(0, 1).toUpperCase(),
              style: TextStyle(color: themeColor, fontWeight: FontWeight.bold)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(client['nome'],
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            if (_isBirthdayToday(client['birthDate']))
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(Icons.cake_rounded,
                    color: Colors.pink.shade400, size: 16),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (client['telefone'] != "Não informado")
              Text(client['telefone'], style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 2),
            Text(
                "${client['visitas']} visitas • Total: ${currency.format(client['totalGasto'])}",
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: (client['tags'] as List? ?? [])
                  .map<Widget>((tag) => _buildTagFromType(tag.toString()))
                  .toList(),
            )
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Botão WhatsApp
            if (client['telefone'] != "Não informado")
              IconButton(
                icon: const FaIcon(
                  FontAwesomeIcons.whatsapp,
                  color: Color(0xFF25D366),
                  size: 24,
                ),
                tooltip: 'Chamar no WhatsApp',
                onPressed: () => _launchWhatsApp(client['telefone']),
              ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() => Center(
      child: Opacity(
          opacity: 0.3,
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.analytics_outlined, size: 80),
                SizedBox(height: 16),
                Text("Selecione um cliente",
                    style: TextStyle(fontWeight: FontWeight.bold))
              ])));

  Widget _buildEmptyState() => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.person_off, size: 50, color: Colors.grey[300]),
        const SizedBox(height: 10),
        Text("Não temos clientes cadastrados.",
            style: TextStyle(color: Colors.grey[500]))
      ]));

  Widget _buildTagFromType(String tag) {
    final t = tag.toLowerCase();
    
    // Configurações de Estilo por Tag
    if (t == 'vip') {
      return _buildTag("VIP", Colors.amber, Icons.star);
    } else if (t == 'problematico' || t == 'problemático') {
      return _buildTag("PROBLEMÁTICO", Colors.red.shade700, Icons.warning_amber_rounded);
    } else if (t == 'novo') {
      return _buildTag("NOVO", Colors.green, Icons.new_releases);
    } else if (t == 'sumido') {
      return _buildTag("SUMIDO", Colors.grey, Icons.timer_off_outlined);
    } else {
      // Tags Manuais Genéricas
      return _buildTag(tag.toUpperCase(), AppColors.primaryPurple, Icons.label);
    }
  }

  Widget _buildTag(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  bool _isBirthdayToday(dynamic birth) {
    if (birth == null) return false;
    final now = DateTime.now();
    final todayStr = DateFormat('dd/MM').format(now);

    String clientBirthStr = "";
    if (birth is Timestamp) {
      clientBirthStr = DateFormat('dd/MM').format(birth.toDate());
    } else if (birth is String) {
      if (birth.contains('/')) {
        clientBirthStr = birth.split('/').take(2).join('/');
      } else if (birth.contains('-')) {
        final parts = birth.split('-');
        if (parts.length >= 3) {
          clientBirthStr = "${parts[2]}/${parts[1]}";
        }
      }
    }
    return clientBirthStr == todayStr;
  }
}
