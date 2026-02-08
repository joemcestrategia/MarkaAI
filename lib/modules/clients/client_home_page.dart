// ignore_for_file: unused_element, unused_field, unused_local_variable
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/services/profile_check_service.dart';
import '../business/business_onboarding_page.dart';
import '../login/login_page.dart';
import '../schedule/booking_page.dart';
import 'client_register_page.dart';
import 'appointment_confirmation_page.dart';
import 'shop_profile_page.dart';
import 'my_appointments_page.dart';
import 'client_service_detail_page.dart';

class ClientHomePage extends StatefulWidget {
  const ClientHomePage({super.key});

  @override
  State<ClientHomePage> createState() => _ClientHomePageState();
}

class _ClientHomePageState extends State<ClientHomePage> {
  final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  int _selectedIndex = 0; 
  String _userName = "Cliente";
  String _userEmail = "";
  String? _userPhotoUrl;
  String? _userId;
  String _userTipo = 'cliente';
  bool _isLoadingUserData = true;

  // Filtros
  String _searchText = "";
  String _selectedCategory = "Todos";
  
  final List<Map<String, dynamic>> _categories = [
    {"name": "Todos", "icon": Icons.grid_view},
    {"name": "Beleza", "icon": Icons.face},
    {"name": "Barbearia", "icon": Icons.content_cut},
    {"name": "Estética", "icon": Icons.spa},
    {"name": "Saúde", "icon": Icons.medical_services},
    {"name": "Bem-estar", "icon": Icons.self_improvement},
    {"name": "Manicure", "icon": Icons.brush},
    {"name": "Personal", "icon": Icons.fitness_center},
    {"name": "Massagem", "icon": Icons.accessibility_new},
    {"name": "Nutrição", "icon": Icons.restaurant_menu},
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _setupNotifications();
  }

