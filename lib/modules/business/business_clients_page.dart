import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rxdart/rxdart.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import 'package:markaai/core/utils/string_utils.dart';
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

  // 0 = Clientes, 1 = Visitantes (Leads)
  int _selectedTabIndex = 0;

  // Filtro de Tags: "Todos", "VIP", "Sumido", "Problematico", "Novo"
  String _selectedTagFilter = "Todos";

  // --- CONTROLE DA COLUNA 3 (PC) ---
  Map<String, dynamic>? _selectedClientData;
  String? _selectedClientId;
  bool _showAddPanel = false;

  // --- CACHE LOCAL ---
  Map<String, List<Map<String, dynamic>>>? _cachedData;
  
  // --- Contador de visitantes para o badge ---
  int _visitorsCount = 0;

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
                title: Text(client['name'] ?? 'Cliente'),
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
    final response = await sb.Supabase.instance.client
        .from('appointments')
        .select('client_id, client_phone')
        .eq('shop_id', shopId!);

    final uniqueClients =
        response.map((d) => d['client_id'] ?? d['client_phone']).toSet();

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
          builder: (context) => const ClientRegisterPage(isBusinessAdding: true),
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

  void _showClearVisitorsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Limpar Visitantes?"),
        content: const Text("Isso apagará todo o histórico de visualizações (leads) da sua loja. Esta ação não pode ser desfeita."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearVisitors();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("LIMPAR TUDO"),
          ),
        ],
      ),
    );
  }

  Future<void> _clearVisitors() async {
    if (shopId == null) return;
    
    try {
      setState(() => _isLoadingId = true); // Reutiliza flag de loading para feedback visual
      await sb.Supabase.instance.client
          .from('shop_views')
          .delete()
          .eq('shop_id', shopId!);
      
      if (mounted) {
        setState(() => _isLoadingId = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lista de visitantes limpa com sucesso!")),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingId = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao limpar visitantes: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }
  
  // ✅ STREAM REATIVO COMBINADO
  Stream<Map<String, dynamic>> _buildCombinedStream() {
    if (shopId == null) return const Stream.empty();

    final supabase = sb.Supabase.instance.client;

    final appointmentsStream = supabase
        .from('appointments')
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId!)
        .order('scheduled_at', ascending: false);

    final shopStream = supabase
        .from('shops')
        .stream(primaryKey: ['id'])
        .eq('id', shopId!)
        .limit(1);

    final featuresStream = PlanFeaturesService.streamFeaturesByShopId(shopId!);

    final favoritesStream = supabase
        .from('favorites')
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId!);

    final shopClientsStream = supabase
        .from('shop_clients')
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId!);

    final shopViewsStream = supabase
        .from('shop_views')
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId!);

    return Rx.combineLatest6(
      appointmentsStream,
      shopStream,
      featuresStream,
      favoritesStream,
      shopClientsStream,
      shopViewsStream,
      (appointments, shopList, features, favorites, shopClients, shopViews) => {
        'appointments': appointments,
        'shop': shopList.isNotEmpty ? shopList.first : {},
        'features': features,
        'favorites': favorites,
        'shopClients': shopClients,
        'shopViews': shopViews,
      },
    ).asyncMap((data) async {
      final appointments = data['appointments'] as List;
      final favorites = data['favorites'] as List;
      final shopViews = data['shopViews'] as List;

      // Busca todos os usuários: de agendamentos (ID ou Telefone), favoritos e visualizações
      final allUserIds = <String>{};
      final manualPhones = <String>{};

      for (final a in appointments) {
        final id = (a['client_id'] ?? a['clientId'])?.toString();
        if (id != null && id.isNotEmpty) {
          allUserIds.add(id);
        } else {
          final phone = (a['client_phone'] ?? a['client_telefone'])?.toString();
          if (phone != null && phone.isNotEmpty) {
            final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
            if (cleanPhone.isNotEmpty) manualPhones.add(cleanPhone);
          }
        }
      }
      for (final f in favorites) {
        final id = (f['user_id'] ?? f['userId'])?.toString();
        if (id != null && id.isNotEmpty) allUserIds.add(id);
      }
      for (final v in shopViews) {
        final id = (v['user_id'] ?? v['userId'])?.toString();
        if (id != null && id.isNotEmpty) allUserIds.add(id);
      }

      List<dynamic> users = [];

      // 1. Busca usuários por UUID (RPC ou Select Direto)
      if (allUserIds.isNotEmpty) {
        try {
          final rpcResult = await supabase.rpc(
            'get_visitor_profiles',
            params: {'user_ids': allUserIds.toList()},
          );
          users = List<dynamic>.from(rpcResult as List? ?? []);
        } catch (_) {
          try {
            final directUsers = await supabase
                .from('users')
                .select('id, name, phone, email, photo_url, created_at, birth_date, city, state, street, neighborhood, number, zip_code, cpf')
                .inFilter('id', allUserIds.toList());
            users = List<dynamic>.from(directUsers);
          } catch (_) {}
        }
      }

      // 2. Busca usuários por TELEFONE (Para clientes manuais que possuem perfil mas o agendamento não vinculou o ID)
      if (manualPhones.isNotEmpty) {
        try {
          final phoneUsers = await supabase
              .from('users')
              .select('id, name, phone, email, photo_url, created_at, birth_date, city, state, street, neighborhood, number, zip_code, cpf')
              .inFilter('phone', manualPhones.toList());
          
          if (phoneUsers.isNotEmpty) {
            final Set<String> existingIds = users.map((u) => u['id'].toString()).toSet();
            for (var u in phoneUsers) {
              if (!existingIds.contains(u['id'].toString())) {
                users.add(u);
              }
            }
          }
        } catch (_) {}
      }

      return {...data, 'users': users};
    });
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
                _buildTabButton(0, "Clientes", Icons.people_outline),
                const SizedBox(width: 15),
                _buildTabButton(1, "Visitantes", Icons.visibility_outlined, 
                    isLocked: !_currentFeatures.visitorsAnalytics, 
                    count: _visitorsCount),
                if (_selectedTabIndex == 1 && _visitorsCount > 0) ...[
                  const SizedBox(width: 15),
                  TextButton.icon(
                    onPressed: _showClearVisitorsDialog,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18, color: Colors.red),
                    label: const Text("Limpar", style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      backgroundColor: Colors.red.withValues(alpha: 0.05),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ],
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
                    final appointmentDocs = data['appointments'] as List<Map<String, dynamic>>;
                    final usersDocs = data['users'] as List<dynamic>;
                    final shopConfig = (data['shop'] as Map?)?['config'] as Map? ?? {};
                    _currentFeatures = data['features'] as PlanFeatures;

                    final favoritesDocs = data['favorites'] as List<Map<String, dynamic>>? ?? [];
                    final shopClientsDocs = data['shopClients'] as List<Map<String, dynamic>>? ?? [];
                    final shopViewsDocs = data['shopViews'] as List<Map<String, dynamic>>? ?? [];

                    final Map<String, Map<String, dynamic>> usersMap = {
                      for (var doc in usersDocs)
                        doc['id']: doc as Map<String, dynamic>
                    };

                    _cachedData = _processClientsData(
                        appointmentDocs,
                        usersMap,
                        shopConfig,
                        favoritesDocs,
                        shopClientsDocs,
                        shopViewsDocs);

                    // Extrair contadores
                    final int visitorsCount = _cachedData!['visitors']!.length;
                    
                    // Atualizar contador apenas quando mudar (evita loop infinito de rebuild)
                    if (_visitorsCount != visitorsCount) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() => _visitorsCount = visitorsCount);
                        }
                      });
                    }

                    List<Map<String, dynamic>> targetList;
                    if (_selectedTabIndex == 0) {
                      targetList = _cachedData!['clients']!;
                    } else {
                      targetList = _cachedData!['visitors']!;
                    }

                    final filteredDocs = targetList.where((client) {
                      // Filtro de Texto
                      final nome = (client['name'] ?? "").toString();
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

  // ?? LÓGICA DE UNIFICAÇÃO DE CLIENTES
  Map<String, List<Map<String, dynamic>>> _processClientsData(
      List<Map<String, dynamic>> appointments,
      Map<String, Map<String, dynamic>> usersMap,
      Map<dynamic, dynamic> shopConfig,
      List<Map<String, dynamic>> favorites,
      List<Map<String, dynamic>> shopClients,
      List<Map<String, dynamic>> shopViews) {
    
    Map<String, Map<String, dynamic>> allClientsMap = {};
    final now = DateTime.now();

    // 1. Processar dados de 'shop_clients' (Tags manuais e customizações)
    final Map<String, Map<String, dynamic>> manualDataMap = {
      for (var doc in shopClients)
        (doc['user_id'] ?? doc['userId'] ?? '').toString(): doc
    };

    // 2. Processar Favoritos
    final Set<String> favoritedIds = favorites.map((f) => (f['user_id'] ?? f['userId'] ?? '').toString()).where((id) => id.isNotEmpty).toSet();

    // 3. Processar Visualizações (Leads)
    final Map<String, DateTime> visitorIds = {
      for (var v in shopViews)
        (v['user_id'] ?? v['userId'] ?? '').toString(): DateTime.tryParse(v['viewed_at']?.toString() ?? "") ?? now
    };

    // 4. Processar Agendamentos (Principal fonte de clientes)
    for (var doc in appointments) {
      final data = doc;
      String? userId = (data['client_id'] ?? data['clientId'])?.toString();
      bool isManual = (userId == null || userId.isEmpty);

      final user = isManual ? null : usersMap[userId];

      String nome = user?['name'] ?? data['client_name'] ?? data['client_nome'] ?? "Cliente Desconhecido";
      String telefone = user?['phone'] ?? data['client_phone'] ?? "";
      String photoUrl = user?['photo_url'] ?? "";

      String key = !isManual ? userId : (telefone.isNotEmpty ? telefone : "doc_${doc['id']}");

      double valor = double.tryParse(
              (data['total_price'] ?? data['price'] ?? data['valor_total'] ?? "0")
                  .toString()) ??
          0.0;
      DateTime dataVisita = DateTime.tryParse(data['scheduled_at'] ?? "") ?? now;
      String status = (data['status'] ?? "").toString().toLowerCase();

      if (!allClientsMap.containsKey(key)) {
        allClientsMap[key] = {
          'id': key,
          'name': nome,
          'nome': nome,
          'telefone': telefone.isNotEmpty ? telefone : "Não informado",
          'foto': photoUrl,
          'origem': isManual ? 'manual' : 'app',
          'totalGasto': (status == 'concluido' || status == 'pago') ? valor : 0.0,
          'visitas': (status == 'concluido' || status == 'pago') ? 1 : 0,
          'agendamentosCount': 1,
          'primeiraVisita': dataVisita,
          'ultimaVisita': dataVisita,
          'email': user?['email'] ?? "",
          'city': user?['city'] ?? "",
          'state': user?['state'] ?? "",
          'street': user?['street'] ?? "",
          'neighborhood': user?['neighborhood'] ?? "",
          'number': user?['number'] ?? "",
          'zipCode': user?['zip_code'] ?? "",
          'cpf': user?['cpf'] ?? "",
          'birthDate': user?['birth_date'] ?? "",
          'isFavorite': favoritedIds.contains(userId),
          'isVisitor': visitorIds.containsKey(userId),
          'lastViewed': visitorIds[userId],
          'tags': [],
          'servicos': <String, int>{}, // Para calcular serviço preferido
          'visitasDates': <DateTime>[dataVisita], // Para calcular intervalo médio
          'ultimoServico': (status == 'concluido' || status == 'pago') ? (data['service_name'] ?? data['serviceName'] ?? "") : "",
        };
        if (status == 'concluido' || status == 'pago') {
          final sName = data['service_name'] ?? data['serviceName'] ?? "";
          if (sName.isNotEmpty) allClientsMap[key]!['servicos'][sName] = 1;
        }
      } else {
        if (status == 'concluido' || status == 'pago') {
          allClientsMap[key]!['totalGasto'] += valor;
          allClientsMap[key]!['visitas'] += 1;
          
          final sName = data['service_name'] ?? data['serviceName'] ?? "";
          if (sName.isNotEmpty) {
            allClientsMap[key]!['servicos'][sName] = (allClientsMap[key]!['servicos'][sName] ?? 0) + 1;
          }
        }
        allClientsMap[key]!['agendamentosCount'] += 1;

        if (dataVisita.isBefore(allClientsMap[key]!['primeiraVisita'])) {
          allClientsMap[key]!['primeiraVisita'] = dataVisita;
        }
        if (dataVisita.isAfter(allClientsMap[key]!['ultimaVisita'])) {
          allClientsMap[key]!['ultimaVisita'] = dataVisita;
          if (status == 'concluido' || status == 'pago') {
            allClientsMap[key]!['ultimoServico'] = data['service_name'] ?? data['serviceName'] ?? "";
          }
        }
        allClientsMap[key]!['visitasDates'].add(dataVisita);
      }
    }

    // 5. Adicionar Favoritos e Visitantes que ainda não agendaram
    final Set<String> allUserIds = {...favoritedIds, ...visitorIds.keys};
    for (var uid in allUserIds) {
      if (!allClientsMap.containsKey(uid) && uid.isNotEmpty) {
        // Para esses leads, tentamos pegar o nome básico se disponível no usersMap
        final user = usersMap[uid];
        String nome = user?['name'] ?? "Cliente (Interesse)";
        
        allClientsMap[uid] = {
          'id': uid,
          'name': nome,
          'nome': nome,
          'telefone': user?['phone'] ?? "Não informado",
          'foto': user?['photo_url'] ?? "",
          'origem': 'app',
          'totalGasto': 0.0,
          'visitas': 0,
          'agendamentosCount': 0,
          'primeiraVisita': visitorIds[uid] ?? now,
          'ultimaVisita': visitorIds[uid] ?? now,
          'email': user?['email'] ?? "",
          'city': user?['city'] ?? "",
          'state': user?['state'] ?? "",
          'street': user?['street'] ?? "",
          'neighborhood': user?['neighborhood'] ?? "",
          'number': user?['number'] ?? "",
          'zipCode': user?['zip_code'] ?? "",
          'cpf': user?['cpf'] ?? "",
          'birthDate': user?['birth_date'] ?? "",
          'isFavorite': favoritedIds.contains(uid),
          'isVisitor': visitorIds.containsKey(uid),
          'lastViewed': visitorIds[uid],
          'tags': [],
          'servicos': <String, int>{},
          'visitasDates': <DateTime>[],
        };
      }
    }

    // 6. Aplicar Tags e Classificações (Auto + Manual)
    final int vipMinVisits = shopConfig['vip_min_visits'] ?? 15;
    final int sumidoMaxDays = shopConfig['sumido_max_days'] ?? 45;

    for (var c in allClientsMap.values) {
      final String uid = c['id'];
      final mData = manualDataMap[uid];
      
      // Tags Automáticas
      List<String> tags = [];
      String classification = "";

      if (c['origem'] == 'app') {
        final int visits = (c['visitas'] ?? 0) as int;
        final DateTime lastVisit = c['ultimaVisita'] as DateTime;
        final int daysSinceLast = now.difference(lastVisit).inDays;

        if (daysSinceLast > sumidoMaxDays && visits > 0) {
          classification = 'sumido';
        } else if (visits >= vipMinVisits && _currentFeatures.clientClassification) {
          classification = 'vip';
        } else if (visits == 1 && daysSinceLast < 30 && _currentFeatures.clientClassification) {
          classification = 'novo';
        }
      }

      // Sobreposição Manual
      if (mData != null) {
        final manualTags = List<String>.from(mData['manual_tags'] ?? mData['manualTags'] ?? []);
        final manualClass = mData['classification']?.toString();
        
        if (manualClass != null && manualClass.isNotEmpty) {
          classification = manualClass;
        }
        tags.addAll(manualTags);
      }

      // Remove classificações da lista para garantir exclusividade antes de reinjetar a correta
      final presetClasses = ['vip', 'novo', 'problematico', 'problemático', 'sumido'];
      tags.removeWhere((t) => presetClasses.contains(t.toLowerCase()));

      if (classification.isNotEmpty) tags.add(classification);
      // Tags "favoritou" e "visitou" removidas - o coração e ícone de olho já mostram isso visualmente

      c['classification'] = classification;
      c['tags'] = tags.toSet().toList(); // Remove duplicatas

      // FINALIZAR ESTATÍSTICAS
      // 1. Serviço Preferido
      final servicos = c['servicos'] as Map<String, int>;
      if (servicos.isNotEmpty) {
        final sortedServicos = servicos.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        c['servicoPreferido'] = sortedServicos.first.key;
      } else {
        c['servicoPreferido'] = "Nenhum";
      }

      // 2. Intervalo Médio (em dias)
      final dates = List<DateTime>.from(c['visitasDates'])..sort();
      if (dates.length > 1) {
        int totalDays = 0;
        for (int i = 0; i < dates.length - 1; i++) {
          totalDays += dates[i + 1].difference(dates[i]).inDays;
        }
        c['intervaloMedio'] = (totalDays / (dates.length - 1)).round();
      } else {
        c['intervaloMedio'] = 0;
      }
    }

    // 7. Separar listas
    List<Map<String, dynamic>> mainClients = [];
    List<Map<String, dynamic>> visitorLeads = [];

    for (var c in allClientsMap.values) {
      if (c['origem'] == 'manual') {
        if (c['telefone'] != "Não informado") mainClients.add(c);
      } else {
        // Clientes são quem tem agendamentos OU são classificados como VIP
        bool isVip = c['classification'] == 'vip' || (c['tags'] as List? ?? []).contains('vip');
        
        if (c['agendamentosCount'] > 0 || isVip) {
          mainClients.add(c);
        } else {
          visitorLeads.add(c);
        }
      }
    }

    return {
      'clients': mainClients,
      'visitors': visitorLeads,
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


  Widget _buildTabButton(int index, String label, IconData icon, {bool isLocked = false, int? count}) {
    bool isSelected = _selectedTabIndex == index;
    final showBadge = count != null && count > 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: () {
            if (isLocked) {
              UpgradeModal.show(
                context,
                featureName: "Aba de Visitantes",
                requiredPlan: "Plus",
              );
              return;
            }
            setState(() {
              _selectedTabIndex = index;
              _selectedTagFilter = "Todos";
            });
          },
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isLocked
                  ? Colors.grey[200]
                  : (isSelected
                      ? (index == 0 ? AppColors.primaryPurple : Colors.blue)
                      : Colors.grey[100]),
              borderRadius: BorderRadius.circular(20),
              border: isSelected
                  ? Border.all(color: Colors.transparent)
                  : Border.all(color: Colors.grey[300]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isLocked ? Icons.lock : icon,
                    size: 16,
                    color: isSelected
                        ? Colors.white
                        : (isLocked ? Colors.grey : Colors.grey[600])),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : (isLocked ? Colors.grey : Colors.grey[600]),
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
              ],
            ),
          ),
        ),
        if (showBadge)
          Positioned(
            right: -8,
            top: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                count > 99 ? '99+' : count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
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
          child: Text((client['name'] ?? "?").substring(0, 1).toUpperCase(),
              style: TextStyle(color: themeColor, fontWeight: FontWeight.bold)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(client['name'],
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            if (client['isFavorite'] == true)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.favorite, color: Colors.red, size: 14),
              ),
            if (client['isVisitor'] == true && client['agendamentosCount'] == 0)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.visibility, color: Colors.blue, size: 14),
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
              Text(client['telefone'], style: const TextStyle(fontSize: 12))
            else if ((client['email'] ?? '').toString().isNotEmpty)
              Text(client['email'], style: TextStyle(fontSize: 11, color: Colors.grey[700])),
            if ((client['city'] ?? '').toString().isNotEmpty)
              Text(
                '${client['city']}${(client['state'] ?? '').toString().isNotEmpty ? ', ${client['state']}' : ''}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
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
            if (client['telefone'] != "Não informado")
              IconButton(
                icon: const FaIcon(
                  FontAwesomeIcons.whatsapp,
                  color: Color(0xFF25D366),
                  size: 24,
                ),
                tooltip: 'Chamar no WhatsApp',
                onPressed: () => _launchWhatsApp(client['telefone']),
              )
            else if ((client['email'] ?? '').toString().isNotEmpty)
              IconButton(
                icon: const Icon(Icons.email_outlined, color: Colors.blueGrey, size: 22),
                tooltip: 'Enviar e-mail',
                onPressed: () async {
                  final uri = Uri.parse('mailto:${client['email']}');
                  if (await canLaunchUrl(uri)) launchUrl(uri);
                },
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
    if (birth is String) {
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
