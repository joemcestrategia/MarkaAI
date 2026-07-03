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
  Map<String, dynamic>? _cachedData;
  int _lastStreamFingerprint = 0;

  // --- STREAM CACHE ---
  Stream<Map<String, dynamic>>? _combinedStream;
  
  // --- Contador de visitantes para o badge ---
  int _visitorsCount = 0;

  PlanFeatures _currentFeatures = planFeaturesConfig[PlanKey.free]!;
  int _clientsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadShopId();
  }

  Future<void> _loadShopId() async {
    final id = await SessionService.getShopId();
    if (mounted) {
      if (id != null) {
        final cached = await ClientCacheService.getCachedClients(id);
        final stale = await ClientCacheService.isCacheStale(id);
        if (cached != null) {
          _cachedData = cached;
          _clientsCount = (cached['clients'] as List?)?.length ?? 0;
          _visitorsCount = (cached['visitors'] as List?)?.length ?? 0;
          _lastStreamFingerprint = (cached['fingerprint']?.toString() ?? '').hashCode;
        }
        if (cached == null) {
          _fetchInitialData(id);
        } else if (stale) {
          _fetchInitialData(id);
        }
        _combinedStream = _buildCombinedStream();
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

  Future<void> _fetchInitialData(String shopId) async {
    try {
      final supabase = sb.Supabase.instance.client;

      final results = await Future.wait([
        supabase.from('appointments').select().eq('shop_id', shopId).order('scheduled_at', ascending: false).limit(5000),
        supabase.from('shops').select().eq('id', shopId).limit(1).maybeSingle(),
        supabase.from('favorites').select().eq('shop_id', shopId),
        supabase.from('shop_clients').select().eq('shop_id', shopId),
        supabase.from('shop_views').select().eq('shop_id', shopId),
      ]);

      final appointments = (results[0] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>)
          .where((r) => (r['status'] ?? '').toString() != 'pre_reserva')
          .toList() ?? [];
      final shop = results[1] as Map<String, dynamic>?;
      final favorites = (results[2] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>).toList() ?? [];
      final shopClients = (results[3] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>).toList() ?? [];
      final shopViews = (results[4] as List<dynamic>?)
          ?.map((e) => e as Map<String, dynamic>).toList() ?? [];

      final features = PlanFeaturesService.getFeaturesForShop(shop);

      final allUserIds = <String>{};
      final manualPhones = <String>{};
      for (final a in appointments) {
        final id = (a['client_id'] ?? a['clientId'])?.toString();
        if (id != null && id.isNotEmpty) {
          allUserIds.add(id);
        } else {
          final phone = (a['client_phone'] ?? a['client_telefone'])?.toString();
          if (phone != null && phone.isNotEmpty) {
            final cleanPhone = _normalizePhone(phone);
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
      if (allUserIds.isNotEmpty) {
        try {
          final directUsers = await supabase
              .from('users')
              .select('id, name, phone, email, photo_url, created_at, birth_date, city, state, street, neighborhood, number, zip_code, cpf')
              .inFilter('id', allUserIds.toList());
          users = List<dynamic>.from(directUsers);
        } catch (_) {}
      }
      if (manualPhones.isNotEmpty) {
        try {
          final phoneUsers = await supabase
              .from('users')
              .select('id, name, phone, email, photo_url, created_at, birth_date, city, state, street, neighborhood, number, zip_code, cpf')
              .inFilter('phone', manualPhones.toList());
          if (phoneUsers.isNotEmpty) {
            final existingIds = users.map((u) => u['id'].toString()).toSet();
            for (var u in phoneUsers) {
              if (!existingIds.contains(u['id'].toString())) users.add(u);
            }
          }
        } catch (_) {}
      }

      // RPC fallback: fetch profiles for users not found via direct query (bypasses RLS)
      if (allUserIds.isNotEmpty) {
        final foundIds = users.map((u) => u['id'].toString()).toSet();
        final missingIds = allUserIds.where((id) => !foundIds.contains(id)).toList();
        if (missingIds.isNotEmpty && shopId != null) {
          try {
            final rpcUsers = await supabase
                .rpc('get_visitor_profiles', params: {'user_ids': missingIds, 'caller_shop_id': shopId});
            if (rpcUsers is List && rpcUsers.isNotEmpty) {
              users.addAll(rpcUsers);
            }
          } catch (_) {}
        }
      }

      final usersMap = <String, Map<String, dynamic>>{
        for (var doc in users) doc['id']: doc as Map<String, dynamic>
      };

      final shopConfig = (shop?['config'] as Map?)?.cast<dynamic, dynamic>() ?? {};
      final featuresForNow = features;

      if (mounted) {
        final processed = _processClientsData(
            appointments, usersMap, shopConfig, favorites, shopClients, shopViews);
        ClientCacheService.saveClients(shopId, processed);
        setState(() {
          _cachedData = processed;
          _currentFeatures = featuresForNow;
          _clientsCount = (processed['clients'] as List?)?.length ?? 0;
          _visitorsCount = (processed['visitors'] as List?)?.length ?? 0;
        });
      }
    } catch (e) {
      debugPrint('_fetchInitialData error: $e');
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
        .eq('shop_id', shopId!)
        .neq('status', 'pre_reserva');

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

    // Stream Supabase não suporta neq, então filtramos no map abaixo
    final appointmentsStream = supabase
        .from('appointments')
        .stream(primaryKey: ['id'])
        .eq('shop_id', shopId!)
        .order('scheduled_at', ascending: false)
        .limit(5000)
        .map((rows) => rows
            .where((r) => (r['status'] ?? '').toString() != 'pre_reserva')
            .toList());

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
            final cleanPhone = _normalizePhone(phone);
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

      // 1. Busca usuários por UUID (select direto no Supabase, com fallback chunked)
      if (allUserIds.isNotEmpty) {
        try {
          final directUsers = await supabase
              .from('users')
              .select('id, name, phone, email, photo_url, created_at, birth_date, city, state, street, neighborhood, number, zip_code, cpf')
              .inFilter('id', allUserIds.toList());
          users = List<dynamic>.from(directUsers);
        } catch (_) {
          // Fallback: busca em chunks de 50
          final chunks = allUserIds.toList();
          for (var i = 0; i < chunks.length; i += 50) {
            try {
              final chunk = chunks.sublist(i, (i + 50).clamp(0, chunks.length));
              final chunkUsers = await supabase
                  .from('users')
                  .select('id, name, phone, email, photo_url, created_at, birth_date, city, state, street, neighborhood, number, zip_code, cpf')
                  .inFilter('id', chunk);
              users.addAll(List<dynamic>.from(chunkUsers));
            } catch (_) {}
          }
        }
      }

      // RPC fallback: fetch profiles for users not found via direct query (bypasses RLS)
      if (allUserIds.isNotEmpty) {
        final foundIds = users.map((u) => u['id'].toString()).toSet();
        final missingIds = allUserIds.where((id) => !foundIds.contains(id)).toList();
        if (missingIds.isNotEmpty && shopId != null) {
          try {
            final rpcUsers = await supabase
                .rpc('get_visitor_profiles', params: {'user_ids': missingIds, 'caller_shop_id': shopId});
            if (rpcUsers is List && rpcUsers.isNotEmpty) {
              users.addAll(rpcUsers);
            }
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

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isMobile = constraints.maxWidth < 850;

        if (isMobile) {
          return Material(
            color: const Color(0xFFF2F4F8),
            child: _buildListContent(isMobile),
          );
        } else {
          return Material(
            color: const Color(0xFFF2F4F8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _buildListContent(isMobile),
                ),
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
  }

  // ?? WIDGET EXTRAÍDO: Conteúdo da Lista (Reusável)
  Widget _buildListContent(bool isMobile) {
    return Column(
      children: [
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
                label: Text(isMobile ? "NOVO" : "NOVO CLIENTE"),
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

        shopId == null
            ? const Center(child: Text("Erro: ID da Loja não encontrado"))
            : Expanded(
                child: StreamBuilder<Map<String, dynamic>>(
                  stream: _combinedStream,
                  builder: (context, snapshot) {
                    final bool useRealtime = snapshot.hasData && !snapshot.hasError;
                    final data = useRealtime ? snapshot.data! : null;

                    if (useRealtime && data != null) {
                      try {
                        _currentFeatures = (data['features'] as PlanFeatures?) ?? planFeaturesConfig[PlanKey.free]!;
                        final appointmentDocs = (data['appointments'] as List?)?.cast<Map<String, dynamic>>() ?? [];

                        // Só re-processa se os appointments mudaram (fingerprint diferente)
                        final newFingerprint = ClientCacheService.computeAppointmentsFingerprint(appointmentDocs);
                        if (newFingerprint != _lastStreamFingerprint) {
                          _lastStreamFingerprint = newFingerprint;

                          final usersDocs = (data['users'] as List?) ?? [];
                          final shopConfig = (data['shop'] as Map?)?['config'] as Map? ?? {};
                          final favoritesDocs = (data['favorites'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                          final shopClientsDocs = (data['shopClients'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                          final shopViewsDocs = (data['shopViews'] as List?)?.cast<Map<String, dynamic>>() ?? [];

                          final Map<String, Map<String, dynamic>> usersMap = {
                            for (var doc in usersDocs)
                              if (doc is Map && doc['id'] != null)
                                doc['id'].toString(): doc as Map<String, dynamic>
                          };

                          final freshData = _processClientsData(
                              appointmentDocs, usersMap, shopConfig,
                              favoritesDocs, shopClientsDocs, shopViewsDocs);

                          if (shopId != null) {
                            freshData['fingerprint'] = _lastStreamFingerprint.toString();
                            ClientCacheService.saveClients(shopId!, freshData);
                          }
                          _cachedData = freshData;
                          _clientsCount = (freshData['clients'] as List?)?.length ?? 0;
                          _visitorsCount = (freshData['visitors'] as List?)?.length ?? 0;
                        }
                      } catch (e) {
                        debugPrint('StreamBuilder processing error: $e');
                      }
                    }

                    final displayData = _cachedData;
                    if (displayData == null) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    List<Map<String, dynamic>> targetList;
                    if (_selectedTabIndex == 0) {
                      targetList = (displayData['clients'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                    } else if (_selectedTabIndex == 1) {
                      targetList = (displayData['visitors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                    } else {
                      targetList = (displayData['clients'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                    }

                    final filteredDocs = targetList.where((client) {
                      final nome = (client['name'] ?? "").toString();
                      final normalizedNome =
                          StringUtils.removeDiacritics(nome).toLowerCase();
                      final normalizedSearch =
                          StringUtils.removeDiacritics(_searchText).toLowerCase();
                      if (!normalizedNome.contains(normalizedSearch)) return false;
                      if (_selectedTagFilter == "Todos") return true;
                      final List tags = client['tags'] as List? ?? [];
                      final String? classification =
                          client['classification']?.toString().toLowerCase();
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
                        return tags.contains('problematico') ||
                            tags.contains('problemático') ||
                            classification == 'problematico' ||
                            classification == 'problemático';
                      }
                      return tags.any((t) =>
                          t.toString().toLowerCase() ==
                          _selectedTagFilter.toLowerCase());
                    }).toList();

                    // Aba Clientes: remove quem nunca agendou (leads puros)
                    if (_selectedTabIndex == 0) {
                      filteredDocs.removeWhere((c) => (c['agendamentosCount'] ?? 0) == 0);
                    }
                    // Ranking: remove sem gasto e ordena por totalGasto decrescente
                    if (_selectedTabIndex == 2) {
                      filteredDocs.removeWhere((c) => (c['totalGasto'] ?? 0.0) <= 0);
                      filteredDocs.sort((a, b) {
                        final ga = (a['totalGasto'] ?? 0.0) as double;
                        final gb = (b['totalGasto'] ?? 0.0) as double;
                        return gb.compareTo(ga);
                      });
                    } else {
                      // Ordena alfabeticamente
                      filteredDocs.sort((a, b) {
                        final na = (a['name'] ?? '').toString().toLowerCase();
                        final nb = (b['name'] ?? '').toString().toLowerCase();
                        return na.compareTo(nb);
                      });
                    }

                    return Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 10),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2))
                            ],
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildTabButton(0, "Clientes",
                                    Icons.people_outline,
                                    count: _clientsCount),
                                const SizedBox(width: 15),
                                _buildTabButton(1, "Visitantes",
                                    Icons.visibility_outlined,
                                    isLocked: !_currentFeatures
                                        .visitorsAnalytics,
                                    count: _visitorsCount),
                                const SizedBox(width: 15),
                                _buildTabButton(2, "Ranking",
                                    Icons.leaderboard_outlined),
                                if (_selectedTabIndex == 1 &&
                                    _visitorsCount > 0) ...[
                                  const SizedBox(width: 15),
                                  TextButton.icon(
                                    onPressed: _showClearVisitorsDialog,
                                    icon: const Icon(
                                        Icons.delete_sweep_outlined,
                                        size: 18,
                                        color: Colors.red),
                                    label: const Text("Limpar",
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold)),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      backgroundColor:
                                          Colors.red.withValues(alpha: 0.05),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 8),
                          color: Colors.white,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildTagFilterChip("Todos"),
                                const SizedBox(width: 8),
                                _buildTagFilterChip("VIP",
                                    icon: Icons.star,
                                    color: Colors.amber,
                                    isLocked: !_currentFeatures.clientFilter),
                                const SizedBox(width: 8),
                                _buildTagFilterChip("Novo",
                                    icon: Icons.new_releases,
                                    color: Colors.green,
                                    isLocked: !_currentFeatures.clientFilter),
                                const SizedBox(width: 8),
                                _buildTagFilterChip("Sumido",
                                    icon: Icons.timer_off_outlined,
                                    color: Colors.grey,
                                    isLocked: !_currentFeatures.clientFilter),
                                const SizedBox(width: 8),
                                _buildTagFilterChip("Problemático",
                                    icon: Icons.warning_amber_rounded,
                                    color: Colors.red,
                                    isLocked: !_currentFeatures.clientFilter),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: filteredDocs.isEmpty
                              ? _buildEmptyState()
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      24, 16, 24, 80),
                                  itemCount: filteredDocs.length,
                                  itemBuilder: (context, index) {
                                    return _buildClientListItem(
                                        filteredDocs[index],
                                        (_selectedClientId ==
                                            filteredDocs[index]['id']),
                                        isMobile,
                                        rank: _selectedTabIndex == 2 ? index + 1 : null);
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
      ],
    );
  }

  Map<String, dynamic> _processClientsData(
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

    // 4. Mapas reversos: telefone/email normalizado → usuário (para vincular agendamentos manuais)
    final Map<String, Map<String, dynamic>> phoneToUser = {};
    final Map<String, Map<String, dynamic>> emailToUser = {};
    for (var entry in usersMap.entries) {
      final rawPhone = (entry.value['phone'] ?? '').toString();
      final normalized = _normalizePhone(rawPhone);
      if (normalized.isNotEmpty) {
        phoneToUser[normalized] = entry.value;
      }
      final email = (entry.value['email'] ?? '').toString().trim().toLowerCase();
      if (email.isNotEmpty) {
        emailToUser[email] = entry.value;
      }
    }

    // 5. Processar Agendamentos (Principal fonte de clientes)
    for (var doc in appointments) {
      final data = doc;
      String? userId = (data['client_id'] ?? data['clientId'])?.toString();
      String rawClientPhone = (data['client_phone'] ?? '').toString();
      String normalizedPhone = _normalizePhone(rawClientPhone);
      String clientEmail = (data['client_email'] ?? '').toString().trim().toLowerCase();

      // Appointments sem client_id no banco são manuais, mesmo se acharmos usuário por telefone
      final bool wasManual = (userId == null || userId.isEmpty);

      // Tenta vincular agendamento manual a usuário registrado (telefone → email)
      Map<String, dynamic>? matchedUser;
      if (wasManual) {
        if (normalizedPhone.isNotEmpty) {
          matchedUser = phoneToUser[normalizedPhone];
        }
        if (matchedUser == null && clientEmail.isNotEmpty) {
          matchedUser = emailToUser[clientEmail];
        }
      }

      // Dados do usuário: da conta vinculada OU do match OU do appointment
      final effectiveUser = wasManual ? matchedUser : usersMap[userId];
      String nome = effectiveUser?['name'] ?? data['client_name'] ?? data['client_nome'] ?? "Cliente Desconhecido";
      String telefone = effectiveUser?['phone'] ?? rawClientPhone;
      String photoUrl = effectiveUser?['photo_url'] ?? "";

      // Chave de deduplicação: UUID do match > UUID do appointment > telefone > email > doc id
      String key;
      if (matchedUser != null) {
        key = matchedUser['id']?.toString() ?? (normalizedPhone.isNotEmpty ? 'phone_$normalizedPhone' : 'email_$clientEmail');
      } else if (!wasManual) {
        key = userId;
      } else if (normalizedPhone.isNotEmpty) {
        key = 'phone_$normalizedPhone';
      } else if (clientEmail.isNotEmpty) {
        key = 'email_$clientEmail';
      } else {
        key = "doc_${doc['id']}";
      }

      double valor = double.tryParse(
              (data['total_price'] ?? data['price'] ?? data['valor_total'] ?? "0")
                  .toString()) ??
          0.0;
      DateTime dataVisita = DateTime.tryParse(data['scheduled_at'] ?? "") ?? now;
      String status = (data['status'] ?? "").toString().toLowerCase();
      final bool pastAppointment = dataVisita.isBefore(now);
      final bool countsAsVisit = pastAppointment &&
          (status == 'concluido' || status == 'pago' || status == 'confirmado');

      if (!allClientsMap.containsKey(key)) {
        final String effectiveUserId = matchedUser?['id']?.toString() ?? userId ?? '';

        allClientsMap[key] = {
          'id': key,
          'name': nome,
          'nome': nome,
          'telefone': telefone.isNotEmpty ? telefone : "Não informado",
          'foto': photoUrl,
          'origem': wasManual ? 'manual' : 'app',
          'totalGasto': (status == 'concluido' || status == 'pago') ? valor : 0.0,
          'visitas': countsAsVisit ? 1 : 0,
          'agendamentosCount': 1,
          'primeiraVisita': pastAppointment ? dataVisita : DateTime(2100),
          'ultimaVisita': pastAppointment ? dataVisita : DateTime(2000),
          'email': effectiveUser?['email'] ?? "",
          'city': effectiveUser?['city'] ?? "",
          'state': effectiveUser?['state'] ?? "",
          'street': effectiveUser?['street'] ?? "",
          'neighborhood': effectiveUser?['neighborhood'] ?? "",
          'number': effectiveUser?['number'] ?? "",
          'zipCode': effectiveUser?['zip_code'] ?? "",
          'cpf': effectiveUser?['cpf'] ?? "",
          'birthDate': effectiveUser?['birth_date'] ?? "",
          'isFavorite': favoritedIds.contains(effectiveUserId),
          'isVisitor': visitorIds.containsKey(effectiveUserId),
          'lastViewed': visitorIds[effectiveUserId],
          'tags': [],
          'servicos': <String, int>{},
          'visitasDates': <DateTime>[if (pastAppointment) dataVisita],
          'ultimoServico': countsAsVisit ? (data['service_name'] ?? data['serviceName'] ?? "") : "",
        };
        if (countsAsVisit) {
          final sName = data['service_name'] ?? data['serviceName'] ?? "";
          if (sName.isNotEmpty) allClientsMap[key]!['servicos'][sName] = 1;
        }
      } else {
        if (status == 'concluido' || status == 'pago') {
          allClientsMap[key]!['totalGasto'] += valor;
        }
        if (countsAsVisit) {
          allClientsMap[key]!['visitas'] += 1;

          final sName = data['service_name'] ?? data['serviceName'] ?? "";
          if (sName.isNotEmpty) {
            allClientsMap[key]!['servicos'][sName] = (allClientsMap[key]!['servicos'][sName] ?? 0) + 1;
          }
        }
        allClientsMap[key]!['agendamentosCount'] += 1;

        if (pastAppointment) {
          if (dataVisita.isBefore(allClientsMap[key]!['primeiraVisita'])) {
            allClientsMap[key]!['primeiraVisita'] = dataVisita;
          }
          if (dataVisita.isAfter(allClientsMap[key]!['ultimaVisita'])) {
            allClientsMap[key]!['ultimaVisita'] = dataVisita;
            if (countsAsVisit) {
              allClientsMap[key]!['ultimoServico'] = data['service_name'] ?? data['serviceName'] ?? "";
            }
          }
          allClientsMap[key]!['visitasDates'].add(dataVisita);
        }
      }
    }

    // 5. Adicionar Favoritos e Visitantes que ainda não agendaram
    final Set<String> allUserIds = {...favoritedIds, ...visitorIds.keys};
    for (var uid in allUserIds) {
      if (!allClientsMap.containsKey(uid) && uid.isNotEmpty) {
        // Para esses leads, tentamos pegar o nome básico se disponível no usersMap
        final user = usersMap[uid];
        String nome = user?['name'] ?? "Visitante";
        
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

    // 6. Aplicar Tags Manuais (antes do merge, baseado no user_id de shop_clients)
    final int vipMinVisits = shopConfig['vip_min_visits'] ?? 15;
    final int sumidoMaxDays = shopConfig['sumido_max_days'] ?? 45;

    for (var c in allClientsMap.values) {
      final String uid = c['id'];
      final mData = manualDataMap[uid];
      
      if (mData != null) {
        final manualTags = List<String>.from(mData['manual_tags'] ?? mData['manualTags'] ?? []);
        final manualClass = mData['classification']?.toString();
        if (manualClass != null && manualClass.isNotEmpty) {
          c['classification'] = manualClass;
        }
        c['tags'] = List<String>.from(manualTags);
      }
    }

    // 7. Pós-processamento: unificar entradas com mesmo telefone (client_ids diferentes)
    // Resolve duplicatas causadas por migration vinculando mesmo telefone a UUIDs distintos
    final Map<String, String> phoneToBestKey = {};
    final List<String> keysToRemove = [];

    for (var entry in allClientsMap.entries) {
      final phone = _normalizePhone((entry.value['telefone'] ?? '').toString());
      if (phone.isEmpty) continue;

      if (phoneToBestKey.containsKey(phone)) {
        final primaryKey = phoneToBestKey[phone]!;
        final primary = allClientsMap[primaryKey]!;
        final secondary = entry.value;

        // Mantém o registro com mais agendamentos ou o primeiro encontrado
        if ((secondary['agendamentosCount'] as int) > (primary['agendamentosCount'] as int)) {
          // Promove o secundário a primário e merge
          final oldPrimary = Map<String, dynamic>.from(primary);
          allClientsMap[entry.key] = _mergeClientEntry(oldPrimary, secondary);
          allClientsMap[entry.key]!['id'] = entry.key;
          keysToRemove.add(primaryKey);
          phoneToBestKey[phone] = entry.key;
          keysToRemove.remove(entry.key);
        } else {
          // Merge secundário no primário
          allClientsMap[primaryKey] = _mergeClientEntry(primary, secondary);
          keysToRemove.add(entry.key);
        }
      } else {
        phoneToBestKey[phone] = entry.key;
      }
    }
    for (var key in keysToRemove) {
      allClientsMap.remove(key);
    }

    // 7b. Segunda passagem de merge: unificar por email (clientes que trocaram de telefone)
    // Só executa se sobrou mais de 1 entrada (já foram unificadas por telefone)
    if (allClientsMap.length > 1) {
      final Map<String, String> emailToBestKey = {};
      final List<String> emailKeysToRemove = [];

      for (var entry in allClientsMap.entries) {
        final email = (entry.value['email'] ?? '').toString().trim().toLowerCase();
        if (email.isEmpty) continue;

        if (emailToBestKey.containsKey(email)) {
          final primaryKey = emailToBestKey[email]!;
          final primary = allClientsMap[primaryKey]!;
          final secondary = entry.value;

          if ((secondary['agendamentosCount'] as int) > (primary['agendamentosCount'] as int)) {
            final oldPrimary = Map<String, dynamic>.from(primary);
            allClientsMap[entry.key] = _mergeClientEntry(oldPrimary, secondary);
            allClientsMap[entry.key]!['id'] = entry.key;
            emailKeysToRemove.add(primaryKey);
            emailToBestKey[email] = entry.key;
            emailKeysToRemove.remove(entry.key);
          } else {
            allClientsMap[primaryKey] = _mergeClientEntry(primary, secondary);
            emailKeysToRemove.add(entry.key);
          }
        } else {
          emailToBestKey[email] = entry.key;
        }
      }
      for (var key in emailKeysToRemove) {
        allClientsMap.remove(key);
      }
    }

    // 8. Recalcular classificações automáticas e estatísticas (pós-merge)
    for (var c in allClientsMap.values) {
      final int visits = (c['visitas'] ?? 0) as int;
      final bool hasRealVisits = visits > 0;
      final DateTime ultimaVisita = c['ultimaVisita'] as DateTime;
      final int daysSinceLast = hasRealVisits ? now.difference(ultimaVisita).inDays : 0;

      // Classificação automática (só se não tiver manual e tiver visitas reais)
      final existingClass = c['classification']?.toString() ?? '';
      final isManualClass = existingClass.isNotEmpty;
      
      String autoClassification = '';
      if (hasRealVisits && c['origem'] == 'app' && !isManualClass) {
        if (daysSinceLast > sumidoMaxDays && visits > 0) {
          autoClassification = 'sumido';
        } else if (visits >= vipMinVisits && _currentFeatures.clientClassification) {
          autoClassification = 'vip';
        } else if (visits == 1 && daysSinceLast < 30 && _currentFeatures.clientClassification) {
          autoClassification = 'novo';
        }
      }

      if (!isManualClass && autoClassification.isNotEmpty) {
        c['classification'] = autoClassification;
      }

      // Tags finais: mantém tags manuais + adiciona classificação se não existir
      final List<String> tags = List<String>.from(c['tags'] ?? []);
      final presetClasses = ['vip', 'novo', 'problematico', 'problemático', 'sumido'];
      tags.removeWhere((t) => presetClasses.contains(t.toLowerCase()));
      final finalClass = c['classification']?.toString() ?? '';
      if (finalClass.isNotEmpty) tags.add(finalClass);
      c['tags'] = tags.toSet().toList();

      // Serviço Preferido
      final servicos = c['servicos'] as Map<String, int>;
      if (servicos.isNotEmpty) {
        final sortedServicos = servicos.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        c['servicoPreferido'] = sortedServicos.first.key;
      } else {
        c['servicoPreferido'] = "Nenhum";
      }

      // Intervalo Médio (em dias)
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

      // Ticket Médio
      final totalGasto = (c['totalGasto'] ?? 0.0) as double;
      c['ticketMedio'] = visits > 0 ? (totalGasto / visits) : 0.0;
    }

    // 9. Separar listas
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

    return Padding(
      padding: const EdgeInsets.only(right: 10.0, top: 10.0),
      child: Stack(
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
              right: -10,
              top: -10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  count.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClientListItem(
      Map<String, dynamic> client, bool isSelected, bool isMobile,
      {int? rank}) {
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
        leading: rank != null
            ? CircleAvatar(
                backgroundColor: _rankColor(rank),
                child: Text('$rank',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              )
            : CircleAvatar(
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
                "${client['visitas']} visitas • ${currency.format(client['ticketMedio'] ?? 0)} ticket",
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500)),
            Text(
                "Total: ${currency.format(client['totalGasto'])}",
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600)),
            if ((client['visitas'] ?? 0) > 0 && (client['ultimaVisita'] as DateTime?) != null)
              Text(
                "Última visita: ${DateFormat('dd/MM/yy').format(client['ultimaVisita'])}",
                style: TextStyle(fontSize: 10, color: Colors.grey[500])),
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

  Map<String, dynamic> _mergeClientEntry(
      Map<String, dynamic> primary, Map<String, dynamic> secondary) {
    primary['totalGasto'] = (primary['totalGasto'] ?? 0.0) + (secondary['totalGasto'] ?? 0.0);
    primary['visitas'] = (primary['visitas'] ?? 0) + (secondary['visitas'] ?? 0);
    primary['agendamentosCount'] = (primary['agendamentosCount'] ?? 0) + (secondary['agendamentosCount'] ?? 0);

    final primaryServicos = primary['servicos'] as Map<String, int>? ?? {};
    final secondaryServicos = secondary['servicos'] as Map<String, int>? ?? {};
    for (var e in secondaryServicos.entries) {
      primaryServicos[e.key] = (primaryServicos[e.key] ?? 0) + e.value;
    }
    primary['servicos'] = primaryServicos;

    final primaryDates = List<DateTime>.from(primary['visitasDates'] ?? []);
    final secondaryDates = List<DateTime>.from(secondary['visitasDates'] ?? []);
    primaryDates.addAll(secondaryDates);
    primary['visitasDates'] = primaryDates;

    final pFirst = primary['primeiraVisita'] as DateTime?;
    final sFirst = secondary['primeiraVisita'] as DateTime?;
    if (pFirst == null || (sFirst != null && sFirst.isBefore(pFirst))) {
      primary['primeiraVisita'] = sFirst;
    }

    final pLast = primary['ultimaVisita'] as DateTime?;
    final sLast = secondary['ultimaVisita'] as DateTime?;
    if (pLast == null || (sLast != null && sLast.isAfter(pLast))) {
      primary['ultimaVisita'] = sLast;
      primary['ultimoServico'] = secondary['ultimoServico'] ?? primary['ultimoServico'];
    }

    // Union de tags
    final primaryTags = List<String>.from(primary['tags'] ?? []);
    final secondaryTags = List<String>.from(secondary['tags'] ?? []);
    for (var t in secondaryTags) {
      if (!primaryTags.contains(t)) primaryTags.add(t);
    }
    primary['tags'] = primaryTags;

    // Mantém classificação mais específica (VIP > Novo > Sumido > Problematico)
    final pClass = (primary['classification'] ?? '').toString();
    final sClass = (secondary['classification'] ?? '').toString();
    const priority = ['vip', 'novo', 'sumido', 'problematico', 'problemático'];
    final pIdx = priority.indexOf(pClass);
    final sIdx = priority.indexOf(sClass);
    if (sIdx >= 0 && (pIdx < 0 || sIdx < pIdx)) {
      primary['classification'] = sClass;
    }

    return primary;
  }

  String _normalizePhone(String phone) {
    String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 12 && digits.startsWith('55')) {
      digits = digits.substring(2);
    }
    while (digits.length > 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  Color _rankColor(int rank) {
    if (rank == 1) return Colors.amber.shade700;
    if (rank == 2) return Colors.blueGrey.shade400;
    if (rank == 3) return Colors.brown.shade400;
    return Colors.grey.shade500;
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
