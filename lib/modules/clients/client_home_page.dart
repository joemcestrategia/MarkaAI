// ignore_for_file: unused_element, unused_field, unused_local_variable
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geocoding/geocoding.dart';
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
import '../../core/widgets/seletor_de_cidade.dart';
import '../../core/utils/string_utils.dart';

class ClientHomePage extends StatefulWidget {
  final int initialTabIndex;
  const ClientHomePage({super.key, this.initialTabIndex = 0});

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

  // Filtros de localização
  String _selectedLocation = "";
  String _searchText = "";
  String _selectedCategory = "Todos";
  double? _userLat;
  double? _userLng;
  final double _selectedRadius = 20.0; // km

  // ?? Cidade selecionada pelo cliente (persiste no SharedPreferences)
  CidadeSelecionada? _cidadeSelecionada;

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
    _selectedIndex = widget.initialTabIndex;
    _loadUserData();
    _setupNotifications();
    _loadCidadeSalva();
  }

  // Carrega cidade salva no SharedPreferences
  Future<void> _loadCidadeSalva() async {
    final cidade = await CidadePrefs.carregar();
    if (mounted) {
      if (cidade != null) {
        setState(() => _cidadeSelecionada = cidade);
      } else {
        // Primeira vez: tenta detectar automaticamente
        _detectLocationAndSetCity();
      }
    }
  }

  Future<void> _detectLocationAndSetCity() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 5),
      );

      final List<Placemark> placemarks =
          await placemarkFromCoordinates(pos.latitude, pos.longitude);

      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final String detectedCity =
            (p.subAdministrativeArea ?? p.locality ?? '').trim();
        final String detectedState = (p.administrativeArea ?? '').trim();

        if (detectedCity.isNotEmpty) {
          // Tenta "encaixar" no que temos no banco (case insensitive)
          final suggestions =
              await SeletorDeCidadeModal.getCitySuggestions(detectedCity);
          CidadeSelecionada? finalCidade;

          if (suggestions.isNotEmpty) {
            final best = suggestions.first;
            finalCidade = CidadeSelecionada(
              cidade: best.cidade,
              estado: best.estado,
              definidoEm: DateTime.now(),
            );
          } else {
            // Se não achou no banco, usa o que o GPS deu (fallback)
            finalCidade = CidadeSelecionada(
              cidade: detectedCity,
              estado: detectedState.length > 2
                  ? detectedState.substring(0, 2).toUpperCase()
                  : detectedState.toUpperCase(),
              definidoEm: DateTime.now(),
            );
          }

          setState(() => _cidadeSelecionada = finalCidade);
          await CidadePrefs.salvar(finalCidade);
          debugPrint(
              '📍 Localização automática: ${finalCidade.cidade}/${finalCidade.estado}');
        }
      }
    } catch (e) {
      debugPrint('Erro ao detectar localização: $e');
    }
  }

  // Abre a tela de seleção de cidade
  void _mostrarSeletorDeCidade() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SeletorDeCidadePage(
          cidadeAtual: _cidadeSelecionada,
          onCidadeSelecionada: (c) {
            setState(() {
              _cidadeSelecionada = c;
              // Sincroniza com o filtro legado de lojas
              _selectedLocation = c.cidade;
            });
          },
        ),
      ),
    );
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Linha com ícone + título
            Row(
              children: [
                Icon(Icons.logout_rounded,
                    color: Colors.red.shade600, size: 22),
                const SizedBox(width: 10),
                Text(
                  "Sair da Conta",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Text(
              "Tem certeza que deseja sair?\nVocê precisará fazer login novamente.",
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),

            // Botão Sair
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text("Confirmar Saída",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _handleLogout();
                },
              ),
            ),
            const SizedBox(height: 10),

            // Botão Cancelar
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  foregroundColor: Colors.grey[700],
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Cancelar",
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
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
      case 'privacy':
        _showPrivacySheet();
        break;
      case 'delete':
        _deleteAccount();
        break;
      case 'logout':
        _confirmLogout();
        break;
    }
  }

  void _showPrivacySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.privacy_tip_outlined,
                        color: AppColors.primaryPurple),
                    const SizedBox(width: 10),
                    const Text('Privacidade & Dados',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _privacySection('📋 Dados Coletados',
                          'Coletamos: nome, e-mail, telefone, localização aproximada e histórico de agendamentos para proporcionar a melhor experiência no app.'),
                      _privacySection('🔐 Uso dos Dados',
                          'Seus dados são usados exclusivamente para identificar sua conta, exibir estabelecimentos próximos e registrar seus agendamentos. Não compartilhamos dados com terceiros para fins publicitários.'),
                      _privacySection('📍 Localização',
                          'A localização é usada apenas para filtrar estabelecimentos próximos. Você pode desativar a permissão de localização a qualquer momento nas configurações do seu dispositivo.'),
                      _privacySection('🗑️ Seus Direitos (LGPD)',
                          'De acordo com a Lei Geral de Proteção de Dados (Lei nº 13.709/2018), você tem direito a: acessar, corrigir, exportar e excluir seus dados pessoais a qualquer momento.'),
                      _privacySection('📧 Contato',
                          'Para exercer seus direitos ou esclarecer dúvidas sobre privacidade, entre em contato: privacidade@markaai.com.br'),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    color: Colors.red, size: 20),
                                SizedBox(width: 8),
                                Text('Excluir Conta',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                        fontSize: 15)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'A exclusão da conta remove permanentemente todos os seus dados, agendamentos e histórico. Esta ação é irreversível.',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.black87),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.delete_forever,
                                    color: Colors.red, size: 18),
                                label: const Text('Excluir minha conta',
                                    style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _deleteAccount();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _privacySection(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 6),
          Text(body,
              style: const TextStyle(
                  fontSize: 13, color: Colors.black54, height: 1.5)),
        ],
      ),
    );
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
        if (mounted) Navigator.pop(context);
        if (!mounted) return;
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
      if (mounted) Navigator.pop(context);
      if (resp.statusCode == 200) {
        // success
        try {
          await GoogleSignIn().signOut();
          await GoogleSignIn().disconnect();
        } catch (_) {}
        await SessionService.logout();
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Conta excluída com sucesso. Limpe o cache do app/telefone manualmente.')));
        Navigator.pushAndRemoveUntil(context,
            MaterialPageRoute(builder: (_) => const LoginPage()), (r) => false);
      } else {
        final body = resp.body;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Falha ao excluir conta: ${resp.statusCode} $body')));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
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
          onBookService: (sDoc) {
            // ✅ Navega para a página de detalhes do serviço PRIMEIRO
            _openServiceDetails(serviceDoc: sDoc);
          },
        ),
      ),
    );
  }

  void _openServiceDetails({required DocumentSnapshot serviceDoc}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClientServiceDetailPage(
          serviceDoc: serviceDoc,
        ),
      ),
    );
  }

  Future<void> _openBookingPage({
    required DocumentSnapshot shop,
    required DocumentSnapshot serviceDoc,
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
                    ClientRegisterPage(user: user, isBusinessAdding: false)));
      }
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BookingPage(
          shop: shop,
          serviceDoc: serviceDoc,
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
      return const Center(child: Text('Faa login para ver seus favoritos'));
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
                Text('Toque no ?? nas lojas para adicion-las aqui',
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
                  // Apenas o logo (j contm o nome do app)
                  Image.asset('assets/images/logo_purple.png', height: 36),

                  const Spacer(),

                  // Seletor de Cidade (Pequeno no topo)
                  SeletorDeCidadeButton(
                    cidadeSelecionada: _cidadeSelecionada,
                    onTap: _mostrarSeletorDeCidade,
                  ),

                  const SizedBox(width: 8),

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
                        value: 'privacy',
                        child: Row(children: const [
                          Icon(Icons.privacy_tip_outlined,
                              size: 20, color: Colors.blueGrey),
                          SizedBox(width: 10),
                          Text('Privacidade & Dados'),
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

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: TextField(
                onChanged: (v) => setState(() => _searchText = v),
                decoration: InputDecoration(
                  hintText: "O que você procura hoje?",
                  prefixIcon:
                      const Icon(Icons.search, color: AppColors.primaryPurple),
                  suffixIcon: _searchText.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            setState(() => _searchText = "");
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ),
          ),
        ),

        // ? SEO DESTAQUES  Banner largo logo abaixo da busca
        SliverToBoxAdapter(
          child: _BoostBannerCarousel(
            cidadeSelecionada: _cidadeSelecionada,
            onShopTap: _openShopProfile,
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
          stream: _cidadeSelecionada == null
              ? const Stream.empty()
              : FirebaseFirestore.instance
                  .collection('shops')
                  .where('cidade', isEqualTo: _cidadeSelecionada!.cidade)
                  // Nota: se quisermos filtrar por estado também, precisamos de índice composto
                  .snapshots(),
          builder: (context, snapshot) {
            if (_cidadeSelecionada == null) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search, size: 60, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'Digite uma cidade para encontrar\nserviços próximos a você.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 100),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.location_off_outlined,
                            size: 60, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhuma loja encontrada em ${_cidadeSelecionada!.cidade}.\nTente outra cidade.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final filtered = snapshot.data!.docs.where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final bool isActive = d['ativo'] ?? true;

              // Filtro adicional por estado se houver ambiguidade (opcional)
              if (_cidadeSelecionada!.estado.isNotEmpty) {
                final String shopEstado = (d['estado'] ??
                        d['endereco']?['estado'] ??
                        d['uf'] ??
                        d['endereco']?['uf'] ??
                        '')
                    .toString()
                    .toUpperCase();
                if (shopEstado.isNotEmpty &&
                    !shopEstado
                        .contains(_cidadeSelecionada!.estado.toUpperCase()) &&
                    !_cidadeSelecionada!.estado
                        .toUpperCase()
                        .contains(shopEstado)) {
                  return false;
                }
              }

              // Filtro por texto (busca por nome da loja)
              final String searchLower = _searchText.isEmpty
                  ? ""
                  : StringUtils.removeDiacritics(_searchText).toLowerCase();
              final matchesText = searchLower.isEmpty ||
                  StringUtils.removeDiacritics(d['nome'] ?? '')
                      .toLowerCase()
                      .contains(searchLower);

              if (!matchesText) return false;

              final matchesCat = _selectedCategory == "Todos" ||
                  (() {
                    final cats = (d['categoria'] ?? '')
                        .toString()
                        .split(';')
                        .map((c) => c.trim());
                    return cats.any((c) => c.contains(_selectedCategory));
                  })();

              return matchesCat && isActive;
            }).toList();

            // 🏆 Ordenação por Qualidade do Perfil (Media)
            filtered.sort((a, b) {
              final da = a.data() as Map<String, dynamic>;
              final db = b.data() as Map<String, dynamic>;

              int getScore(Map<String, dynamic> d) {
                int s = 0;
                if ((d['logoUrl'] ?? '').toString().isNotEmpty) s += 10;
                if ((d['coverUrl'] ?? '').toString().isNotEmpty ||
                    (d['imageUrl'] ?? '').toString().isNotEmpty) {
                  s += 10;
                }
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
                  const Text("Encontre os melhores servios perto de voc.",
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
// ?? COMPONENTES VISUAIS (DESIGN SYSTEM)
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
        case 'esttica':
          return const Color(0xFFFCE4EC);
        case 'sade':
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
        case 'esttica':
          return Icons.face;
        case 'sade':
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
                    // AVALIAO (Top Right se no for destaque)
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

// ?? PGINA RESTAURADA: DETALHES DO SERVIO
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

  DocumentSnapshot? _shopDoc;
  bool _isLoadingShop = true;
  bool _isOnlineBookingActive = true;

  @override
  void initState() {
    super.initState();
    _loadShopConfig();
  }

  Future<void> _loadShopConfig() async {
    try {
      final shopId = widget.serviceData['shopId'];
      if (shopId != null) {
        final doc = await FirebaseFirestore.instance
            .collection('shops')
            .doc(shopId)
            .get();
        if (doc.exists) {
          _shopDoc = doc;
          final config = doc.data()?['config'] as Map<String, dynamic>?;
          _isOnlineBookingActive = config?['agendamento_online_ativo'] ?? true;
        }
      }
    } catch (e) {
      debugPrint("Erro ao carregar loja: $e");
    } finally {
      if (mounted) setState(() => _isLoadingShop = false);
    }
  }

  void _agendarViaWhatsApp() async {
    if (_shopDoc == null) return;

    final shopData = _shopDoc!.data() as Map<String, dynamic>;
    final phone = shopData['telefone'] ?? shopData['whatsapp'];
    if (phone == null || phone.toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Loja no possui nmero de WhatsApp cadastrado.")),
      );
      return;
    }

    String cleanPhone = phone.toString().replaceAll(RegExp(r'\D'), '');
    if (!cleanPhone.startsWith('55')) {
      cleanPhone = '55$cleanPhone';
    }

    final String serviceName = widget.serviceData['nome'] ?? 'Servio';
    final String shopName = shopData['nome'] ?? 'loja';
    final String message =
        "Ol, vim pelo App MarkaAI e gostaria de agendar o servio $serviceName na $shopName.";

    final Uri url = Uri.parse(
        "https://wa.me/$cleanPhone?text=${Uri.encodeComponent(message)}");

    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'Cannot launch url';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Erro ao abrir o WhatsApp. Tente novamente.")),
        );
      }
    }
  }

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
                              sData['nome'] ?? "Servio",
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
                      const Text("Sobre o servio",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Text(
                        sData['descricao'] ??
                            "Sem descrio disponvel para este servio.",
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
                    onPressed: _isLoadingShop
                        ? null
                        : (!_isOnlineBookingActive
                            ? _agendarViaWhatsApp
                            : widget.onBookPressed),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isOnlineBookingActive
                          ? AppColors.primaryPurple
                          : Colors.green[600],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isLoadingShop
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!_isOnlineBookingActive) ...[
                                const Icon(Icons.chat,
                                    color: Colors.white, size: 20),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                _isOnlineBookingActive
                                    ? "AGENDAR AGORA"
                                    : "AGENDAR PELO WHATSAPP",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
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

// -----------------------------------------------------------------------------
// ?? BOOST BANNER CAROUSEL  banner largo de negócios impulsionados
// -----------------------------------------------------------------------------
class _BoostBannerCarousel extends StatefulWidget {
  final CidadeSelecionada? cidadeSelecionada;
  final void Function(DocumentSnapshot) onShopTap;

  const _BoostBannerCarousel({
    required this.cidadeSelecionada,
    required this.onShopTap,
  });

  @override
  State<_BoostBannerCarousel> createState() => _BoostBannerCarouselState();
}

class _BoostBannerCarouselState extends State<_BoostBannerCarousel> {
  final PageController _pageCtrl = PageController(viewportFraction: 0.92);
  int _currentPage = 0;
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  void _startAutoScroll() {
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_pageCtrl.hasClients) return;
      // will be updated after docs are loaded
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('shops')
          .where('is_boosted', isEqualTo: true)
          .limit(20)
          .snapshots(),
      builder: (context, snap) {
        final now = DateTime.now();
        final cidade = widget.cidadeSelecionada?.cidade.toLowerCase() ?? '';

        final docs = (snap.data?.docs ?? []).where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          // Filtro de cidade
          final shopCity =
              (d['cidade'] ?? d['endereco'] ?? '').toString().toLowerCase();
          final matchesCity = cidade.isEmpty ||
              shopCity.contains(cidade) ||
              cidade.contains(shopCity);
          // Filtro de boost expirado
          final expires = d['boost_expires_at'] as Timestamp?;
          final isExpired = expires == null || expires.toDate().isBefore(now);
          return !isExpired && matchesCity;
        }).toList();

        if (docs.isEmpty) return const SizedBox.shrink();

        // Restart auto-scroll when docs change
        _autoScrollTimer?.cancel();
        _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
          if (!_pageCtrl.hasClients) return;
          final next = (_currentPage + 1) % docs.length;
          _pageCtrl.animateToPage(
            next,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ttulo
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFFD700), Color(0xFFFFA000)]),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.rocket_launch,
                      size: 15, color: Colors.white),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Destaques',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${docs.length}',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF9A6F00))),
                ),
              ]),
            ),

            // Carousel de banners largos
            SizedBox(
              height: 170,
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: docs.length,
                onPageChanged: (p) => setState(() => _currentPage = p),
                itemBuilder: (ctx, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final img = d['coverUrl'] ?? d['imageUrl'] ?? '';
                  final nome = d['nome'] ?? '';
                  final cat = d['categoria'] ?? d['nicho'] ?? '';
                  final logo = d['logoUrl'] ?? '';

                  return GestureDetector(
                    onTap: () => widget.onShopTap(docs[i]),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6A1B9A), Color(0xFF4A148C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF6A1B9A).withValues(alpha: 0.25),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color:
                                const Color(0xFFFFD700).withValues(alpha: 0.08),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Stack(fit: StackFit.expand, children: [
                          // Imagem de capa
                          if (img.isNotEmpty)
                            CachedNetworkImage(
                              imageUrl: img,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  Container(color: const Color(0xFF4A148C)),
                            ),
                          // Gradiente escurece o fundo para legibilidade
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Color(0xDD1A0033),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                          // Badge DESTAQUE  topo direito
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFFD700),
                                    Color(0xFFFFA000)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                      color: const Color(0xFFFFD700)
                                          .withValues(alpha: 0.5),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2)),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.rocket_launch,
                                      size: 11, color: Colors.white),
                                  SizedBox(width: 4),
                                  Text('DESTAQUE',
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          letterSpacing: 0.6)),
                                ],
                              ),
                            ),
                          ),
                          // Contedo inferior: logo + nome + categoria
                          Positioned(
                            bottom: 12,
                            left: 12,
                            right: 12,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Logo circle
                                if (logo.isNotEmpty)
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 2.5),
                                      boxShadow: [
                                        BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.2),
                                            blurRadius: 6),
                                      ],
                                    ),
                                    child: ClipOval(
                                      child: CachedNetworkImage(
                                        imageUrl: logo,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        nome,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          shadows: [
                                            Shadow(
                                                blurRadius: 8,
                                                color: Colors.black45),
                                          ],
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (cat.isNotEmpty)
                                        Text(
                                          cat,
                                          style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.8),
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                        ),
                                    ],
                                  ),
                                ),
                                // Boto Ver Loja
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.5)),
                                  ),
                                  child: const Text(
                                    'Ver loja',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Dots indicadores
            if (docs.length > 1) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(docs.length, (i) {
                  final active = i == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color:
                          active ? AppColors.primaryPurple : Colors.grey[300],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ],
            const SizedBox(height: 12),
          ],
        );
      },
    );
  }
}
