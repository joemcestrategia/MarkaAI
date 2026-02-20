// ignore_for_file: unused_element, unused_field, unused_local_variable
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/services/profile_check_service.dart';
import '../login/login_page.dart';
import '../schedule/booking_page.dart';
import 'client_register_page.dart';
import 'appointment_confirmation_page.dart';
import 'shop_profile_page.dart';
import 'my_appointments_page.dart';
import 'client_service_detail_page.dart';
import 'address_selector_page.dart';
import 'client_search_page.dart';

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
  String _selectedLocation = "";
  String _searchText = "";
  String _selectedCategory = "Todos";
  double? _userLat;
  double? _userLng;
  double _selectedRadius = 20.0; // km

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

  // Helper para cores de categoria (Smart Fallback)
  Color _getCategoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'barbearia':
        return const Color(0xFFE3F2FD); // Azul claro
      case 'beleza':
      case 'estética':
        return const Color(0xFFFCE4EC); // Rosa claro
      case 'saúde':
        return const Color(0xFFE8F5E9); // Verde claro
      case 'bem-estar':
        return const Color(0xFFFFF3E0); // Laranja claro
      default:
        return Colors.grey[100]!;
    }
  }

  IconData _getCategoryIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'barbearia':
        return Icons.content_cut;
      case 'beleza':
      case 'estética':
        return Icons.face;
      case 'saúde':
        return Icons.medical_services;
      case 'bem-estar':
        return Icons.self_improvement;
      default:
        return Icons.store;
    }
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
            content:
                Text(message.notification?.body ?? 'Confirme seu agendamento'),
            action: SnackBarAction(
              label: 'VER',
              textColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AppointmentConfirmationPage(
                        appointmentId: appointmentId),
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
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (mounted) {
        final data = doc.data();
        setState(() {
          _userId = user.uid;
          _userName = data?['nome'] ?? user.displayName ?? "Cliente";
          _userEmail = user.email ?? "";
          _userPhotoUrl = user.photoURL;
          _userTipo = data?['tipo'] ?? data?['role'] ?? 'cliente';
          // Restaurar última localização salva
          final lastLoc = data?['last_location'] as Map<String, dynamic>?;
          if (lastLoc != null) {
            _selectedLocation = lastLoc['label'] ?? '';
            _userLat = lastLoc['lat'] != null
                ? (lastLoc['lat'] as num).toDouble()
                : null;
            _userLng = lastLoc['lng'] != null
                ? (lastLoc['lng'] as num).toDouble()
                : null;
          }
          _isLoadingUserData = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoadingUserData = false);
    }
  }

  void _showLocationPicker() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const AddressSelectorPage()),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedLocation = result['label'] ?? result['city'] ?? '';
        _userLat =
            result['lat'] != null ? (result['lat'] as num).toDouble() : null;
        _userLng =
            result['lng'] != null ? (result['lng'] as num).toDouble() : null;
      });
      // Persistir última localização no Firestore
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        FirebaseFirestore.instance.collection('users').doc(uid).set({
          'last_location': {
            'label': _selectedLocation,
            'address': result['address'],
            'city': result['city'],
            'lat': result['lat'],
            'lng': result['lng'],
          },
        }, SetOptions(merge: true));
      }
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
              child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
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

  void _handleProfileMenu(String value) {
    switch (value) {
      case 'edit':
        final user = FirebaseAuth.instance.currentUser;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ClientRegisterPage(
              user: user,
              isBusinessAdding: false,
            ),
          ),
        );
        break;
      case 'logout':
        _confirmLogout();
        break;
    }
  }

  void _navigateToSearch(String query) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientSearchPage(
          initialQuery: query,
          initialCity: _selectedLocation,
          userLat: _userLat,
          userLng: _userLng,
          initialRadius: _selectedRadius,
        ),
      ),
    );
  }

  // Profile bottom sheet removed (menu moved to top-right popup)

  // Top menu helper removed (menu handled via PopupMenuButton on the AppBar)

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          bool checked = false;
          return StatefulBuilder(builder: (ctx2, setS) {
            return AlertDialog(
              title: const Text('Excluir Conta - Irreversível'),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'Esta ação removerá TODOS os dados ligados a esta conta (agendamentos, perfil, etc.) e é IRRECUPERÁVEL. Após a exclusão, limpe o cache do telefone para evitar reentrar com dados antigos.'),
                const SizedBox(height: 12),
                Row(children: [
                  Checkbox(
                      value: checked,
                      onChanged: (v) => setS(() => checked = v ?? false)),
                  const Expanded(
                      child: Text(
                          'Estou ciente e desejo excluir permanentemente esta conta')),
                ])
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar')),
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

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()));
    try {
      final idToken = await FirebaseAuth.instance.currentUser?.getIdToken(true);
      if (idToken == null) {
        Navigator.pop(context);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Erro: usuário não autenticado')));
        return;
      }
      final url = Uri.parse(
          'https://us-central1-wismart-118c3.cloudfunctions.net/deleteUserAccount');
      final resp = await http.post(url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken'
          },
          body: jsonEncode({'confirm': true}));
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Conta excluída com sucesso. Limpe o cache do app/telefone manualmente.')));
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
              (r) => false);
        }
      } else {
        final body = resp.body;
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text('Falha ao excluir conta: ${resp.statusCode} $body')));
      }
    } catch (e) {
      Navigator.pop(context);
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao excluir conta: $e')));
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
          (route) => false);
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
  void _openServiceDetails(
      {required String serviceId, required Map<String, dynamic> serviceData}) {
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
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Depois')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Completar')),
          ],
        ),
      );
      if (go == true && mounted) {
        final user = FirebaseAuth.instance.currentUser;
        Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ClientRegisterPage(user: user, isBusinessAdding: false),
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
      return const Scaffold(
          body: Center(
              child:
                  CircularProgressIndicator(color: AppColors.primaryPurple)));
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
              : _selectedIndex == 1
                  ? _buildFavoritesView(isDesktop: false)
                  : _buildScheduleView(isDesktop: false),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (idx) =>
                setState(() => _selectedIndex = idx),
            backgroundColor: Colors.white,
            elevation: 10,
            shadowColor: Colors.black12,
            indicatorColor: AppColors.primaryPurple.withValues(alpha: 0.2),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore),
                  label: "Explorar"),
              NavigationDestination(
                  icon: Icon(Icons.favorite_border),
                  selectedIcon: Icon(Icons.favorite),
                  label: "Favoritos"),
              NavigationDestination(
                  icon: Icon(Icons.calendar_today_outlined),
                  selectedIcon: Icon(Icons.calendar_today),
                  label: "Agendamentos"),
            ],
          ),
        );
      },
    );
  }

  // ============ VIEW: FAVORITOS ============
  Widget _buildFavoritesView({required bool isDesktop}) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('Faça login para ver seus favoritos'));
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('favorites')
          .orderBy('added_at', descending: true)
          .snapshots(),
      builder: (context, favSnap) {
        if (favSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final favDocs = favSnap.data?.docs ?? [];
        if (favDocs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, size: 64, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text('Nenhuma loja favorita ainda',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500])),
                const SizedBox(height: 8),
                Text('Toque no ❤️ nas lojas para adicioná-las aqui',
                    style: TextStyle(fontSize: 13, color: Colors.grey[400])),
              ],
            ),
          );
        }
        final shopIds = favDocs.map((d) => d.id).toList();
        // Firestore 'whereIn' supports max 30 items per query
        final chunks = <List<String>>[];
        for (var i = 0; i < shopIds.length; i += 10) {
          chunks.add(shopIds.sublist(
              i, i + 10 > shopIds.length ? shopIds.length : i + 10));
        }
        return FutureBuilder<List<DocumentSnapshot>>(
          future: Future.wait(
            chunks.map((chunk) => FirebaseFirestore.instance
                .collection('shops')
                .where(FieldPath.documentId, whereIn: chunk)
                .get()
                .then((s) => s.docs)),
          ).then((lists) => lists.expand((l) => l).toList()),
          builder: (context, shopsSnap) {
            if (shopsSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final shops = shopsSnap.data ?? [];
            if (shops.isEmpty) {
              return Center(
                child: Text('Nenhuma loja encontrada',
                    style: TextStyle(color: Colors.grey[500])),
              );
            }
            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  backgroundColor: const Color(0xFFF5F7FA),
                  elevation: 0,
                  floating: true,
                  toolbarHeight: 60,
                  titleSpacing: 20,
                  title: Row(children: [
                    const Icon(Icons.favorite, color: Colors.red, size: 22),
                    const SizedBox(width: 10),
                    const Text('Meus Favoritos',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text('${shops.length}',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.red)),
                    ),
                  ]),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(20),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.72,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _ShopCard(
                        shop: shops[i],
                        onTap: () => _openShopProfile(shops[i]),
                      ),
                      childCount: shops.length,
                    ),
                  ),
                ),
              ],
            );
          },
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
            toolbarHeight: 56,
            titleSpacing: 0,
            title: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Apenas o logo (já contém o nome do app)
                  Image.asset('assets/images/logo_purple.png', height: 36),

                  const Spacer(),

                  // Perfil Mini com PopupMenu
                  PopupMenuButton<String>(
                    onSelected: _handleProfileMenu,
                    offset: const Offset(0, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(children: const [
                          Icon(Icons.person_outline,
                              size: 20, color: AppColors.primaryPurple),
                          SizedBox(width: 10),
                          Text('Editar Perfil'),
                        ]),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'logout',
                        child: Row(children: const [
                          Icon(Icons.logout, size: 20, color: Colors.red),
                          SizedBox(width: 10),
                          Text('Sair da Conta',
                              style: TextStyle(color: Colors.red)),
                        ]),
                      ),
                    ],
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: _userPhotoUrl != null
                              ? CachedNetworkImageProvider(_userPhotoUrl!)
                              : null,
                          child: _userPhotoUrl == null
                              ? const Icon(Icons.person, color: Colors.grey)
                              : null,
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.keyboard_arrow_down,
                            size: 16, color: Colors.grey[500]),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),

        // LOCATION PICKER - Compacto
        SliverToBoxAdapter(
          child: GestureDetector(
            onTap: _showLocationPicker,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_on,
                      size: 13,
                      color: _selectedLocation.isEmpty
                          ? Colors.grey[500]
                          : AppColors.primaryPurple),
                  const SizedBox(width: 3),
                  Text(
                    _selectedLocation.isEmpty
                        ? "Escolher localização"
                        : _selectedLocation,
                    style: TextStyle(
                      color: _selectedLocation.isEmpty
                          ? Colors.grey[500]
                          : AppColors.primaryPurple,
                      fontSize: 12,
                      fontWeight: _selectedLocation.isEmpty
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down,
                      size: 14,
                      color: _selectedLocation.isEmpty
                          ? Colors.grey[500]
                          : AppColors.primaryPurple),
                ],
              ),
            ),
          ),
        ),

        // 📏 SELETOR DE RAIO (KM)
        if (_selectedLocation.isNotEmpty && _userLat != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Raio de busca: ${_selectedRadius.toInt()} km",
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500),
                      ),
                      Text(
                        "Aumentar alcance",
                        style: TextStyle(
                            fontSize: 10, color: AppColors.primaryPurple),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: _selectedRadius,
                      min: 1,
                      max: 100,
                      divisions: 99,
                      activeColor: AppColors.primaryPurple,
                      inactiveColor:
                          AppColors.primaryPurple.withValues(alpha: 0.1),
                      onChanged: (v) => setState(() => _selectedRadius = v),
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 8)),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30), // Mais arredondado
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4))
                ],
              ),
              child: TextField(
                onChanged: (v) => setState(() => _searchText = v),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) {
                    _navigateToSearch(v.trim());
                  }
                },
                decoration: const InputDecoration(
                  hintText: "O que você procura hoje?",
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
              ),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 10)),

        // ⭐ SEÇÃO DESTAQUES - Horizontal
        SliverToBoxAdapter(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('shops')
                .where('is_boosted', isEqualTo: true)
                .limit(20)
                .snapshots(),
            builder: (context, snap) {
              final now = DateTime.now();
              final docs = (snap.data?.docs ?? []).where((doc) {
                final d = doc.data() as Map<String, dynamic>;
                // 📍 Filtro de Cidade
                final shopCity = (d['endereco'] ?? d['cidade'] ?? '')
                    .toString()
                    .toLowerCase();
                final matchesCity = _selectedLocation.isEmpty ||
                    shopCity.contains(_selectedLocation.toLowerCase()) ||
                    _selectedLocation.toLowerCase().contains(shopCity);

                // Filtra lojas com boost expirado
                final expires = d['boost_expires_at'] as Timestamp?;
                bool isExpired =
                    expires == null || expires.toDate().isBefore(now);

                return !isExpired && matchesCity;
              }).toList();
              if (docs.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFA000)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.rocket_launch,
                              size: 16, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Destaques',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFFFD700).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${docs.length}',
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFB8860B)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 160,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: docs.length,
                      itemBuilder: (ctx, i) {
                        final d = docs[i].data() as Map<String, dynamic>;
                        final img = d['coverUrl'] ?? d['imageUrl'] ?? '';
                        final cat = d['categoria']?.toString() ?? '';
                        Color fallback = Colors.grey[200]!;
                        IconData fi = Icons.store;
                        switch (cat.toLowerCase()) {
                          case 'barbearia':
                            fallback = const Color(0xFFE3F2FD);
                            fi = Icons.content_cut;
                            break;
                          case 'beleza':
                          case 'estética':
                            fallback = const Color(0xFFFCE4EC);
                            fi = Icons.face;
                            break;
                          case 'saúde':
                            fallback = const Color(0xFFE8F5E9);
                            fi = Icons.medical_services;
                            break;
                          case 'bem-estar':
                            fallback = const Color(0xFFFFF3E0);
                            fi = Icons.self_improvement;
                            break;
                        }
                        return GestureDetector(
                          onTap: () => _openShopProfile(docs[i]),
                          child: Container(
                            width: 140,
                            margin: const EdgeInsets.only(right: 14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFFFFD700)
                                      .withValues(alpha: 0.4),
                                  width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                    color: const Color(0xFFFFD700)
                                        .withValues(alpha: 0.12),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4)),
                                BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Stack(children: [
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(13)),
                                      child: img.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: img,
                                              fit: BoxFit.cover,
                                              width: double.infinity,
                                              height: double.infinity,
                                              errorWidget: (c, u, e) =>
                                                  Container(
                                                      color: fallback,
                                                      child: Icon(
                                                          fi,
                                                          color:
                                                              Colors.grey[400],
                                                          size: 36)))
                                          : Container(
                                              color: fallback,
                                              child: Center(
                                                  child: Icon(fi,
                                                      color: Colors.grey[400],
                                                      size: 36))),
                                    ),
                                    // 🚀 Badge dourado "DESTAQUE" com foguetinho
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          gradient: const LinearGradient(
                                            colors: [
                                              Color(0xFFFFD700),
                                              Color(0xFFFFA000)
                                            ],
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                                color: const Color(0xFFFFD700)
                                                    .withValues(alpha: 0.4),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2)),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            Icon(Icons.rocket_launch,
                                                size: 10, color: Colors.white),
                                            SizedBox(width: 3),
                                            Text('DESTAQUE',
                                                style: TextStyle(
                                                    fontSize: 8,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                    letterSpacing: 0.5)),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Logo overlay (bottom-left)
                                    if ((d['logoUrl'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Positioned(
                                        bottom: 6,
                                        left: 6,
                                        child: Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.white, width: 2),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.1),
                                                blurRadius: 4,
                                              ),
                                            ],
                                          ),
                                          child: ClipOval(
                                            child: CachedNetworkImage(
                                              imageUrl: d['logoUrl'],
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ]),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(d['nome'] ?? '',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 2),
                                        Row(children: [
                                          Icon(Icons.category,
                                              size: 11,
                                              color: Colors.grey[400]),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(cat,
                                                style: TextStyle(
                                                    color: Colors.grey[500],
                                                    fontSize: 11),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ),
                                        ]),
                                      ]),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              );
            },
          ),
        ),

        // Categorias
        SliverToBoxAdapter(
          child: SizedBox(
            height: 38,
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
                    avatar: isSelected
                        ? null
                        : Icon(cat['icon'], size: 16, color: Colors.grey[600]),
                    selected: isSelected,
                    onSelected: (b) =>
                        setState(() => _selectedCategory = cat['name']),
                    backgroundColor: Colors.white,
                    selectedColor: AppColors.primaryPurple,
                    labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                            color: isSelected
                                ? Colors.transparent
                                : Colors.grey.shade300)),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                );
              },
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 10)),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: Text(
              _searchText.isEmpty
                  ? "Recomendados para você"
                  : "Resultados da busca",
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 15)),

        // GRID DE LOJAS
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('shops').snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData)
              return const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()));

            final filtered = snapshot.data!.docs.where((doc) {
              final d = doc.data() as Map<String, dynamic>;

              // 🔥 CORREÇÃO: Lojas sem o campo 'ativo' são consideradas ATIVAS
              final bool isActive = d['ativo'] ?? true;

              final matchesText = (d['nome'] ?? "")
                  .toString()
                  .toLowerCase()
                  .contains(_searchText.toLowerCase());
              // Suporte a múltiplas categorias separadas por ponto e vírgula
              final matchesCat = _selectedCategory == "Todos" ||
                  (() {
                    final cats = (d['categoria'] ?? '')
                        .toString()
                        .split(';')
                        .map((c) => c.trim());
                    return cats.any((c) => c.contains(_selectedCategory));
                  })();

              // 📍 Filtro de Cidade / Raio
              final shopCity =
                  (d['endereco'] ?? d['cidade'] ?? '').toString().toLowerCase();

              bool matchesCity = _selectedLocation.isEmpty ||
                  shopCity.contains(_selectedLocation.toLowerCase()) ||
                  _selectedLocation.toLowerCase().contains(shopCity);

              // 🛰️ Lógica de Raio (KM)
              if (_userLat != null &&
                  _userLng != null &&
                  d['lat'] != null &&
                  d['lng'] != null) {
                final double distance = Geolocator.distanceBetween(
                      _userLat!,
                      _userLng!,
                      (d['lat'] as num).toDouble(),
                      (d['lng'] as num).toDouble(),
                    ) /
                    1000.0; // Converter para KM

                // Se temos coordenadas, o raio TEM PRECEDÊNCIA sobre a cidade
                matchesCity = distance <= _selectedRadius;
              }

              // Quando não está pesquisando, mostramos todas da cidade
              // mas priorizamos na ordenação as que tem perfil completo
              return matchesText && matchesCat && matchesCity && isActive;
            }).toList();

            // 🔀 Ordenação por Qualidade do Perfil (Media)
            filtered.sort((a, b) {
              final da = a.data() as Map<String, dynamic>;
              final db = b.data() as Map<String, dynamic>;

              int getScore(Map<String, dynamic> d) {
                int s = 0;
                if ((d['logoUrl'] ?? '').toString().isNotEmpty) s += 10;
                if ((d['coverUrl'] ?? '').toString().isNotEmpty ||
                    (d['imageUrl'] ?? '').toString().isNotEmpty) s += 10;
                if (d['is_boosted'] == true) s += 100;
                return s;
              }

              return getScore(db).compareTo(getScore(da));
            });

            if (filtered.isEmpty) {
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 50),
                  child: Center(
                      child: Text("Nenhuma loja encontrada.",
                          style: TextStyle(color: Colors.grey))),
                ),
              );
            }

            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: isDesktop
                      ? 4
                      : 3, // 3 colunas no mobile para cards menores
                  childAspectRatio: isDesktop
                      ? 0.85
                      : 0.70, // Um pouco mais alto para evitar overflow no texto
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _ShopCard(
                      shop: filtered[index],
                      onTap: () => _openShopProfile(filtered[index])),
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
                Icon(Icons.auto_awesome,
                    color: AppColors.primaryPurple, size: 30),
                SizedBox(width: 10),
                Text("MarkaAI",
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
        color: isSelected
            ? AppColors.primaryPurple.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(icon,
            color: isSelected ? AppColors.primaryPurple : Colors.grey),
        title: Text(lbl,
            style: TextStyle(
                color: isSelected ? AppColors.primaryPurple : Colors.grey[800],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
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
                Text(_selectedIndex == 0 ? "Explorar" : "Minha Agenda",
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.bold)),
                if (_selectedIndex == 0)
                  const Text("Encontre os melhores serviços perto de você.",
                      style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            offset: const Offset(0, 50),
            color: Colors.white,
            surfaceTintColor: Colors.white,
            onSelected: _handleProfileMenu,
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
                  backgroundImage: _userPhotoUrl != null
                      ? CachedNetworkImageProvider(_userPhotoUrl!)
                      : null,
                  child: (_userPhotoUrl == null)
                      ? const Icon(Icons.person, size: 20)
                      : null,
                ),
                const SizedBox(width: 5),
                const Icon(Icons.keyboard_arrow_down,
                    size: 18, color: Colors.grey),
              ],
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                  value: 'edit',
                  child: Row(children: const [
                    Icon(Icons.person_outline,
                        size: 16, color: AppColors.primaryPurple),
                    SizedBox(width: 8),
                    Text('Editar Perfil')
                  ])),
              const PopupMenuDivider(),
              PopupMenuItem(
                  value: 'logout',
                  child: Row(children: const [
                    Icon(Icons.logout, color: Colors.red, size: 16),
                    SizedBox(width: 8),
                    Text('Sair da Conta', style: TextStyle(color: Colors.red))
                  ])),
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

