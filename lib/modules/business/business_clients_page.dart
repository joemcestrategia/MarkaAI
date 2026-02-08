import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../clients/client_register_page.dart';
import '../clients/client_details_page.dart';

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
        _isLoadingId = false;
      });
    }
  }

  // 🧠 LÓGICA INTELIGENTE DE NAVEGAÇÃO
  void _handleClientTap(BuildContext context, Map<String, dynamic> client, String id, bool isMobile) {
    if (isMobile) {
      // 📱 MODO CELULAR: Navega para nova tela
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: Text(client['nome']), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 1),
            body: ClientDetailsPage(
              clientData: client,
              clientId: id,
              onClose: () => Navigator.pop(context),
            ),
          ),
        ),
      );
    } else {
      // 💻 MODO PC: Abre na lateral
      setState(() {
        _showAddPanel = false;
        _selectedClientData = client;
        _selectedClientId = id;
      });
    }
  }

  void _handleNewClientTap(BuildContext context, bool isMobile) {
    if (isMobile) {
      // 📱 MODO CELULAR: Navega para nova tela
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text("Novo Cliente"), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 1),
            body: const ClientRegisterPage(isBusinessAdding: true),
          ),
        ),
      );
    } else {
      // 💻 MODO PC: Abre na lateral
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

    // 🛡️ O GUARDIÃO DO LAYOUT: Verifica a largura da tela
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

  // 🧩 WIDGET EXTRAÍDO: Conteúdo da Lista (Reusável)
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
                  onChanged: (value) => setState(() => _searchText = value.toLowerCase()),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Buscar por nome...",
                    prefixIcon: const Icon(Icons.search, color: AppColors.primaryPurple, size: 20),
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              ElevatedButton.icon(
                onPressed: () => _handleNewClientTap(context, isMobile),
                icon: const Icon(Icons.person_add, size: 18),
                label: Text(isMobile ? "NOVO" : "NOVO CLIENTE"), // Texto menor no mobile
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: SingleChildScrollView( // Permite rolar as abas em telas muito pequenas
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTabButton(0, "📱 Pelo App", Icons.smartphone),
                const SizedBox(width: 15),
                _buildTabButton(1, "📝 Manuais", Icons.edit_note),
              ],
            ),
          ),
        ),

        // 3. LISTA FILTRADA
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('appointments')
                .where('shopId', isEqualTo: shopId)
                .orderBy('data_agendamento', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              final processedData = _processAppointments(snapshot.data!.docs);
              List<Map<String, dynamic>> targetList =
                  _selectedTabIndex == 0 ? processedData['app']! : processedData['manual']!;

              final filteredDocs = targetList.where((client) {
                final nome = (client['nome'] ?? "").toString().toLowerCase();
                return nome.contains(_searchText);
              }).toList();

              if (filteredDocs.isEmpty) return _buildEmptyState();

              return ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: filteredDocs.length,
                itemBuilder: (context, index) {
                  final client = filteredDocs[index];
                  // No mobile, nada fica "selecionado" visualmente pois abrimos nova tela
                  bool isSelected = !isMobile && _selectedClientId == client['id'];
                  
                  return _buildClientListItem(client, isSelected, isMobile);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ... (Mantenha o _processAppointments IGUAL ao anterior, não mudei nada nele) ...
  Map<String, List<Map<String, dynamic>>> _processAppointments(List<QueryDocumentSnapshot> docs) {
    Map<String, Map<String, dynamic>> appClientsMap = {};
    Map<String, Map<String, dynamic>> manualClientsMap = {};

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      
      String nome = data['client_nome'] ?? data['client_name'] ?? data['clientName'] ?? data['cliente_nome'] ?? "Cliente Desconhecido";
      String telefone = data['client_phone'] ?? data['telefone'] ?? data['whatsapp'] ?? ""; 
      String? userId = data['clientId'];

      bool isManual = (userId == null || userId.isEmpty);

      String key;
      if (!isManual) {
        key = userId;
      } else {
        key = telefone.isNotEmpty ? telefone : "doc_${doc.id}"; 
      }

      double valor = double.tryParse(data['valor_total']?.toString() ?? "0") ?? 0.0;
      DateTime dataVisita;
      try { dataVisita = (data['data_agendamento'] as Timestamp).toDate(); } catch (e) { dataVisita = DateTime.now(); }

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
          'email': ""
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

    return {
      'app': appClientsMap.values.toList(),
      'manual': manualClientsMap.values.toList()
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
          border: isSelected ? Border.all(color: Colors.transparent) : Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey[600]),
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

  Widget _buildClientListItem(Map<String, dynamic> client, bool isSelected, bool isMobile) {
    final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    bool isManual = client['origem'] == 'manual';
    Color themeColor = isManual ? Colors.orange : AppColors.primaryPurple;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected ? themeColor.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isSelected ? Border.all(color: themeColor, width: 1.5) : Border.all(color: Colors.transparent),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 5)],
      ),
      child: ListTile(
        onTap: () => _handleClientTap(context, client, client['id'], isMobile), // <--- AQUI A MÁGICA
        leading: CircleAvatar(
          backgroundColor: themeColor.withValues(alpha: 0.1),
          child: Text((client['nome'] ?? "?").substring(0, 1).toUpperCase(),
              style: TextStyle(color: themeColor, fontWeight: FontWeight.bold)),
        ),
        title: Text(client['nome'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (client['telefone'] != "Não informado")
              Text(client['telefone'], style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 2),
            Text("${client['visitas']} visitas • Total: ${currency.format(client['totalGasto'])}",
                style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
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
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
                Icon(Icons.analytics_outlined, size: 80),
                SizedBox(height: 16),
                Text("Selecione um cliente", style: TextStyle(fontWeight: FontWeight.bold))
              ])));

  Widget _buildEmptyState() => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.person_off, size: 50, color: Colors.grey[300]),
        const SizedBox(height: 10),
        Text("Nenhum cliente nesta categoria.", style: TextStyle(color: Colors.grey[500]))
      ]));
}