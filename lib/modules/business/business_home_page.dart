import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_application_1/modules/business/store_profile_page.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/services/notification_service.dart';
import '../login/login_page.dart';

// --- MÓDULOS ---
import '../services/services_management_page.dart';
import '../team/team_management_page.dart';
import 'business_settings_page.dart';
import 'business_schedule_page.dart';
import 'business_clients_page.dart';
// import '../settings/excel_import_page.dart'; // Import removed — recurso 'Importar Dados' descontinuado
import '../financial/financial_dashboard_page.dart';

import 'inventory_page.dart';

class BusinessHomePage extends StatefulWidget {
  const BusinessHomePage({super.key});

  @override
  State<BusinessHomePage> createState() => _BusinessHomePageState();
}

class _BusinessHomePageState extends State<BusinessHomePage> {
  int _selectedIndex = 0;

  String? shopId;
  String userName = "Profissional";
  String userEmail = "";
  String? userPhotoUrl;

  String shopName = "MarkaAI Painel";
  String? shopLogoUrl;
  String? shopImageUrl;

  bool _isLoading = true;

  int _selectedYear = DateTime.now().year; // Começa com o ano atual para economizar
  // Lista inicial apenas com o ano atual, será populada dinamicamente se necessário
  List<int> _availableYears = [DateTime.now().year];

  @override
  void initState() {
    super.initState();
    _checkBusinessAndLoad();
    _setupForegroundNotifications();
  }