class _ShopCard extends StatefulWidget {
  final DocumentSnapshot shop;
  final VoidCallback onTap;

  const _ShopCard({required this.shop, required this.onTap});

  @override
  State<_ShopCard> createState() => _ShopCardState();
}

class _ShopCardState extends State<_ShopCard> {
  bool _isFavorite = false;
  bool _loadingFav = true;

  @override
  void initState() {
    super.initState();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loadingFav = false);
      return;
    }
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(widget.shop.id)
        .get();
    if (mounted) {
      setState(() {
        _isFavorite = doc.exists;
        _loadingFav = false;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(widget.shop.id);
    setState(() => _isFavorite = !_isFavorite);
    try {
      if (_isFavorite) {
        await ref.set({'added_at': FieldValue.serverTimestamp()});
      } else {
        await ref.delete();
      }
    } catch (_) {
      if (mounted) setState(() => _isFavorite = !_isFavorite);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.shop.data() as Map<String, dynamic>;
    final imgUrl = data['coverUrl'] ?? data['imageUrl'] ?? "";
    final logoUrl = data['logoUrl'] ?? "";
    final categoria = data['categoria']?.toString() ?? 'Outros';

    final bool isDestaque = data['destaque'] == true ||
        (data['rating'] != null && data['rating'] >= 4.5);

    Color getCatColor(String c) {
      switch (c.toLowerCase()) {
        case 'barbearia':
          return const Color(0xFFE3F2FD);
        case 'beleza':
        case 'estética':
          return const Color(0xFFFCE4EC);
        case 'saúde':
          return const Color(0xFFE8F5E9);
        case 'bem-estar':
          return const Color(0xFFFFF3E0);
        default:
          return Colors.grey[100]!;
      }
    }

    IconData getCatIcon(String c) {
      switch (c.toLowerCase()) {
        case 'barbearia':
          return Icons.content_cut;
        case 'beleza':
        case 'estética':
          return Icons.face;
        case 'saúde':
          return Icons.medical_services;
        case 'bem-estar':
          return Icons.self_improvement;
        default:
          return Icons.store;
      }
    }

    final Color fallbackColor = getCatColor(categoria);
    final IconData fallbackIcon = getCatIcon(categoria);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Stack(
                children: [
                  // IMAGEM OU FALLBACK
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(12)),
                      child: imgUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: imgUrl,
                              fit: BoxFit.cover,
                              placeholder: (c, u) =>
                                  Container(color: Colors.grey[200]),
                              errorWidget: (c, u, e) => Container(
                                color: fallbackColor,
                                child: Icon(fallbackIcon,
                                    color: Colors.grey[400], size: 40),
                              ),
                            )
                          : Container(
                              color: fallbackColor,
                              child: Center(
                                child: Icon(fallbackIcon,
                                    color: Colors.grey[400], size: 50),
                              ),
                            ),
                    ),
                  ),

                  // BADGE DESTAQUE (Top Right)
                  if (isDestaque)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFD700),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 4)
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.rocket_launch,
                                size: 10, color: Colors.black),
                            SizedBox(width: 4),
                            Text("DESTAQUE",
                                style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black)),
                          ],
                        ),
                      ),
                    )
                  else
                    // AVALIAÇÃO (Top Right se não for destaque)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star,
                                size: 10, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              (data['rating'] ?? 5.0).toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),

                  Positioned(
                    top: 6,
                    left: 6,
                    child: GestureDetector(
                      onTap: _toggleFavorite,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 4),
                          ],
                        ),
                        child: Icon(
                          _isFavorite ? Icons.favorite : Icons.favorite_border,
                          size: 12,
                          color: _isFavorite ? Colors.red : Colors.grey[400],
                        ),
                      ),
                    ),
                  ),

                  // LOGO (Bottom Left - Sobrepondo)
                  if (logoUrl.isNotEmpty)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 4)
                            ]),
                        child: ClipOval(
                            child: CachedNetworkImage(
                                imageUrl: logoUrl, fit: BoxFit.cover)),
                      ),
                    ),
                ],
              ),
            ),

            // INFO DA LOJA
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['nome'] ?? "Loja",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(data['categoria'] ?? "Serviços",
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 9)),
                      ],
                    ),
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
    dynamic rawFotos = sData['fotos_urls'] ??
        sData['fotos'] ??
        sData['imageUrl'] ??
        sData['imagens'];

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
                  decoration: const BoxDecoration(
                      color: Colors.black45, shape: BoxShape.circle),
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
                              onPageChanged: (idx) =>
                                  setState(() => _currentImageIndex = idx),
                              itemBuilder: (context, index) {
                                return CachedNetworkImage(
                                  imageUrl: images[index],
                                  fit: BoxFit.cover,
                                  placeholder: (c, u) => const Center(
                                      child: CircularProgressIndicator()),
                                  errorWidget: (c, u, e) => Container(
                                      color: Colors.grey[200],
                                      child: const Icon(Icons.broken_image,
                                          size: 50, color: Colors.grey)),
                                );
                              },
                            )
                          : Container(
                              color: Colors.grey[200],
                              child: const Center(
                                  child: Icon(Icons.spa,
                                      size: 80, color: Colors.grey))),
                      if (images.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: images.asMap().entries.map((entry) {
                              return Container(
                                width: 8.0,
                                height: 8.0,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 4.0),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(
                                      alpha: _currentImageIndex == entry.key
                                          ? 0.9
                                          : 0.4),
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
                              style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                currencyFormat.format(sData['preco'] ?? 0),
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryPurple),
                              ),
                              Text(
                                "${sData['tempo_min'] ?? 30} min",
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 14),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 20),
                      const Text("Sobre o serviço",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Text(
                        sData['descricao'] ??
                            "Sem descrição disponível para este serviço.",
                        style: TextStyle(
                            color: Colors.grey[700], fontSize: 16, height: 1.6),
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
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -5))
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: widget.onBookPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text(
                      "AGENDAR AGORA",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
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
