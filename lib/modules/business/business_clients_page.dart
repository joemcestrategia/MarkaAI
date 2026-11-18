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

  // Removido: abas Visitantes e Ranking

  // Filtro de Tags: "Todos", "VIP", "Sumido", "Problematico", "Novo"
  String _selectedTagFilter = "Todos";

  // --- CONTROLE DA COLUNA 3 (PC) ---
  Map<String, dynamic>? _selectedClientData;
  String? _selectedClientId;
  bool _showAddPanel = false;

  // --- CACHE LOCAL ---
  Map<String, dynamic>? _cachedData;
  int _lastStreamFingerprint = 0;
  final Set<String> _deletedClientIds = {};

  // --- STREAM CACHE ---
  Stream<Map<String, dynamic>>? _combinedStream;

  PlanFeatures _currentFeatures = planFeaturesConfig[PlanKey.free]!;

  @override
  void initState() {
    super.initState();
    _loadShopId();
  }

  Future<void> _loadShopId() async {
    final id = await SessionService.getShopId();
    if (mounted) {
      shopId = id;
      if (id != null) {
        final cached = await ClientCacheService.getCachedClients(id);
        if (cached != null) {
          _cachedData = cached;
          _lastStreamFingerprint =
              int.tryParse(cached['fingerprint']?.toString() ?? '') ??
              (cached['fingerprint']?.toString() ?? '').hashCode;
        }
        // Sempre revalida em segundo plano (stale-while-revalidate) para exibir
        // imediatamente clientes novos/editados/excluídos sem ficar preso no cache de 2h.
        _fetchInitialData(id);
        _combinedStream = _buildCombinedStream();
      }
      setState(() {
        if (id == null) {
          debugPrint("Erro: ShopID é null ao carregar BusinessClientsScreen");
        }
        _isLoadingId = false;
      });
    }
  }

  void _collectPhoneVariants(String? raw, Set<String> target) {
    if (raw == null || raw.trim().isEmpty) return;
    final clean = _normalizePhone(raw);
    if (clean.isNotEmpty) target.add(clean);
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isNotEmpty) target.add(digits);
    final trimmed = raw.trim();
    if (trimmed.isNotEmpty) target.add(trimmed);
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
          _collectPhoneVariants(phone, manualPhones);
        }
      }
      for (final sc in shopClients) {
        if (sc['is_manual_client'] == true) {
          _collectPhoneVariants(sc['telefone']?.toString(), manualPhones);
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
        if (missingIds.isNotEmpty) {
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

      // Busca aliases do Setmore (mapeamento shop_client_id → user_id)
      List<Map<String, dynamic>> aliasRows = [];
      try {
        final rawAliases = await supabase
            .from('shop_client_aliases')
            .select('user_id, shop_client_id')
            .eq('shop_id', shopId);
        aliasRows = List<Map<String, dynamic>>.from(rawAliases);
      } catch (_) {}

      if (mounted) {
        final processed = _processClientsData(
            appointments, usersMap, shopConfig, favorites, shopClients, shopViews, aliasRows);
        _lastStreamFingerprint = Object.hash(
          ClientCacheService.computeAppointmentsFingerprint(appointments),
          ClientCacheService.computeShopClientsFingerprint(shopClients),
          _deletedClientIds.length,
        );
        processed['fingerprint'] = _lastStreamFingerprint.toString();
        ClientCacheService.saveClients(shopId, processed);
        setState(() {
          _cachedData = processed;
          _currentFeatures = featuresForNow;
        });
      }
    } catch (e) {
      debugPrint('_fetchInitialData error: $e');
    }
  }

  void _handleClientDeletedOptimistically(String clientId) {
    setState(() {
      _deletedClientIds.add(clientId);
      final list = (_cachedData?['clients'] as List?)?.cast<Map<String, dynamic>>();
      list?.removeWhere((c) => c['id'] == clientId);
      if (_selectedClientId == clientId) {
        _selectedClientData = null;
        _selectedClientId = null;
      }
    });
    if (shopId != null) {
      if (_cachedData != null) {
        ClientCacheService.saveClients(shopId!, _cachedData!);
      }
      _fetchInitialData(shopId!);
    }
  }

  void _handleClientEditedOptimistically(
      String clientId, Map<String, dynamic> updatedClient) {
    setState(() {
      final list = (_cachedData?['clients'] as List?)?.cast<Map<String, dynamic>>();
      if (list != null) {
        for (final c in list) {
          if (c['id'] == clientId) {
            c.addAll(updatedClient);
            break;
          }
        }
      }
    });
    if (shopId != null) {
      _fetchInitialData(shopId!);
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
              onDeleted: () => _handleClientDeletedOptimistically(id),
              onChanged: () => _handleClientEditedOptimistically(id, client),
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
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ClientRegisterPage(isBusinessAdding: true),
        ),
      );
      if (shopId != null) {
        _fetchInitialData(shopId!);
      }
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
      final shopClients = (data['shopClients'] as List?) ?? [];
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
          _collectPhoneVariants(phone, manualPhones);
        }
      }
      for (final sc in shopClients) {
        if (sc['is_manual_client'] == true) {
          _collectPhoneVariants(sc['telefone']?.toString(), manualPhones);
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

      // Busca aliases do Setmore (mapeamento shop_client_id → user_id)
      List<Map<String, dynamic>> aliasRows = [];
      try {
        final rawAliases = await supabase
            .from('shop_client_aliases')
            .select('user_id, shop_client_id')
            .eq('shop_id', shopId!);
        aliasRows = List<Map<String, dynamic>>.from(rawAliases);
      } catch (_) {}

      return {...data, 'users': users, 'aliases': aliasRows};
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
                        ? ClientRegisterPage(
                            isBusinessAdding: true,
                            onSuccess: () {
                              _closePanel();
                              if (shopId != null) {
                                _fetchInitialData(shopId!);
                              }
                            },
                          )
                        : (_selectedClientData != null
                            ? ClientDetailsPage(
                                key: ValueKey(_selectedClientId),
                                clientData: _selectedClientData!,
                                clientId: _selectedClientId!,
                                onClose: _closePanel,
                                onDeleted: () => _handleClientDeletedOptimistically(
                                    _selectedClientId!),
                                onChanged: () => _handleClientEditedOptimistically(
                                    _selectedClientId!, _selectedClientData!),
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
                        // Inclui shop_clients: cadastro/edição/exclusão de cliente manual
                        // também precisa atualizar a lista em tempo real.
                        final shopClientsForFingerprint =
                            (data['shopClients'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                        final newFingerprint = Object.hash(
                          ClientCacheService.computeAppointmentsFingerprint(appointmentDocs),
                          ClientCacheService.computeShopClientsFingerprint(shopClientsForFingerprint),
                          _deletedClientIds.length,
                        );
                        if (newFingerprint != _lastStreamFingerprint) {
                          _lastStreamFingerprint = newFingerprint;

                          final usersDocs = (data['users'] as List?) ?? [];
                          final shopConfig = (data['shop'] as Map?)?['config'] as Map? ?? {};
                          final favoritesDocs = (data['favorites'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                          final shopClientsDocs = (data['shopClients'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                          final shopViewsDocs = (data['shopViews'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                          final aliasesDocs = (data['aliases'] as List?)?.cast<Map<String, dynamic>>() ?? [];

                          final Map<String, Map<String, dynamic>> usersMap = {
                            for (var doc in usersDocs)
                              if (doc is Map && doc['id'] != null)
                                doc['id'].toString(): doc as Map<String, dynamic>
                          };

                          final freshData = _processClientsData(
                              appointmentDocs, usersMap, shopConfig,
                              favoritesDocs, shopClientsDocs, shopViewsDocs,
                              aliasesDocs);

                          if (shopId != null) {
                            freshData['fingerprint'] = _lastStreamFingerprint.toString();
                            ClientCacheService.saveClients(shopId!, freshData);
                          }
                          _cachedData = freshData;
                        }
                      } catch (e) {
                        debugPrint('StreamBuilder processing error: $e');
                      }
                    }

                    final displayData = _cachedData;
                    if (displayData == null) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    List<Map<String, dynamic>> targetList = (displayData['clients'] as List?)?.cast<Map<String, dynamic>>() ?? [];

                    final filteredDocs = targetList.where((client) {
                      if (_deletedClientIds.contains(client['id'])) return false;
                      final nome = (client['name'] ?? "").toString();
                      final normalizedNome =
                          StringUtils.removeDiacritics(nome).toLowerCase();
                      final normalizedSearch =
                          StringUtils.removeDiacritics(_searchText).toLowerCase();
                      if (!normalizedNome.contains(normalizedSearch)) return false;
                      if (_selectedTagFilter == "Todos") return true;
                      if (_selectedTagFilter == "Manual") {
                        return client['is_manual_client'] == true;
                      }
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

                    // Remove quem nunca agendou (leads puros),
                    // EXCETO clientes cadastrados manualmente pela dona do salão
                    filteredDocs.removeWhere((c) =>
                        (c['agendamentosCount'] ?? 0) == 0 &&
                        (c['is_manual_client'] != true));
                    // Ordena alfabeticamente
                    filteredDocs.sort((a, b) {
                      final na = (a['name'] ?? '').toString().toLowerCase();
                      final nb = (b['name'] ?? '').toString().toLowerCase();
                      return na.compareTo(nb);
                    });

                    return Column(
                      children: [
                        // Aba de botões removida

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
                                _buildTagFilterChip(
                                  "Manual",
                                  icon: Icons.person_pin_outlined,
                                  color: Colors.orange,
                                  forceUnlocked: true,
                                ),
                                const SizedBox(width: 8),
                                _buildTagFilterChip("VIP",
                                    icon: Icons.star,
                                    color: Colors.amber),
                                const SizedBox(width: 8),
                                _buildTagFilterChip("Novo",
                                    icon: Icons.new_releases,
                                    color: Colors.green),
                                const SizedBox(width: 8),
                                _buildTagFilterChip("Sumido",
                                    icon: Icons.timer_off_outlined,
                                    color: Colors.grey),
                                const SizedBox(width: 8),
                                _buildTagFilterChip("Problemático",
                                    icon: Icons.warning_amber_rounded,
                                    color: Colors.red),
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
                                        rank: null);
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
      List<Map<String, dynamic>> shopViews,
      [List<Map<String, dynamic>> aliasesDocs = const []]) {

    // Mapa de aliases: user_id (real) → lista de shop_client_ids do Setmore
    final Map<String, List<String>> aliasesMap = {};
    for (var a in aliasesDocs) {
      final uid   = a['user_id']?.toString() ?? '';
      final scId  = a['shop_client_id']?.toString() ?? '';
      if (uid.isNotEmpty && scId.isNotEmpty) {
        aliasesMap.putIfAbsent(uid, () => []).add(scId);
      }
    }

    Map<String, Map<String, dynamic>> allClientsMap = {};
    final now = DateTime.now();

    // Mapas reversos: telefone/email normalizado → usuário (para vincular agendamentos manuais
    // e detectar duplicidade em cadastros manuais)
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

    // 1. Processar dados de 'shop_clients' (Tags manuais e customizações)
    //    Separa clientes manuais (is_manual_client=true, user_id=null) dos
    //    registros de metadados de clientes Auth (user_id preenchido).
    final Map<String, Map<String, dynamic>> manualDataMap = {
      for (var doc in shopClients)
        if ((doc['user_id'] ?? doc['userId']) != null)
          (doc['user_id'] ?? doc['userId']).toString(): doc
    };

    // 1b. Clientes puramente manuais (sem conta Auth): entram direto no allClientsMap
    //     já no início, para que possam ser vistos mesmo sem agendamentos.
    // Índice telefone normalizado → cadastros manuais, usado para unificar os
    // agendamentos (gravados só com nome/telefone) ao cadastro manual do cliente.
    final Map<String, List<MapEntry<String, String>>> manualScByPhone = {};
    final Set<String> deletedManualSignatures = {};
    final Map<String, Map<String, dynamic>> duplicatedAuthToManual = {};
    for (var doc in shopClients) {
      if (doc['is_manual_client'] != true) continue;
      if ((doc['user_id'] ?? doc['userId']) != null) continue; // já tem conta, tratado depois

      final scId = doc['id']?.toString() ?? '';
      if (scId.isEmpty) continue;

      final nome = doc['nome']?.toString() ?? 'Cliente Manual';
      final telefone = doc['telefone']?.toString() ?? 'Não informado';
      final normManualPhone = _normalizePhone(telefone);
      final normManualName = StringUtils.removeDiacritics(nome).trim().toLowerCase();

      final key = 'manual_sc_$scId';
      if ((doc['notes'] ?? '').toString() == '[DELETED_MANUAL]' ||
          doc['is_deleted'] == true ||
          _deletedClientIds.contains(key)) {
        if (normManualPhone.isNotEmpty && normManualName.isNotEmpty) {
          deletedManualSignatures.add('$normManualPhone|$normManualName');
        }
        continue;
      }

      if (normManualPhone.isNotEmpty) {
        manualScByPhone
            .putIfAbsent(normManualPhone, () => [])
            .add(MapEntry(key, normManualName));
      }

      final matchedAuth = normManualPhone.isNotEmpty ? phoneToUser[normManualPhone] : null;
      final bool hasAuthAccount = (doc['has_auth_account'] == true) || (matchedAuth != null);
      final matchedAuthId = matchedAuth?['id']?.toString() ?? '';
      if (matchedAuthId.isNotEmpty) {
        duplicatedAuthToManual[matchedAuthId] = {
          'manualKey': key,
          'manualName': nome,
          'manualPhone': telefone,
          'manualScId': scId,
        };
      }

      allClientsMap[key] = {
        'id': key,
        'name': nome,
        'nome': nome,
        'telefone': telefone,
        'foto': doc['photo_url'] ?? '',
        'origem': 'manual',
        'is_manual_client': true,
        'has_auth_account': hasAuthAccount,
        'matched_auth_name': matchedAuth?['name']?.toString() ?? '',
        'matched_auth_id': matchedAuthId,
        'matched_auth_email': matchedAuth?['email']?.toString() ?? '',
        'matched_auth_cpf': matchedAuth?['cpf']?.toString() ?? '',
        'matched_auth_city': matchedAuth?['city']?.toString() ?? '',
        'totalGasto': 0.0,
        'visitas': 0,
        'agendamentosCount': 0,
        'primeiraVisita': now,
        'ultimaVisita': DateTime(2000),
        'email': doc['email'] ?? '',
        'city': doc['city'] ?? '',
        'state': doc['state'] ?? '',
        'street': doc['street'] ?? '',
        'neighborhood': doc['neighborhood'] ?? '',
        'number': doc['number'] ?? '',
        'zipCode': doc['zip_code'] ?? '',
        'cpf': doc['cpf'] ?? '',
        'birthDate': doc['birth_date'] ?? '',
        'isFavorite': false,
        'isVisitor': false,
        'lastViewed': null,
        'tags': List<String>.from(doc['manual_tags'] ?? []),
        'classification': doc['classification'] ?? '',
        'servicos': <String, int>{},
        'visitasDates': <DateTime>[],
        'ultimoServico': '',
        'ids': [],
      };
    }

    // 2. Processar Favoritos
    final Set<String> favoritedIds = favorites.map((f) => (f['user_id'] ?? f['userId'] ?? '').toString()).where((id) => id.isNotEmpty).toSet();

    // 3. Processar Visualizações (Leads)
    final Map<String, DateTime> visitorIds = {
      for (var v in shopViews)
        (v['user_id'] ?? v['userId'] ?? '').toString(): DateTime.tryParse(v['viewed_at']?.toString() ?? "") ?? now
    };

    // 4.5. Desduplicar Agendamentos (Setmore pode criar múltiplas linhas para o mesmo evento)
    final Map<String, Map<String, dynamic>> dedupedAppointmentsMap = {};
    for (var doc in appointments) {
      String? userId = (doc['client_id'] ?? doc['clientId'])?.toString();
      String rawClientPhone = (doc['client_phone'] ?? '').toString();
      String normalizedPhone = _normalizePhone(rawClientPhone);
      String clientEmail = (doc['client_email'] ?? '').toString().trim().toLowerCase();
      
      String clientKey = userId != null && userId.isNotEmpty ? userId : (normalizedPhone.isNotEmpty ? normalizedPhone : clientEmail);
      
      // Normalizar data para garantir que formatos de string diferentes da mesma data agrupem juntos
      DateTime scheduledDate = DateTime.tryParse((doc['scheduled_at'] ?? "").toString()) ?? DateTime(1970);
      String scheduledAtKey = scheduledDate.millisecondsSinceEpoch.toString();
      if (scheduledDate.year == 1970) scheduledAtKey = doc['id'].toString(); // fallback para ID se não tiver data válida

      final String eventKey = "$clientKey-$scheduledAtKey";

      final currentDoc = dedupedAppointmentsMap[eventKey];
      if (currentDoc == null) {
        dedupedAppointmentsMap[eventKey] = doc;
      } else {
        DateTime currentCreated = DateTime.tryParse(currentDoc['created_at']?.toString() ?? "") ?? DateTime(2000);
        DateTime docCreated = DateTime.tryParse(doc['created_at']?.toString() ?? "") ?? DateTime(2000);
        if (docCreated.isAfter(currentCreated)) {
          dedupedAppointmentsMap[eventKey] = doc;
        }
      }
    }
    final List<Map<String, dynamic>> dedupedAppointments = dedupedAppointmentsMap.values.toList();

    // 5. Processar Agendamentos (Principal fonte de clientes)
    for (var doc in dedupedAppointments) {
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

      // Cliente manual excluído pelo lojista que tinha agendamentos passados:
      // não recriar o cliente na lista (os agendamentos ficam preservados no financeiro).
      if (matchedUser == null && wasManual && normalizedPhone.isNotEmpty) {
        final apptName = StringUtils.removeDiacritics(nome).trim().toLowerCase();
        if (deletedManualSignatures.contains('$normalizedPhone|$apptName')) {
          continue;
        }
      }

      // Agendamento manual (sem conta Auth) de um cliente cadastrado manualmente
      // (mesmo telefone e mesmo nome): unifica no cadastro manual, sem duplicar.
      if (matchedUser == null && wasManual && normalizedPhone.isNotEmpty) {
        final manualCandidates = manualScByPhone[normalizedPhone];
        if (manualCandidates != null) {
          final apptName = StringUtils.removeDiacritics(nome).trim().toLowerCase();
          for (final candidate in manualCandidates) {
            if (candidate.value == apptName) {
              key = candidate.key;
              break;
            }
          }
        }
      }

      double valor = double.tryParse(
              (data['total_price'] ?? data['total_value'] ?? "0")
                  .toString()) ??
          0.0;
      DateTime dataVisita = DateTime.tryParse(data['scheduled_at'] ?? "") ?? now;
      String status = (data['status'] ?? "").toString().toLowerCase();
      final bool pastAppointment = dataVisita.isBefore(now);
      
      // Definições unificadas de visitas reais (MarkaAI + Setmore)
      final bool isRealVisitStatus = status == 'concluido' || status == 'pago' || status == 'finalizado' || status == 'confirmado' || status == 'confirmed_by_client';
      final bool countsAsVisit = pastAppointment && isRealVisitStatus;

      if (!allClientsMap.containsKey(key)) {
        final String effectiveUserId = matchedUser?['id']?.toString() ?? userId ?? '';

        allClientsMap[key] = {
          'id': key,
          'name': nome,
          'nome': nome,
          'telefone': telefone.isNotEmpty ? telefone : "Não informado",
          'foto': photoUrl,
          'origem': wasManual ? 'manual' : 'app',
          'totalGasto': countsAsVisit ? valor : 0.0,
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
          // IDs dos registros Setmore vinculados (alias) — usados no ClientDetailsPage
          'ids': aliasesMap[effectiveUserId] ?? [],
        };
        if (countsAsVisit) {
          final sName = data['service_name'] ?? data['serviceName'] ?? "";
          if (sName.isNotEmpty) allClientsMap[key]!['servicos'][sName] = 1;
        }
      } else {
        if (countsAsVisit) {
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

    // 5. Adicionar Favoritos, Visitantes e Contas do Sistema com par manual duplicado
    final Set<String> allUserIds = {
      ...favoritedIds,
      ...visitorIds.keys,
      ...duplicatedAuthToManual.keys,
    };
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
      final dupInfo = duplicatedAuthToManual[uid];
      if (dupInfo != null && allClientsMap.containsKey(uid)) {
        allClientsMap[uid]!['has_manual_duplicate'] = true;
        allClientsMap[uid]!['manual_duplicate_name'] = dupInfo['manualName'] ?? '';
        allClientsMap[uid]!['manual_duplicate_phone'] = dupInfo['manualPhone'] ?? '';
        allClientsMap[uid]!['manual_duplicate_sc_id'] = dupInfo['manualScId'] ?? '';
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
      // Clientes manuais não devem ser unificados (podem ser dependentes com mesmo telefone)
      if (entry.value['origem'] == 'manual') continue;

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
        if (entry.value['origem'] == 'manual') continue;

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

  Widget _buildTagFilterChip(String label, {IconData? icon, Color? color, bool isLocked = false, bool forceUnlocked = false}) {
    // Garantir que a flag de lock use o plano em cache caso o stream atrase
    final features = PlanFeaturesService.cachedFeatures ?? _currentFeatures;
    final actuallyLocked = forceUnlocked
        ? false
        : (isLocked || (!features.clientFilter && !features.clientClassification));
    
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
      avatar: actuallyLocked 
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
        if (actuallyLocked) {
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
              children: [
                if (client['is_manual_client'] == true &&
                    client['has_auth_account'] == true)
                  _buildTag("DUPLICADO", Colors.deepOrange, Icons.compare_arrows)
                else if (client['is_manual_client'] == true &&
                    _selectedTagFilter != "Manual")
                  _buildTag("MANUAL", Colors.orange.shade800, Icons.edit_note),
                ...(client['tags'] as List? ?? [])
                    .map<Widget>((tag) => _buildTagFromType(tag.toString())),
              ],
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

    if (secondary['has_manual_duplicate'] == true) {
      primary['has_manual_duplicate'] = true;
      primary['manual_duplicate_name'] =
          secondary['manual_duplicate_name'] ?? primary['manual_duplicate_name'];
      primary['manual_duplicate_phone'] =
          secondary['manual_duplicate_phone'] ?? primary['manual_duplicate_phone'];
      primary['manual_duplicate_sc_id'] =
          secondary['manual_duplicate_sc_id'] ?? primary['manual_duplicate_sc_id'];
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