  void _setupNotifications() {
    // Notificações quando app está em foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final appointmentId = message.data['appointmentId'];
      final type = message.data['type'];
      if (appointmentId != null && type == 'confirmacao' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primaryPurple,
            content: Text(message.notification?.body ?? 'Confirme seu agendamento'),
            action: SnackBarAction(
              label: 'VER',
              textColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AppointmentConfirmationPage(appointmentId: appointmentId),
                  ),
                );
              },
            ),
          ),
        );
      }
    });
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted) {
        setState(() {
          _userId = user.uid;
          _userName = doc.data()?['nome'] ?? user.displayName ?? "Cliente";
          _userEmail = user.email ?? "";
          _userPhotoUrl = user.photoURL;
          _userTipo = doc.data()?['tipo'] ?? doc.data()?['role'] ?? 'cliente';
          _isLoadingUserData = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoadingUserData = false);
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              Navigator.pop(context);
              _handleLogout();
            },
            child: const Text("Sair", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showAdvancedOptionsDialog() async {
    final choice = await showDialog<String>(context: context, builder: (ctx) {
      return SimpleDialog(
        title: const Text('Opções Avançadas'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'trocar'),
            child: Row(children: const [Icon(Icons.swap_horiz), SizedBox(width:8), Text('Trocar Tipo de Conta')]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: Row(children: const [Icon(Icons.delete_forever, color: Colors.red), SizedBox(width:8), Text('Excluir Conta (Irreversível)', style: TextStyle(color: Colors.red))]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'close'),
            child: Row(children: const [Icon(Icons.close), SizedBox(width:8), Text('Fechar')]),
          ),
        ],
      );
    });
    if (choice == 'delete') {
      await _deleteAccount();
    } else if (choice == 'trocar') {
      if (_userTipo == 'dono' || _userTipo == 'business') {
        _switchToClient();
      } else {
        _switchToOwner();
      }
    }
  }

  Future<void> _switchToClient() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Confirmar troca'),
      content: const Text('Deseja mudar sua conta para Cliente? Isso removerá associações de loja.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context,false), child: const Text('Cancelar')),
        ElevatedButton(onPressed: () => Navigator.pop(context,true), child: const Text('Confirmar')),
      ],
    ));
    if (ok != true) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'tipo': 'cliente', 'role': 'cliente', 'shopId': FieldValue.delete()});
    await SessionService.saveLogin(userId: user.uid, userType: 'client');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conta alterada para Cliente')));
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const ClientHomePage()), (r)=>false);
    }
  }

  void _switchToOwner() {
    showDialog<String>(context: context, builder: (ctx) {
      return AlertDialog(
        title: const Text('Tornar-se Dono'),
        content: const Text(
          'Recomendamos excluir a conta atual e criar uma nova conta de Dono para evitar inconsistências no sistema. '
          'Se preferir manter a conta atual, ainda é possível cadastrar a loja, mas pode causar conflitos. O que deseja fazer?'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'keep'), child: const Text('Continuar sem excluir')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Excluir e continuar')),
        ],
      );
    }).then((choice) {
      if (choice == 'keep') {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const BusinessOnboardingPage()));
      } else if (choice == 'delete') {
        // deleteAccount will sign the user out after deletion; user must register anew.
        _deleteAccount();
      }
      // cancel -> do nothing
    });
  }

  // Profile bottom sheet removed (menu moved to top-right popup)

  // Top menu helper removed (menu handled via PopupMenuButton on the AppBar)

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) {
      bool checked = false;
      return StatefulBuilder(builder: (ctx2, setS) {
        return AlertDialog(
          title: const Text('Excluir Conta - Irreversível'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Esta ação removerá TODOS os dados ligados a esta conta (agendamentos, perfil, etc.) e é IRRECUPERÁVEL. Após a exclusão, limpe o cache do telefone para evitar reentrar com dados antigos.'),
            const SizedBox(height: 12),
            Row(children: [
              Checkbox(value: checked, onChanged: (v) => setS(() => checked = v ?? false)),
              const Expanded(child: Text('Estou ciente e desejo excluir permanentemente esta conta')),
            ])
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: checked ? () => Navigator.pop(ctx, true) : null,
              child: const Text('Excluir'),
            ),
          ],
        );
      });
    });
    if (confirmed != true) return;

    showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator()));
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken(true);
      if (idToken == null) {
        Navigator.pop(context);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro: usuário não autenticado')));
        return;
      }
      final url = Uri.parse('https://us-central1-wismart-118c3.cloudfunctions.net/deleteUserAccount');
      final resp = await http.post(url, headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $idToken'}, body: jsonEncode({'confirm': true}));
      Navigator.pop(context);
      if (resp.statusCode == 200) {
        // success
        try {
          await GoogleSignIn().signOut();
          await GoogleSignIn().disconnect();
        } catch (_) {}
        await SessionService.logout();
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Conta excluída com sucesso. Limpe o cache do app/telefone manualmente.')));
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (r) => false);
        }
      } else {
        final body = resp.body;
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Falha ao excluir conta: ${resp.statusCode} $body')));
      }
    } catch (e) {
      Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir conta: $e')));
    }
  }

  Future<void> _handleLogout() async {
    try {
      await GoogleSignIn().signOut();
      await GoogleSignIn().disconnect();
    } catch (_) {}
    await SessionService.logout();
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context, 
        MaterialPageRoute(builder: (context) => const LoginPage()), 
        (route) => false
      );
    }
  }

  void _openShopProfile(DocumentSnapshot shop) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShopProfilePage(
          shopDoc: shop,
          onBookService: (serviceId, serviceData) {
             // 🔥 Navega para a página de detalhes do serviço PRIMEIRO
             _openServiceDetails(serviceId: serviceId, serviceData: serviceData);
          },
        ),
      ),
    );
  }
  
  // 🆕 Abre a página de detalhes do serviço com carrossel
  void _openServiceDetails({required String serviceId, required Map<String, dynamic> serviceData}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClientServiceDetailPage(
          serviceId: serviceId,
          serviceData: serviceData,
        ),
      ),
    );
  }

  Future<void> _openBookingPage({
    required DocumentSnapshot shop,
    required String serviceId,
    required Map<String, dynamic> serviceData,
  }) async {
    final uid = _userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final complete = await ProfileCheckService.isClientProfileComplete(uid);
    if (!complete && mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Perfil incompleto'),
          content: const Text(
            'Seu perfil ainda não foi todo preenchido. Para agendar, complete seus dados (nome, telefone, endereço). Deseja completar agora?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Depois')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Completar')),
          ],
        ),
      );
      if (go == true && mounted) {
        final user = FirebaseAuth.instance.currentUser;
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => ClientRegisterPage(user: user, isBusinessAdding: false),
        ));
      }
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BookingPage(
          shop: shop,
          serviceId: serviceId,
          serviceData: serviceData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUserData) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primaryPurple)));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        bool isDesktop = constraints.maxWidth > 900;
        
        if (isDesktop) {
          return Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
            body: Row(
              children: [
                _buildSideMenuDesktop(),
                Expanded(
                  child: Column(
                    children: [
                      _buildHeaderDesktop(),
                      Expanded(
                        child: _selectedIndex == 0 
                          ? _buildExploreView(isDesktop: true) 
                          : _buildScheduleView(isDesktop: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          body: _selectedIndex == 0 
              ? _buildExploreView(isDesktop: false)
              : _buildScheduleView(isDesktop: false),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
            backgroundColor: Colors.white,
            elevation: 10,
            shadowColor: Colors.black12,
            indicatorColor: AppColors.primaryPurple.withValues(alpha: 0.2),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: "Explorar"),
              NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today), label: "Agendamentos"),
            ],
          ),
        );
      },
    );
  }

  // ============ VIEW: EXPLORAR ============
  Widget _buildExploreView({required bool isDesktop}) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        if (!isDesktop)
          SliverAppBar(
            backgroundColor: const Color(0xFFF5F7FA),
            elevation: 0,
            floating: true,
            toolbarHeight: 70,
            title: Row(
              children: [
                // logo no canto esquerdo em vez do texto de saudação
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Image.asset('assets/images/logo_purple.png', height: 48, fit: BoxFit.contain),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
            PopupMenuButton<String>(
              offset: const Offset(0, 50),
              color: Colors.white,
              surfaceTintColor: Colors.white,
              onSelected: (v) {
                if (v == 'perfil') {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user != null) {
                    Navigator.push(context, MaterialPageRoute(builder: (c) => ClientRegisterPage(user: user, isBusinessAdding: false)));
                  }
                } else if (v == 'advanced') {
                  _showAdvancedOptionsDialog();
                } else if (v == 'sair') {
                  _confirmLogout();
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _userName,
                          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const Text(
                          "MarkaAI",
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white,
                      backgroundImage: _userPhotoUrl != null ? CachedNetworkImageProvider(_userPhotoUrl!) : null,
                      child: (_userPhotoUrl == null) ? const Icon(Icons.person, color: AppColors.primaryPurple, size: 20) : null,
                    ),
                    const SizedBox(width: 5),
                    const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey),
                  ],
                ),
              ),
              itemBuilder: (ctx) => [
                PopupMenuItem(value: 'perfil', child: Row(children: const [Icon(Icons.person, size: 16), SizedBox(width:8), Text('Perfil')])),
                PopupMenuItem(value: 'advanced', child: Row(children: const [Icon(Icons.security, size: 16), SizedBox(width:8), Text('Opções Avançadas')])),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'sair', child: Row(children: const [Icon(Icons.logout, color: Colors.red, size: 16), SizedBox(width:8), Text('Sair', style: TextStyle(color: Colors.red))])),
              ],
            ),
            ],
          ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 15),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: TextField(
                onChanged: (v) => setState(() => _searchText = v),
                decoration: const InputDecoration(
                  hintText: "O que você procura hoje?",
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
              ),
            ),
          ),
        ),

        // Banner Promocional
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6B46C1), Color(0xFF9333EA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryPurple.withValues(alpha: 0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -20,
                    bottom: -20,
                    child: Icon(
                      Icons.auto_awesome,
                      size: 150,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text(
                          'Encontre Profissionais',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Agende serviços de beleza, saúde,\nbem-estar e muito mais!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Categorias
        SliverToBoxAdapter(
          child: SizedBox(
            height: 45,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                final isSelected = _selectedCategory == cat['name'];
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: FilterChip(
                    label: Text(cat['name']),
                    avatar: isSelected ? null : Icon(cat['icon'], size: 16, color: Colors.grey[600]),
                    selected: isSelected,
                    onSelected: (b) => setState(() => _selectedCategory = cat['name']),
                    backgroundColor: Colors.white,
                    selectedColor: AppColors.primaryPurple,
                    labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isSelected ? Colors.transparent : Colors.grey.shade300)),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              },
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 25)),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: Text(
              _searchText.isEmpty ? "Recomendados para você" : "Resultados da busca",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 15)),

        // GRID DE LOJAS
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('shops').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
            
            final filtered = snapshot.data!.docs.where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              
              // 🔥 CORREÇÃO: Lojas sem o campo 'ativo' são consideradas ATIVAS
              final bool isActive = d['ativo'] ?? true; 
              
              final matchesText = (d['nome'] ?? "").toString().toLowerCase().contains(_searchText.toLowerCase());
              final matchesCat = _selectedCategory == "Todos" || (d['categoria'] ?? "").toString().contains(_selectedCategory);
              
              return matchesText && matchesCat && isActive;
            }).toList();

            if (filtered.isEmpty) {
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 50),
                  child: Center(child: Text("Nenhuma loja encontrada.", style: TextStyle(color: Colors.grey))),
                ),
              );
            }

            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: isDesktop ? 300 : 400, 
                  childAspectRatio: isDesktop ? 0.85 : 1.3, 
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _ShopCard(shop: filtered[index], onTap: () => _openShopProfile(filtered[index])),
                  childCount: filtered.length,
                ),
              ),
            );
          },
        ),
        
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  // ============ VIEW: AGENDA ============
  Widget _buildScheduleView({required bool isDesktop}) {
    return const MyAppointmentsPage();
  }

  // --- DESKTOP WIDGETS ---
  Widget _buildSideMenuDesktop() {
    return Container(
      width: 250,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.primaryPurple, size: 30),
                SizedBox(width: 10),
                Text("MarkaAI", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 40),
          _menuItemDesktop(0, Icons.explore, "Explorar"),
          _menuItemDesktop(1, Icons.calendar_month, "Minha Agenda"),
          _menuItemDesktop(2, Icons.favorite_border, "Favoritos"),
          const Spacer(),
          const Divider(),
        ],
      ),
    );
  }

  Widget _menuItemDesktop(int idx, IconData icon, String lbl) {
    bool isSelected = _selectedIndex == idx;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primaryPurple.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? AppColors.primaryPurple : Colors.grey),
        title: Text(lbl, style: TextStyle(color: isSelected ? AppColors.primaryPurple : Colors.grey[800], fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
        onTap: () => setState(() => _selectedIndex = idx),
      ),
    );
  }

  Widget _buildHeaderDesktop() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_selectedIndex == 0 ? "Explorar" : "Minha Agenda", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                if (_selectedIndex == 0) const Text("Encontre os melhores serviços perto de você.", style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            offset: const Offset(0, 50),
            color: Colors.white,
            surfaceTintColor: Colors.white,
            onSelected: (v) {
              if (v == 'perfil') {
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  Navigator.push(context, MaterialPageRoute(builder: (c) => ClientRegisterPage(user: user, isBusinessAdding: false)));
                }
              } else if (v == 'trocar') {
                if (_userTipo == 'dono' || _userTipo == 'business') {
                  _switchToClient();
                } else {
                  _switchToOwner();
                }
              } else if (v == 'advanced') {
                _showAdvancedOptionsDialog();
              } else if (v == 'sair') {
                _confirmLogout();
              }
            },
            child: Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _userName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      "MarkaAI",
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: _userPhotoUrl != null ? CachedNetworkImageProvider(_userPhotoUrl!) : null,
                  child: (_userPhotoUrl == null) ? const Icon(Icons.person, size: 20) : null,
                ),
                const SizedBox(width: 5),
                const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey),
              ],
            ),
            itemBuilder: (context) => [
              PopupMenuItem(value: 'perfil', child: Row(children: const [Icon(Icons.person, size: 16), SizedBox(width:8), Text('Perfil')])),
              PopupMenuItem(value: 'trocar', child: Row(children: const [Icon(Icons.swap_horiz, size: 16), SizedBox(width:8), Text('Trocar Tipo')])),
              PopupMenuItem(value: 'advanced', child: Row(children: const [Icon(Icons.security, size: 16), SizedBox(width:8), Text('Opções Avançadas')])),
              const PopupMenuDivider(),
              PopupMenuItem(value: 'sair', child: Row(children: const [Icon(Icons.logout, color: Colors.red, size: 16), SizedBox(width:8), Text('Sair', style: TextStyle(color: Colors.red))])),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 🏰 COMPONENTES VISUAIS (DESIGN SYSTEM)
// =============================================================================

class _ShopCard extends StatelessWidget {
  final DocumentSnapshot shop;
  final VoidCallback onTap;

  const _ShopCard({required this.shop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data = shop.data() as Map<String, dynamic>;
    final imgUrl = data['coverUrl'] ?? data['imageUrl'] ?? "";
    final logoUrl = data['logoUrl'] ?? "";

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Hero(
                      tag: 'cover_${shop.id}',
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        child: imgUrl.isNotEmpty
                            ? CachedNetworkImage(imageUrl: imgUrl, fit: BoxFit.cover)
                            : Container(color: Colors.grey[200], child: const Icon(Icons.store, color: Colors.grey, size: 40)),
                      ),
                    ),
                  ),
                  if (logoUrl.isNotEmpty)
                    Positioned(
                      bottom: 10, left: 10,
                      child: Hero(
                        tag: 'logo_${shop.id}',
                        child: Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white, shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4)]
                          ),
                          child: ClipOval(child: CachedNetworkImage(imageUrl: logoUrl, fit: BoxFit.cover)),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 10, right: 10,
                    child: Builder(builder: (context) {
                      // Try to read rating from shop document fields
                      final rawRating = (data['rating'] ?? (data['google_business'] is Map ? data['google_business']['rating'] : null));
                      String ratingText = '';
                      if (rawRating != null) {
                        try {
                          final r = double.tryParse(rawRating.toString()) ?? (rawRating is num ? rawRating.toDouble() : 0.0);
                          ratingText = r > 0 ? r.toStringAsFixed(1) : '';
                        } catch (_) {
                          ratingText = rawRating.toString();
                        }
                      }
                      if (ratingText.isEmpty) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [const Icon(Icons.star, size: 12, color: Colors.amber), const SizedBox(width: 4), Text(ratingText, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))],
                        ),
                      );
                    }),
                  )
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['nome'] ?? "Loja", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(data['categoria'] ?? "Serviços", style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                      ],
                    ),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 12, color: Colors.grey[400]),
                        const SizedBox(width: 4),
                        Expanded(child: Text(data['endereco'] ?? "Endereço não inf.", style: TextStyle(color: Colors.grey[500], fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 📖 PÁGINA RESTAURADA: DETALHES DO SERVIÇO
class ServiceDetailsPage extends StatefulWidget {
  final String serviceId;
  final Map<String, dynamic> serviceData;
  final VoidCallback onBookPressed;

  const ServiceDetailsPage({
    super.key,
    required this.serviceId,
    required this.serviceData,
    required this.onBookPressed,
  });

  @override
  State<ServiceDetailsPage> createState() => _ServiceDetailsPageState();
}

class _ServiceDetailsPageState extends State<ServiceDetailsPage> {
  final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  int _currentImageIndex = 0;

  @override
  Widget build(BuildContext context) {
    final sData = widget.serviceData;
    
    List<String> images = [];
    dynamic rawFotos = sData['fotos_urls'] ?? sData['fotos'] ?? sData['imageUrl'] ?? sData['imagens'];
    
    if (rawFotos is List) {
      images = rawFotos.map((e) => e.toString()).toList();
    } else if (rawFotos is String && rawFotos.isNotEmpty) {
      images = [rawFotos];
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 400,
                pinned: true,
                backgroundColor: AppColors.primaryPurple,
                leading: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      images.isNotEmpty
                          ? PageView.builder(
                              itemCount: images.length,
                              onPageChanged: (idx) => setState(() => _currentImageIndex = idx),
                              itemBuilder: (context, index) {
                                return CachedNetworkImage(
                                  imageUrl: images[index],
                                  fit: BoxFit.cover,
                                  placeholder: (c, u) => const Center(child: CircularProgressIndicator()),
                                  errorWidget: (c, u, e) => Container(color: Colors.grey[200], child: const Icon(Icons.broken_image, size: 50, color: Colors.grey)),
                                );
                              },
                            )
                          : Container(color: Colors.grey[200], child: const Center(child: Icon(Icons.spa, size: 80, color: Colors.grey))),
                      
                      if (images.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: images.asMap().entries.map((entry) {
                              return Container(
                                width: 8.0,
                                height: 8.0,
                                margin: const EdgeInsets.symmetric(horizontal: 4.0),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: _currentImageIndex == entry.key ? 0.9 : 0.4),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              sData['nome'] ?? "Serviço",
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, height: 1.2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                currencyFormat.format(sData['preco'] ?? 0),
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primaryPurple),
                              ),
                              Text(
                                "${sData['tempo_min'] ?? 30} min",
                                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 20),
                      const Text("Sobre o serviço", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Text(
                        sData['descricao'] ?? "Sem descrição disponível para este serviço.",
                        style: TextStyle(color: Colors.grey[700], fontSize: 16, height: 1.6),
                      ),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -5))
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: widget.onBookPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text(
                      "AGENDAR AGORA",
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}