  void _setupForegroundNotifications() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primaryPurple,
            content: Text(
              "${message.notification!.title}: ${message.notification!.body}",
            ),
            action: SnackBarAction(
              label: "VER",
              textColor: Colors.white,
              onPressed: () {
                setState(() => _selectedIndex = 1);
              },
            ),
          ),
        );
      }
    });
  }

  Future<void> _checkBusinessAndLoad() async {
    try {
      final id = await SessionService.getShopId();
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        _forceLogout();
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        _forceLogout();
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      String tipo = userData['tipo'] ?? 'cliente';
      String currentShopId = id ?? userData['shopId'] ?? "";

      if (tipo != 'dono' && tipo != 'business') {
        _forceLogout();
        return;
      }

      if (currentShopId.isEmpty) {
        _forceLogout();
        return;
      }

      // Tenta buscar anos disponíveis (opcional, para popular o dropdown)
      // Para economizar, podemos manter fixo ou fazer uma query leve de agregação futuramente
      // Por enquanto, vou gerar de 2024 até o ano atual + 1
      final currentYear = DateTime.now().year;
      _availableYears = List.generate(5, (index) => (currentYear - 2) + index);

      if (mounted) {
        setState(() {
          shopId = currentShopId;
          userName = userData['nome'] ?? "Profissional";
          userEmail = user.email ?? "";
          userPhotoUrl = user.photoURL;
          _isLoading = false;
        });
        
        // 🔔 Inicializar notificações push para o dono da loja
        NotificationService.initialize().then((_) {
          debugPrint('✅ Notificações inicializadas para o dono da loja');
        }).catchError((e) {
          debugPrint('❌ Erro ao inicializar notificações: $e');
        });
      }
    } catch (e) {
      debugPrint('Error loading business data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _forceLogout();
      }
    }
  }

  void _forceLogout() async {
    // Remover token FCM antes de fazer logout
    await NotificationService.removeToken();
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Sair da Conta"),
        content: const Text("Deseja realmente sair do App?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              _forceLogout();
            },
            child: const Text(
              "Sair",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // --- MENU ACTIONS ---
  void _handleMenuAction(String value) {
    switch (value) {
      case 'perfil':
        Navigator.push(context, MaterialPageRoute(builder: (_) => StoreProfilePage()));
        break;
      case 'advanced':
        _showAdvancedOptionsDialog();
        break;
      
      case 'importar':
        // Importar removido — manter compatibilidade caso seja chamado
        // Navigator.push(context, MaterialPageRoute(builder: (_) => const ExcelImportPage()));
        break;
      case 'sair':
        _confirmLogout();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: AppColors.primaryPurple,
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: shopId != null
          ? FirebaseFirestore.instance.collection('shops').doc(shopId).snapshots()
          : null,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          shopName = data['nome'] ?? "Meu Negócio";

          shopLogoUrl = (data['logoUrl'] != null &&
                  data['logoUrl'].toString().isNotEmpty)
              ? data['logoUrl']
              : data['foto'];

          shopImageUrl = (data['imageUrl'] != null &&
                  data['imageUrl'].toString().isNotEmpty)
              ? data['imageUrl']
              : null;
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            bool isDesktop = constraints.maxWidth > 900;
            return isDesktop ? _buildDesktopLayout() : _buildMobileLayout();
          },
        );
      },
    );
  }

  List<Widget> _buildScreens({required bool isDesktop}) {
    return [
      _buildHomeDashboard(isDesktop: isDesktop), // 0
      BusinessSchedulePage(shopId: shopId ?? ""), // 1
      const ServicesManagementPage(), // 2
      const BusinessClientsScreen(), // 3
      const FinancialDashboardPage(), // 4
      const TeamManagementPage(), // 5
      const BusinessSettingsPage(), // 6
      const InventoryPage(), // 7 Estoque
    ];
  }

  // ============================================================================
  // DESKTOP LAYOUT
  // ============================================================================

  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      body: Row(
        children: [
          _buildDesktopSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildDesktopHeader(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: _buildScreens(isDesktop: true)[_selectedIndex],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopSidebar() {
    return Container(
      width: 250,
      color: Colors.white,
      child: Column(
        children: [
          const SizedBox(height: 25),
          Image.asset(
            'assets/images/logo_full.png',
            width: 140,
            errorBuilder: (context, error, stackTrace) {
              return const Text(
                "MarkaAI",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: AppColors.primaryPurple,
                ),
              );
            },
          ),
          const SizedBox(height: 25),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDesktopMenuItem(0, Icons.dashboard_rounded, "Visão Geral"),
                _buildDesktopMenuItem(1, Icons.event_note_rounded, "Agenda Completa"),
                _buildDesktopMenuItem(2, Icons.design_services_rounded, "Meus Serviços"),
                _buildDesktopMenuItem(3, Icons.groups_rounded, "Base de Clientes"),
                _buildDesktopMenuItem(4, Icons.account_balance_wallet_rounded, "Financeiro"),
                _buildDesktopMenuItem(5, Icons.people_outline, "Equipe"),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Divider(height: 1),
                ),
                _buildDesktopMenuItem(6, Icons.settings_outlined, "Configurações"),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text("v1.0 Pro", style: TextStyle(fontSize: 10, color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopMenuItem(int index, IconData icon, String label) {
    bool isSelected = _selectedIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primaryPurple.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Icon(
          icon,
          color: isSelected ? AppColors.primaryPurple : Colors.grey[600],
          size: 20,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.primaryPurple : Colors.grey[800],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
        onTap: () => setState(() => _selectedIndex = index),
      ),
    );
  }

  Widget _buildDesktopHeader() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _getScreenTitle(_selectedIndex),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          PopupMenuButton<String>(
            offset: const Offset(0, 50),
            color: Colors.white,
            surfaceTintColor: Colors.white,
            onSelected: _handleMenuAction,
            child: Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      userName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      shopName,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: shopLogoUrl != null
                      ? CachedNetworkImageProvider(shopLogoUrl!)
                      : (userPhotoUrl != null
                          ? CachedNetworkImageProvider(userPhotoUrl!)
                          : null),
                  child: (shopLogoUrl == null && userPhotoUrl == null)
                      ? const Icon(Icons.person, size: 20)
                      : null,
                ),
                const SizedBox(width: 5),
                const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey),
              ],
            ),
            itemBuilder: (context) => [
              _buildPopupItem('perfil', Icons.store, "Perfil da Loja"),
              _buildPopupItem('advanced', Icons.security, "Opções Avançadas"),
              const PopupMenuDivider(),
              _buildPopupItem('sair', Icons.logout, "Sair", isRed: true),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(String value, IconData icon, String text, {bool isRed = false}) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: isRed ? Colors.red : Colors.grey[700]),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(color: isRed ? Colors.red : Colors.black87, fontSize: 13)),
        ],
      ),
    );
  }

  Future<void> _showBusinessTopMenu() async {
    final choice = await showDialog<String>(context: context, builder: (ctx) {
      return SimpleDialog(
        title: const Text('Menu'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'perfil'), child: Row(children: const [Icon(Icons.store), SizedBox(width:8), Text('Perfil da Loja')])),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'pagamentos'), child: Row(children: const [Icon(Icons.credit_card), SizedBox(width:8), Text('Configurar Pagamento')])),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'importar'), child: Row(children: const [Icon(Icons.cloud_upload_outlined), SizedBox(width:8), Text('Importar Dados')])),
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'sair'), child: Row(children: const [Icon(Icons.logout), SizedBox(width:8), Text('Sair')])),
        ],
      );
    });
    if (choice != null) _handleMenuAction(choice);
  }

  Future<void> _showAdvancedOptionsDialog() async {
    final choice = await showDialog<String>(context: context, builder: (ctx) {
      return SimpleDialog(
        title: const Text('Opções Avançadas'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: Row(children: const [Icon(Icons.delete_forever, color: Colors.red), SizedBox(width:8), Text('Excluir Conta (Irreversível)', style: TextStyle(color: Colors.red))]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Row(children: const [Icon(Icons.close), SizedBox(width:8), Text('Fechar')]),
          ),
        ],
      );
    });
    if (choice == 'delete') {
      await _confirmAndDeleteAccount();
    }
  }

  Future<void> _confirmAndDeleteAccount() async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) {
      bool checked = false;
      return StatefulBuilder(builder: (ctx2, setS) {
        return AlertDialog(
          title: const Text('Excluir Conta - Irreversível'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Esta ação excluirá o usuário do Firebase Auth e marcará o perfil como excluído no Firestore. É IRRECUPERÁVEL.'),
            const SizedBox(height: 12),
            Row(children: [
              Checkbox(value: checked, onChanged: (v) => setS(() => checked = v ?? false)),
              const Expanded(child: Text('Estou ciente e desejo excluir permanentemente esta conta')),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx2, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: checked ? () => Navigator.pop(ctx2, true) : null,
              child: const Text('Excluir'),
            ),
          ],
        );
      });
    });
    if (confirmed == true) {
      // perform deletion
      showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator()));
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) throw 'Usuário não autenticado';
        final idToken = await user.getIdToken(true);
        final url = Uri.parse('https://us-central1-wismart-118c3.cloudfunctions.net/deleteUserAccount');
        final resp = await http.post(url, headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'}, body: jsonEncode({'confirm': true}));
        Navigator.pop(context); // remove progress
        if (resp.statusCode == 200) {
          try {
            await GoogleSignIn().signOut();
            await GoogleSignIn().disconnect();
          } catch (_) {}
          await SessionService.logout();
          await FirebaseAuth.instance.signOut();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conta excluída com sucesso. Limpe o cache do app/telefone para evitar reentrar.')));
            Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (r) => false);
          }
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao excluir conta: ${resp.statusCode} ${resp.body}')));
        }
      } catch (e) {
        Navigator.pop(context);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir conta: $e')));
      }
    }
  }

  // ============================================================================
  // MOBILE LAYOUT
  // ============================================================================

  Widget _buildMobileLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      drawer: _buildMobileDrawer(),
      appBar: AppBar(
        backgroundColor: AppColors.primaryPurple,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _getScreenTitle(_selectedIndex),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            offset: const Offset(0, 50),
            color: Colors.white,
            surfaceTintColor: Colors.white,
            onSelected: _handleMenuAction,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text(
                        shopName,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white,
                    backgroundImage: shopLogoUrl != null ? CachedNetworkImageProvider(shopLogoUrl!) : (userPhotoUrl != null ? CachedNetworkImageProvider(userPhotoUrl!) : null),
                    child: (shopLogoUrl == null && userPhotoUrl == null) ? const Icon(Icons.store, color: AppColors.primaryPurple) : null,
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                ],
              ),
            ),
            itemBuilder: (context) => [
              _buildPopupItem('perfil', Icons.store, "Perfil da Loja"),
              _buildPopupItem('advanced', Icons.security, "Opções Avançadas"),
              const PopupMenuDivider(),
              _buildPopupItem('sair', Icons.logout, "Sair", isRed: true),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _buildScreens(isDesktop: false),
      ),
      bottomNavigationBar: _buildMobileBottomNav(),
    );
  }

  Widget _buildMobileBottomNav() {
    final mainItems = [0, 1, 2, 3];
    int currentBottomIndex = mainItems.contains(_selectedIndex)
        ? mainItems.indexOf(_selectedIndex)
        : 0;

    return BottomNavigationBar(
      currentIndex: currentBottomIndex,
      onTap: (index) {
        setState(() {
          _selectedIndex = mainItems[index];
        });
      },
      selectedItemColor: AppColors.primaryPurple,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      selectedFontSize: 11,
      unselectedFontSize: 10,
      elevation: 8,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard, size: 24),
          label: "Painel",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.event, size: 24),
          label: "Agenda",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.design_services, size: 24),
          label: "Serviços",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.people, size: 24),
          label: "Clientes",
        ),
      ],
    );
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryPurple,
                  Color(0xFF7C3AED),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            currentAccountPicture: GestureDetector(
              onTap: _showBusinessTopMenu,
              child: CircleAvatar(
                backgroundColor: Colors.white,
                backgroundImage: shopLogoUrl != null ? CachedNetworkImageProvider(shopLogoUrl!) : null,
                child: shopLogoUrl == null ? const Icon(Icons.store, color: AppColors.primaryPurple) : null,
              ),
            ),
            accountName: Text(
              shopName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            accountEmail: Text(
              userName,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  icon: Icons.account_balance_wallet,
                  title: "Financeiro",
                  index: 4,
                ),
                _buildDrawerItem(
                  icon: Icons.people,
                  title: "Equipe",
                  index: 5,
                ),
                _buildDrawerItem(
                  icon: Icons.inventory_2_outlined,
                  title: "Estoque",
                  index: 7,
                ),
                ListTile(
                  leading: const Icon(Icons.security),
                  title: const Text("Opções Avançadas"),
                  onTap: () {
                    Navigator.pop(context);
                    _showAdvancedOptionsDialog();
                  },
                ),
                _buildDrawerItem(
                  icon: Icons.settings,
                  title: "Configurações",
                  index: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required int index,
  }) {
    bool isSelected = _selectedIndex == index;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primaryPurple.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? AppColors.primaryPurple : Colors.grey[700],
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? AppColors.primaryPurple : Colors.grey[800],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        onTap: () {
          Navigator.pop(context);
          setState(() => _selectedIndex = index);
        },
      ),
    );
  }

  // ============================================================================
  // DASHBOARD - OTIMIZADO E COM MONITOR DE CUSTO
  // ============================================================================

  Widget _buildHomeDashboard({required bool isDesktop}) {
    // 1. Definição do Intervalo de Tempo para Leitura (Range)
    // Se selecionado "Todos" (-1), pegamos um range amplo, mas idealmente você limitaria.
    // Aqui vamos focar na otimização do ano selecionado.
    
    DateTime startData;
    DateTime endData;

    if (_selectedYear == -1) {
      // CUIDADO: Ler tudo pode ser caro. 
      // Em produção, recomendo limitar aos últimos 2 anos.
      startData = DateTime(2023, 1, 1);
      endData = DateTime(2030, 12, 31);
    } else {
      startData = DateTime(_selectedYear, 1, 1);
      endData = DateTime(_selectedYear, 12, 31, 23, 59, 59);
    }

    return StreamBuilder<QuerySnapshot>(
      // 🔥 QUERY BLINDADA: Filtra por Shop + Intervalo de Data
      // Isso exige um Índice Composto no Firebase (ShopId + Data Asc/Desc)
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('shopId', isEqualTo: shopId)
          .where('data_agendamento', isGreaterThanOrEqualTo: startData)
          .where('data_agendamento', isLessThanOrEqualTo: endData)
          .snapshots(), // Ordenação pode ser feita em memória para economizar índice ou no .orderBy
      builder: (context, snapshot) {
        if (snapshot.hasError) {
           return Center(child: Text("Erro (Verifique índices no Console): ${snapshot.error}"));
        }

        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppColors.primaryPurple,
            ),
          );
        }

        final docs = snapshot.data!.docs;

        // (monitoring removed to silence linter; keep snapshot processing)
        // Metadata diz a origem
        if (snapshot.data!.metadata.isFromCache) {
           debugPrint("💰 [ECONOMIA] Lendo ${docs.length} agendamentos do CACHE Local.");
        } else {
           debugPrint("💸 [CUSTO] Baixando ${docs.length} documentos do SERVIDOR ($shopId).");
        }

        // --- LÓGICA DE CÁLCULO (Mantida, mas operando sobre o subset filtrado) ---
        
        bool isAllYears = _selectedYear == -1;
        double faturamentoTotal = 0;
        int totalAtendimentos = 0;
        double faturamentoMaoDeObra = 0;
        double faturamentoProdutos = 0;

        List<double> dataMoney = [];
        List<double> dataQty = [];
        List<String> chartLabels = [];

        // Inicializa estrutura de dados
        chartLabels = [
          'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
          'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
        ];
        dataMoney = List.filled(12, 0.0);
        dataQty = List.filled(12, 0.0);

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['data_agendamento'] is! Timestamp) continue;
          
          DateTime date = (data['data_agendamento'] as Timestamp).toDate();
          
          // Filtra status concluído
          if ((data['status'] ?? 'agendado') == 'concluido') {
            double total = double.tryParse(
                    data['valor_total']?.toString() ??
                        data['valor']?.toString() ??
                        '0') ??
                0.0;
            double maoObra = double.tryParse(
                    data['valor_mao_de_obra']?.toString() ?? '0') ??
                0.0;
            double produtos =
                double.tryParse(data['valor_produtos']?.toString() ?? '0') ??
                    0.0;
            
            if (maoObra == 0 && produtos == 0) maoObra = total;

            // Se for visualização mensal (ano selecionado)
            if (!isAllYears) {
               dataMoney[date.month - 1] += total;
               dataQty[date.month - 1] += 1;
            }

            faturamentoTotal += total;
            faturamentoMaoDeObra += maoObra;
            faturamentoProdutos += produtos;
            totalAtendimentos++;
          }
        }

        // Se for "Todos os anos", ajustamos o gráfico para ser por Ano, não por Mês
        if (isAllYears) {
           // Lógica simplificada para multiplos anos (recalculando baseada nos docs recebidos)
           Map<int, double> yearMoney = {};
           Map<int, double> yearQty = {};
           for (var doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              DateTime date = (data['data_agendamento'] as Timestamp).toDate();
               if ((data['status'] ?? 'agendado') == 'concluido') {
                 double total = double.tryParse(data['valor_total']?.toString() ?? '0') ?? 0;
                 yearMoney[date.year] = (yearMoney[date.year] ?? 0) + total;
                 yearQty[date.year] = (yearQty[date.year] ?? 0) + 1;
               }
           }
           chartLabels = yearMoney.keys.map((e) => e.toString()).toList();
           chartLabels.sort();
           dataMoney = chartLabels.map((key) => yearMoney[int.parse(key)]!).toList();
           dataQty = chartLabels.map((key) => yearQty[int.parse(key)]!).toList();
        }


        double ticketMedio =
            totalAtendimentos > 0 ? faturamentoTotal / totalAtendimentos : 0;

        if (isDesktop) {
          return _buildDesktopDashboard(
            isAllYears: isAllYears,
            faturamentoTotal: faturamentoTotal,
            totalAtendimentos: totalAtendimentos,
            ticketMedio: ticketMedio,
            dataMoney: dataMoney,
            dataQty: dataQty,
            chartLabels: chartLabels,
            faturamentoMaoDeObra: faturamentoMaoDeObra,
            faturamentoProdutos: faturamentoProdutos,
            appointmentDocs: docs,
          );
        } else {
          return _buildMobileDashboard(
            isAllYears: isAllYears,
            faturamentoTotal: faturamentoTotal,
            totalAtendimentos: totalAtendimentos,
            ticketMedio: ticketMedio,
            dataMoney: dataMoney,
            dataQty: dataQty,
            chartLabels: chartLabels,
            faturamentoMaoDeObra: faturamentoMaoDeObra,
            faturamentoProdutos: faturamentoProdutos,
            appointmentDocs: docs,
          );
        }
      },
    );
  }

  // ... (RESTANTE DOS WIDGETS DE UI - _buildDesktopDashboard, _buildMobileDashboard, ETC. PERMANECEM IGUAIS PARA NÃO QUEBRAR O DESIGN)
  
  Widget _buildDesktopDashboard({
    required bool isAllYears,
    required double faturamentoTotal,
    required int totalAtendimentos,
    required double ticketMedio,
    required List<double> dataMoney,
    required List<double> dataQty,
    required List<String> chartLabels,
    required double faturamentoMaoDeObra,
    required double faturamentoProdutos,
    List<QueryDocumentSnapshot>? appointmentDocs,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAllYears
                      ? "Desempenho Geral"
                      : "Resultados de $_selectedYear",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  "Análise combinada de Faturamento e Atendimentos",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
            _buildYearDropdown(),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                "Faturamento",
                faturamentoTotal,
                Icons.monetization_on,
                Colors.green,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                "Atendimentos",
                totalAtendimentos.toDouble(),
                Icons.people_alt,
                Colors.blue,
                isMoney: false,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                "Ticket Médio",
                ticketMedio,
                Icons.receipt_long,
                AppColors.primaryPurple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 7,
                child: _buildDualChart(
                  dataMoney,
                  dataQty,
                  chartLabels,
                  isAllYears,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: _buildBreakdownCard(
                  faturamentoMaoDeObra,
                  faturamentoProdutos,
                  faturamentoTotal,
                ),
              ),
            ],
          ),
        ),
        if (shopId != null && appointmentDocs != null && appointmentDocs.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildEquipeComissoesCard(shopId!, appointmentDocs),
        ],
      ],
    );
  }

  Widget _buildEquipeComissoesCard(String shopId, List<QueryDocumentSnapshot> appointmentDocs) {
    final concluidos = appointmentDocs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return (data['status'] ?? '') == 'confirmado' || (data['status'] ?? '') == 'concluido';
    }).toList();
    Map<String, double> producaoPorProf = {};
    for (var d in concluidos) {
      final data = d.data() as Map<String, dynamic>;
      final pid = data['profissionalId']?.toString() ?? '';
      if (pid.isEmpty) continue;
      final valor = double.tryParse(data['valor_pago']?.toString() ?? data['valor_total']?.toString() ?? '0') ?? 0;
      producaoPorProf[pid] = (producaoPorProf[pid] ?? 0) + valor;
    }
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance.collection('employees').where('shopId', isEqualTo: shopId).get(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox.shrink();
        final employees = snap.data!.docs;
        double totalComissao = 0;
        final rows = <Widget>[];
        for (var emp in employees) {
          final ed = emp.data() as Map<String, dynamic>?;
          final nome = ed?['nome']?.toString() ?? 'Sem nome';
          final p = ed?['comissao_percent'];
          final percent = (p is num) ? p.toDouble() : 0.0;
          final produzido = producaoPorProf[emp.id] ?? 0.0;
          final aReceber = percent > 0 ? (produzido * percent / 100) : 0.0;
          totalComissao += aReceber;
          rows.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(nome, style: const TextStyle(fontWeight: FontWeight.w500))),
                Text(NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(produzido), style: const TextStyle(fontSize: 12)),
                Text(NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(aReceber), style: TextStyle(fontSize: 12, color: AppColors.primaryPurple, fontWeight: FontWeight.bold)),
              ],
            ),
          ));
        }
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Equipe - Produção e a receber', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Profissional', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const Text('Produzido', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text('A receber', style: TextStyle(fontSize: 11, color: AppColors.primaryPurple)),
                  ],
                ),
                ...rows,
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('Total comissões: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(totalComissao)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileDashboard({
    required bool isAllYears,
    required double faturamentoTotal,
    required int totalAtendimentos,
    required double ticketMedio,
    required List<double> dataMoney,
    required List<double> dataQty,
    required List<String> chartLabels,
    required double faturamentoMaoDeObra,
    required double faturamentoProdutos,
    List<QueryDocumentSnapshot>? appointmentDocs,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAllYears ? "Geral" : "$_selectedYear",
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      "Análise de Performance",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _buildYearDropdown(),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildMobileMetricCard(
                  "Faturamento",
                  faturamentoTotal,
                  Icons.monetization_on,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMobileMetricCard(
                  "Atendimentos",
                  totalAtendimentos.toDouble(),
                  Icons.people_alt,
                  Colors.blue,
                  isMoney: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildMobileMetricCard(
            "Ticket Médio",
            ticketMedio,
            Icons.receipt_long,
            AppColors.primaryPurple,
          ),
          const SizedBox(height: 20),
          _buildMobileChart(dataMoney, dataQty, chartLabels, isAllYears),
          const SizedBox(height: 20),
          _buildMobileBreakdown(
            faturamentoMaoDeObra,
            faturamentoProdutos,
            faturamentoTotal,
          ),
          if (shopId != null && appointmentDocs != null && appointmentDocs.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildEquipeComissoesCard(shopId!, appointmentDocs),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileMetricCard(
    String title,
    double value,
    IconData icon,
    Color color, {
    bool isMoney = true,
  }) {
    String textVal = isMoney
        ? NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value)
        : value.toInt().toString();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 24),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(Icons.trending_up, color: color, size: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            textVal,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileChart(
    List<double> moneyData,
    List<double> qtyData,
    List<String> labels,
    bool isAllYears,
  ) {
    double maxMoney = moneyData.fold(0, max);
    if (maxMoney == 0) maxMoney = 1;
    double maxQty = qtyData.fold(0, max);
    if (maxQty == 0) maxQty = 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Performance",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _legendItem("Faturamento", AppColors.primaryPurple),
              const SizedBox(width: 16),
              _legendItem("Atendimentos", AppColors.gold),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: labels.length * 55.0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(labels.length, (index) {
                    double moneyH = (moneyData[index] / maxMoney) * 150;
                    double qtyH = (qtyData[index] / maxQty) * 150;

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              width: 22,
                              height: moneyH.clamp(2.0, 150),
                              decoration: const BoxDecoration(
                                color: AppColors.primaryPurple,
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Container(
                              width: 22,
                              height: qtyH.clamp(2.0, 150),
                              decoration: const BoxDecoration(
                                color: AppColors.gold,
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          labels[index],
                          style: const TextStyle(
                            fontSize: 9,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBreakdown(
    double servico,
    double produto,
    double total,
  ) {
    double pctS = total > 0 ? servico / total : 0;
    double pctP = total > 0 ? produto / total : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Composição da Receita",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 16,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[100],
            ),
            child: Row(
              children: [
                if (pctS > 0)
                  Expanded(
                    flex: (pctS * 100).toInt().clamp(1, 100),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.primaryPurple,
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(8),
                        ),
                      ),
                    ),
                  ),
                if (pctP > 0)
                  Expanded(
                    flex: (pctP * 100).toInt().clamp(1, 100),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(8),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildLegendItemBreakdown("Serviços", pctS, AppColors.primaryPurple),
          const SizedBox(height: 8),
          _buildLegendItemBreakdown("Produtos", pctP, AppColors.gold),
        ],
      ),
    );
  }

  Widget _buildYearDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primaryPurple.withValues(alpha: 0.3),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _availableYears.contains(_selectedYear) || _selectedYear == -1
              ? _selectedYear
              : -1,
          icon: const Icon(Icons.filter_list, color: AppColors.primaryPurple, size: 18),
          isDense: true,
          items: [
            const DropdownMenuItem<int>(
              value: -1,
              child: Text(
                "Todos",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryPurple,
                  fontSize: 13,
                ),
              ),
            ),
            ..._availableYears
                .map(
                  (int year) => DropdownMenuItem<int>(
                    value: year,
                    child: Text(
                      year.toString(),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                )
                
          ],
          onChanged: (int? newValue) {
            if (newValue != null) {
              setState(() => _selectedYear = newValue);
            }
          },
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    double value,
    IconData icon,
    Color color, {
    bool isMoney = true,
  }) {
    String textVal = isMoney
        ? NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value)
        : value.toInt().toString();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    textVal,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDualChart(
    List<double> moneyData,
    List<double> qtyData,
    List<String> labels,
    bool isAllYears,
  ) {
    double maxMoney = moneyData.fold(0, max);
    if (maxMoney == 0) maxMoney = 1;
    double maxQty = qtyData.fold(0, max);
    if (maxQty == 0) maxQty = 1;
    double barWidth = isAllYears ? 35.0 : 20.0;

    String formatVal(double v) =>
        v >= 1000 ? "${(v / 1000).toStringAsFixed(1)}k" : v.toInt().toString();

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                "Evolução de Performance",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              _legendItem("Faturamento", AppColors.primaryPurple),
              const SizedBox(width: 12),
              _legendItem("Atendimentos", AppColors.gold),
            ],
          ),
          const SizedBox(height: 30),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                double chartHeight = constraints.maxHeight;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(labels.length, (index) {
                    double moneyH =
                        (moneyData[index] / maxMoney) * (chartHeight * 0.75);
                    double qtyH =
                        (qtyData[index] / maxQty) * (chartHeight * 0.75);

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (moneyData[index] > 0)
                                  Text(
                                    formatVal(moneyData[index]),
                                    style: const TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryPurple,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Container(
                                  width: barWidth,
                                  height: moneyH.clamp(2.0, chartHeight),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primaryPurple,
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 2),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (qtyData[index] > 0)
                                  Text(
                                    qtyData[index].toInt().toString(),
                                    style: const TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.gold,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Container(
                                  width: barWidth,
                                  height: qtyH.clamp(2.0, chartHeight),
                                  decoration: const BoxDecoration(
                                    color: AppColors.gold,
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(4),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          labels[index],
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownCard(
    double servico,
    double produto,
    double total,
  ) {
    double pctS = total > 0 ? servico / total : 0;
    double pctP = total > 0 ? produto / total : 0;

    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Receita",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Container(
            height: 20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.grey[100],
            ),
            child: Row(
              children: [
                if (pctS > 0)
                  Expanded(
                    flex: (pctS * 100).toInt().clamp(1, 100),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.primaryPurple,
                        borderRadius: BorderRadius.horizontal(
                          left: Radius.circular(10),
                        ),
                      ),
                    ),
                  ),
                if (pctP > 0)
                  Expanded(
                    flex: (pctP * 100).toInt().clamp(1, 100),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.horizontal(
                          right: Radius.circular(10),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildLegendItemBreakdown("Serviços", pctS, AppColors.primaryPurple),
          const Divider(),
          _buildLegendItemBreakdown("Produtos", pctP, AppColors.gold),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildLegendItemBreakdown(String label, double pct, Color color) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12)),
        const Spacer(),
        Text(
          "${(pct * 100).toStringAsFixed(1)}%",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  String _getScreenTitle(int index) {
    switch (index) {
      case 0:
        return "Painel Geral";
      case 1:
        return "Agenda";
      case 2:
        return "Serviços";
      case 3:
        return "Clientes";
      case 4:
        return "Financeiro";
      case 5:
        return "Equipe";
      case 6:
        return "Configurações";
      case 7:
        return "Estoque";
      default:
        return "";
    }
  }
}