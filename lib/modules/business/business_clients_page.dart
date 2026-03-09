import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/string_utils.dart';
import '../clients/client_register_page.dart';
import '../clients/client_details_page.dart';
import 'subscription_service.dart';
import 'subscription_plans_page.dart';

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

  // --- CONTROLE DA COLUNA 3 (PC) ---
  Map<String, dynamic>? _selectedClientData;
  String? _selectedClientId;
  bool _showAddPanel = false;

  @override
  void initState() {
    super.initState();
    _loadShopId();
  }

  Future<void> _loadShopId() async {
    final id = await SessionService.getShopId();
    if (mounted) {
      setState(() {
        shopId = id;
        if (id == null) {
          debugPrint("Erro: ShopID é null ao carregar BusinessClientsScreen");
        }
        _isLoadingId = false;
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
        _showUpgradeDialog();
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

  @override
  Widget build(BuildContext context) {
    if (_isLoadingId) return const Center(child: CircularProgressIndicator());

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

        // 3. LISTA FILTRADA
        shopId == null
            ? const Center(child: Text("Erro: ID da Loja não encontrado"))
            : Expanded(
                child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('shops')
                        .doc(shopId)
                        .collection('clients')
                        .snapshots(),
                    builder: (context, clientsSnapshot) {
                      if (clientsSnapshot.hasError) {
                        return const Center(
                            child: Text(
                                "Erro ao carregar configurações de clientes"));
                      }

                      final clientSettingsDocs =
                          clientsSnapshot.data?.docs ?? [];
                      final Map<String, Map<String, dynamic>> clientSettings = {
                        for (var doc in clientSettingsDocs)
                          doc.id: doc.data() as Map<String, dynamic>
                      };

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('appointments')
                            .where('shopId', isEqualTo: shopId)
                            .orderBy('data_agendamento', descending: true)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            debugPrint(
                                "Erro ao carregar clientes: ${snapshot.error}");
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline,
                                      color: Colors.red, size: 48),
                                  const SizedBox(height: 16),
                                  Text(
                                    "Erro ao carregar clientes.\nVerifique sua conexão ou contate o suporte.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.red[700]),
                                  ),
                                  if (snapshot.error
                                      .toString()
                                      .contains('index'))
                                    const Padding(
                                      padding: EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        "Requer índice do Firestore.",
                                        style: TextStyle(
                                            fontSize: 12, color: Colors.grey),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          final processedData = _processAppointments(
                              snapshot.data!.docs, clientSettings);
                          List<Map<String, dynamic>> targetList =
                              _selectedTabIndex == 0
                                  ? processedData['app']!
                                  : processedData['manual']!;

                          final filteredDocs = targetList.where((client) {
                            final nome = (client['nome'] ?? "").toString();
                            final normalizedNome =
                                StringUtils.removeDiacritics(nome)
                                    .toLowerCase();
                            final normalizedSearch =
                                StringUtils.removeDiacritics(_searchText)
                                    .toLowerCase();

                            return normalizedNome.contains(normalizedSearch);
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
                      );
                    }),
              ),
      ],
    );
  }

  // ... (Mantenha o _processAppointments IGUAL ao anterior, não mudei nada nele) ...
  Map<String, List<Map<String, dynamic>>> _processAppointments(
      List<QueryDocumentSnapshot> docs,
      Map<String, Map<String, dynamic>> clientSettings) {
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
          'ultimaVisita': dataVisita,
          'email': "",
          'birthDate':
              data['data_nascimento'] ?? data['nascimento'] ?? data['birthDate']
        };
      } else {
        targetMap[key]!['totalGasto'] += valor;
        targetMap[key]!['visitas'] += 1;
        if (dataVisita.isAfter(targetMap[key]!['ultimaVisita'])) {
          targetMap[key]!['ultimaVisita'] = dataVisita;
        }
        if (nome != "Cliente Desconhecido") {
          targetMap[key]!['nome'] = nome;
        }
      }
    }

    // --- RANKING CALCULATION ---
    // 1. Sort by total spent to find VIPs (Top 20%)
    final allApps = appClientsMap.values.toList();
    if (allApps.isNotEmpty) {
      allApps.sort((a, b) =>
          (b['totalGasto'] as double).compareTo(a['totalGasto'] as double));
      int topCount = (allApps.length * 0.2).ceil(); // Top 20%
      for (int i = 0; i < allApps.length; i++) {
        if (i < topCount && (allApps[i]['totalGasto'] as double) > 0) {
          allApps[i]['tags'] = [...(allApps[i]['tags'] ?? []), 'vip'];
        }
      }
    }

    // 2. Add 'Fiel' and 'Novo' tags AND Manual Classification Override
    final now = DateTime.now();
    for (var c in allApps) {
      List<String> tags = List<String>.from(c['tags'] ?? []);

      // Auto tags
      if ((c['visitas'] as int) > 5) tags.add('fiel');
      if ((c['visitas'] as int) == 1 &&
          (c['ultimaVisita'] as DateTime).difference(now).inDays.abs() < 30) {
        tags.add('novo');
      }

      // Manual Override
      final settings = clientSettings[c['id']];
      if (settings != null && settings['classification'] != null) {
        // Se houver classificação manual, ela pode ser adicionada ou substituir.
        // Vamos adicionar como uma tag especial se não existir
        String manualClass =
            settings['classification'].toString().toLowerCase();
        if (!tags.contains(manualClass)) {
          tags.insert(0, manualClass); // Prioridade visual
        }
        // Também injetamos no mapa para uso direto
        c['classification'] = manualClass;
      }

      c['tags'] = tags;
    }

    return {
      'app': allApps,
      // ?? FILTRO DE LIMPEZA: Remove clientes manuais sem telefone (provavelmente apenas agendamentos rápidos)
      // O usuário solicitou não mostrar esses registros pois não tem dados relevantes para CRM.
      'manual': manualClientsMap.values
          .where((c) =>
              c['telefone'] != null &&
              c['telefone'].toString().isNotEmpty &&
              c['telefone'] != "Não informado")
          .toList()
    };
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    bool isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
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
            Row(
              children: [
                if ((client['tags'] as List?)?.contains('vip') ?? false)
                  _buildTag("VIP", Colors.amber, Icons.star),
                if ((client['tags'] as List?)?.contains('fiel') ?? false)
                  _buildTag("Fiel", Colors.blue, Icons.thumb_up),
                if ((client['tags'] as List?)?.contains('novo') ?? false)
                  _buildTag("Novo", Colors.green, Icons.new_releases),
                // Exibe qualquer outra tag manual que não seja as automáticas acima (para flexibilidade)
                if (client['classification'] != null &&
                    !['vip', 'fiel', 'novo'].contains(client['classification']))
                  _buildTag(client['classification'].toString().toUpperCase(),
                      Colors.purple, Icons.label),
              ],
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

  Widget _buildTag(String label, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
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

  void _showUpgradeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Limite de Clientes Atingido"),
        content: const Text(
            "Você atingiu o limite de clientes do seu plano atual (Starter).\n\n"
            "Faça um upgrade para adicionar ilimitados clientes e desbloquear recursos exclusivos!"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const SubscriptionPlansPage()));
              if (mounted) setState(() {});
            },
            child: const Text("Ver Planos"),
          )
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
