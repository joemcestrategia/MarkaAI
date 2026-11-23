// ignore_for_file: unused_element, unused_field, unused_local_variable
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/profile_check_service.dart';
import '../../core/services/shop_data_cache_service.dart';
import '../../core/widgets/supabase_stream_widget.dart';
import '../login/login_page.dart';
import '../schedule/booking_page.dart';
import 'shop_profile_page.dart';
import 'my_appointments_page.dart';
import 'appointment_confirmation_page.dart';
import 'client_service_detail_page.dart';
import 'address_selector_page.dart';
import 'client_search_page.dart';
import 'client_register_page.dart';
import '../../core/widgets/seletor_de_cidade.dart';
import 'package:markaai/core/utils/string_utils.dart';
import '../../core/utils/shop_image_keywords.dart';
import '../../core/utils/shop_category_helper.dart';
import '../../core/widgets/pexels_image_widget.dart';
import '../../core/widgets/shared_bottom_nav_bar.dart';
import '../../services/update_service.dart';
import '../../core/widgets/afro_comb_icon.dart';

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

  // Controle de Abas Visitadas (Lazy Loading)
  final List<bool> _tabVisited = [false, false, false];

  // Filtros de localização
  String _selectedLocation = "";
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<String> _searchNotifier = ValueNotifier('');
  final ValueNotifier<String> _categoryNotifier = ValueNotifier('Todos');
  double? _userLat;
  double? _userLng;
  final double _selectedRadius = 20.0; // km

  // Chaves para os Navigators aninhados
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  final GlobalKey<MyAppointmentsPageState> _appointmentsKey = GlobalKey();

  // ?? Cidade selecionada pelo cliente (persiste no SharedPreferences)
  CidadeSelecionada? _cidadeSelecionada;
  // Notifier para propagar mudanças dentro dos Navigators aninhados
  final ValueNotifier<CidadeSelecionada?> _cidadeNotifier = ValueNotifier(null);

  final List<Map<String, dynamic>> _categories = [
    {"name": "Todos", "icon": Icons.grid_view},
    {
      "name": "Trancistas",
      "isAfroComb": true,
    },
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
    _tabVisited[_selectedIndex] = true; // Marca aba inicial como visitada
    _loadUserData();
    _loadCidadeSalva();
    _setupNotifications();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      UpdateService.checkForUpdateAndPrompt(context);
    });
  }

  @override
  void dispose() {
    _cidadeNotifier.dispose();
    _searchController.dispose();
    _searchNotifier.dispose();
    _categoryNotifier.dispose();
    super.dispose();
  }

  // Carrega cidade salva no SharedPreferences
  Future<void> _loadCidadeSalva() async {
    final cidade = await CidadePrefs.carregar();
    if (mounted) {
      if (cidade != null) {
        setState(() {
          _cidadeSelecionada = cidade;
          _selectedLocation = cidade.cidade;
        });
        _cidadeNotifier.value = cidade;
        // Cidade já salva: não sobrescreve com GPS (usuário pode alterar pelo seletor)
      } else {
        // Primeira vez sem cidade salva: tenta detectar automaticamente
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
        timeLimit: const Duration(seconds: 10),
      );

      String detectedCity = '';
      String detectedState = '';

      try {
        final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse'
          '?lat=${pos.latitude}&lon=${pos.longitude}'
          '&format=json&accept-language=pt-BR',
        );
        final resp =
            await http.get(uri, headers: {'User-Agent': 'MarkaAI/1.0'});
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final addr = data['address'] as Map<String, dynamic>?;
          detectedCity = (addr?['city'] ??
                  addr?['town'] ??
                  addr?['village'] ??
                  addr?['municipality'] ??
                  '')
              .toString()
              .trim();
          detectedState =
              (addr?['state_code'] ?? addr?['state'] ?? '').toString().trim();
        }
      } catch (_) {}

      if (detectedCity.isEmpty || !mounted) return;

      // Só define cidade se ainda não há nenhuma (evita sobrescrever seleção manual)
      if (_cidadeSelecionada != null) return;

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

      if (mounted) {
        setState(() {
          _cidadeSelecionada = finalCidade;
          _selectedLocation = finalCidade!.cidade;
        });
        _cidadeNotifier.value = finalCidade;
        await CidadePrefs.salvar(finalCidade);
        debugPrint(
            '📍 Localização automática: ${finalCidade.cidade}/${finalCidade.estado}');
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
              _selectedLocation = c.cidade;
            });
            _cidadeNotifier.value = c;
          },
        ),
      ),
    );
  }

  // Helper para cores de categoria (Smart Fallback)
  Color _getCategoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'trancista':
      case 'trancistas':
      case 'tranças':
      case 'trancas':
        return const Color(0xFFEDE7F6); // Lilás / Roxo suave
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
      case 'trancista':
      case 'trancistas':
      case 'tranças':
      case 'trancas':
        return Icons.auto_awesome;
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
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final appointmentId =
          message.data['appointment_id'] ?? message.data['appointmentId'];
      final title = message.notification?.title ?? '';
      final body = message.notification?.body ?? '';
      if (appointmentId != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.primaryPurple,
            content: Text(body.isNotEmpty ? body : title),
            duration: const Duration(seconds: 8),
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
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final doc = await Supabase.instance.client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();
        if (mounted) {
          final data = doc;
          setState(() {
            _userId = user.id;
            _userName = data?['name'] ?? data?['nome'] ?? "Cliente";
            _userEmail = user.email ?? "";
            _userPhotoUrl = data?['photo_url'] as String? ??
                user.userMetadata?['avatar_url'] as String? ??
                user.userMetadata?['picture'] as String?;
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
    } catch (e) {
      debugPrint('⚠️ [ClientHome] Erro ao carregar dados do usuário: $e');
      if (mounted) {
        final user = Supabase.instance.client.auth.currentUser;
        setState(() {
          if (user != null) {
            _userId = user.id;
            _userName = user.userMetadata?['name'] as String? ??
                user.userMetadata?['nome'] as String? ??
                user.email ??
                'Usuario';
            _userEmail = user.email ?? '';
            _userPhotoUrl = user.userMetadata?['avatar_url'] as String? ??
                user.userMetadata?['picture'] as String?;
            _userTipo = user.userMetadata?['role'] as String? ?? 'cliente';
          }
          _isLoadingUserData = false;
        });
      }
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
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        await Supabase.instance.client.from('users').upsert({
          'id': uid,
          'last_location': {
            'label': _selectedLocation,
            'address': result['address'] ?? '',
            'city': result['city'] ?? '',
            'lat': result['lat'],
            'lng': result['lng'],
          },
        });
      }
    }
  }

  void _redirectToLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const LoginPage()));
      }
    });
  }

  void _confirmLogout() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
            24,
            16,
            24,
            MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom +
                24),
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

  void _showProfileBottomSheet() {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            bottom: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                        // Handle superior
                        Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Cabeçalho com dados do usuário
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.primaryPurple.withValues(alpha: 0.25),
                                  width: 1.5,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 26,
                                backgroundColor: const Color(0xFFF3F4F6),
                                backgroundImage: _userPhotoUrl != null
                                    ? CachedNetworkImageProvider(_userPhotoUrl!)
                                    : null,
                                child: _userPhotoUrl == null
                                    ? const Icon(Icons.person, size: 28, color: Colors.grey)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          _userName.isNotEmpty ? _userName : 'Cliente',
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1F2937),
                                            letterSpacing: -0.2,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryPurple
                                              .withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Text(
                                          'Cliente',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primaryPurple,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_userEmail.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      _userEmail,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                              splashRadius: 20,
                            ),
                          ],
                        ),

                        const SizedBox(height: 18),
                        Divider(height: 1, thickness: 1, color: Colors.grey[100]),
                        const SizedBox(height: 12),

                        // Opções modernas no padrão de UI do MarkaAI
                        _buildProfileOptionTile(
                          icon: Icons.person_outline_rounded,
                          iconBgColor: AppColors.primaryPurple.withValues(alpha: 0.1),
                          iconColor: AppColors.primaryPurple,
                          title: 'Editar Perfil',
                          subtitle: 'Altere seu nome, telefone e foto',
                          onTap: () {
                            Navigator.pop(ctx);
                            _handleProfileMenu('edit');
                          },
                        ),
                        const SizedBox(height: 8),

                        _buildProfileOptionTile(
                          icon: Icons.shield_outlined,
                          iconBgColor: const Color(0xFFE0F2FE),
                          iconColor: const Color(0xFF0284C7),
                          title: 'Privacidade & Dados',
                          subtitle: 'Gerencie suas preferências e dados',
                          onTap: () {
                            Navigator.pop(ctx);
                            _handleProfileMenu('privacy');
                          },
                        ),
                        const SizedBox(height: 8),

                        _buildProfileOptionTile(
                          icon: Icons.logout_rounded,
                          iconBgColor: const Color(0xFFFEE2E2),
                          iconColor: const Color(0xFFDC2626),
                          title: 'Sair da Conta',
                          subtitle: 'Encerrar sessão neste dispositivo',
                          titleColor: Colors.red.shade700,
                          onTap: () {
                            Navigator.pop(ctx);
                            _handleProfileMenu('logout');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      }

  Widget _buildProfileOptionTile({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey[200]!, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: titleColor ?? const Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  void _handleProfileMenu(String value) {
    switch (value) {
      case 'edit':
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) {
          _redirectToLogin();
          return;
        }
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
      useRootNavigator: true,
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
    final user = Supabase.instance.client.auth.currentUser;
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

    if (!mounted) return;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()));
    try {
      // Forçar refresh do token para garantir JWT válido antes da chamada
      final sessionResult =
          await Supabase.instance.client.auth.refreshSession();
      if (sessionResult.session == null) {
        if (mounted) Navigator.pop(context);
        throw Exception(
            'Sessão expirada. Faça login novamente para excluir a conta.');
      }

      // IMPORTANTE: NÃO passar o header Authorization manualmente.
      // O SDK do Supabase já injeta o JWT atualizado da sessão automaticamente.
      // Passar manualmente causa conflito de headers e resulta em erro 401.
      final response = await Supabase.instance.client.functions.invoke(
        'deleteUserAccount',
        body: {'userId': user.id},
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () =>
            throw Exception('A operação demorou muito. Tente novamente.'),
      );

      if (mounted) Navigator.pop(context); // Fecha diálogo de progresso

      final responseData = response.data;
      if (responseData is Map && responseData.containsKey('error')) {
        final errMsg = responseData['error'] as String? ?? '';
        if (errMsg.contains('Sessão') ||
            errMsg.contains('inválida') ||
            errMsg.contains('expirada')) {
          throw Exception(
              'Sua sessão expirou. Faça login novamente e tente excluir a conta.');
        }
        throw Exception(errMsg);
      }

      try {
        await GoogleSignIn().signOut();
        await GoogleSignIn().disconnect();
      } catch (_) {}
      await AuthService().signOut();

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Conta Excluída',
                style: TextStyle(color: Colors.green)),
            content: const Text(
                'Sua conta e todos os dados vinculados foram removidos com sucesso.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        if (mounted) {
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                  builder: (_) => const LoginPage(skipAutoLogin: true)),
              (r) => false);
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao excluir conta: $e'),
          backgroundColor: Colors.red));
    }
  }

  Future<void> _handleLogout() async {
    try {
      await GoogleSignIn().signOut();
      await GoogleSignIn().disconnect();
    } catch (_) {}
    await AuthService().signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
              builder: (context) => const LoginPage(skipAutoLogin: true)),
          (route) => false);
    }
  }

  void _openShopProfile(Map<String, dynamic> shop) {
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

  void _openServiceDetails({required Map<String, dynamic> serviceDoc}) {
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
    required Map<String, dynamic> shop,
    required Map<String, dynamic> serviceDoc,
  }) async {
    final uid = _userId ?? Supabase.instance.client.auth.currentUser?.id;
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
        final user = Supabase.instance.client.auth.currentUser;
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    ClientRegisterPage(user: user, isBusinessAdding: false)));
      }
      return;
    }
    if (!mounted) return;

    // Verificar se a loja permite múltiplos agendamentos
    final shopConfig = shop['config'] as Map<String, dynamic>? ?? {};
    final permitirMultiplos = shopConfig['permitir_multiplos'] ?? true;
    if (!permitirMultiplos) {
      final now = DateTime.now();
      final clientAppts = await Supabase.instance.client
          .from('appointments')
          .select('id, scheduled_at, status')
          .eq('client_id', uid)
          .eq('shop_id', shop['id'])
          .not('status', 'in',
              '("cancelado","rejeitado","recusado","excluido","pendente_pix")')
          .gte('scheduled_at', now.toIso8601String())
          .limit(1);

      if (clientAppts.isNotEmpty) {
        if (mounted) {
          final appt = clientAppts[0];
          final data = DateTime.parse(appt['scheduled_at']);
          final dataFmt =
              '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}';
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Agendamento não permitido'),
              content: Text(
                  'Esta loja não permite múltiplos agendamentos. Você já possui um agendamento ativo para $dataFmt.\n\n'
                  'Cancele o agendamento existente ou aguarde até a data para criar um novo.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }
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
                        child: IndexedStack(
                          index: _selectedIndex,
                          children: [
                            _tabVisited[0]
                                ? _buildTabNavigator(
                                    0, _buildExploreView(isDesktop: true))
                                : const SizedBox.shrink(),
                            _tabVisited[1]
                                ? _buildTabNavigator(
                                    1, _buildFavoritesView(isDesktop: true))
                                : const SizedBox.shrink(),
                            _tabVisited[2]
                                ? _buildTabNavigator(
                                    2, _buildScheduleView(isDesktop: true))
                                : const SizedBox.shrink(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;

            final NavigatorState? currentNavigator =
                _navigatorKeys[_selectedIndex].currentState;
            if (currentNavigator != null && currentNavigator.canPop()) {
              currentNavigator.pop();
            } else {
              if (_selectedIndex != 0) {
                setState(() => _selectedIndex = 0);
              } else {
                // Se estiver na home e não puder mais voltar internamente, permite fechar o app
                if (mounted) {
                  Navigator.of(context).pop();
                }
              }
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFFF5F7FA),
            body: IndexedStack(
              index: _selectedIndex,
              children: [
                _tabVisited[0]
                    ? _buildTabNavigator(0, _buildExploreView(isDesktop: false))
                    : const SizedBox.shrink(),
                _tabVisited[1]
                    ? _buildTabNavigator(
                        1, _buildFavoritesView(isDesktop: false))
                    : const SizedBox.shrink(),
                _tabVisited[2]
                    ? _buildTabNavigator(
                        2, _buildScheduleView(isDesktop: false))
                    : const SizedBox.shrink(),
              ],
            ),
            bottomNavigationBar: SharedBottomNavBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (idx) {
                if (_selectedIndex == idx) {
                  // Se clicar na mesma aba, volta pro início dela
                  _navigatorKeys[idx].currentState?.popUntil((r) => r.isFirst);
                  if (idx == 2) {
                    _appointmentsKey.currentState?.refreshData();
                  }
                } else {
                  _onTabChanged(idx);
                }
              },
            ),
          ),
        );
      },
    );
  }

  void _onTabChanged(int index) {
    if (index >= 0 && index < _tabVisited.length) {
      if (index == 2) {
        // Força atualização ao entrar na aba de agendamentos
        _appointmentsKey.currentState?.refreshData();
      }
      setState(() {
        _tabVisited[index] = true;
        _selectedIndex = index;
      });
    }
  }

  Widget _buildTabNavigator(int index, Widget child) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => child,
          settings: settings,
        );
      },
    );
  }

  // ============ VIEW: FAVORITOS ============
  Widget _buildFavoritesView({required bool isDesktop}) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      _redirectToLogin();
      return const Center(child: CircularProgressIndicator());
    }
    return SupabaseStreamWidget<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('favorites')
          .stream(primaryKey: ['id'])
          .eq('user_id', uid)
          .order('created_at', ascending: false),
      emptyBuilder: (context) => Center(
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
            Text('Toque no coração nas lojas para adicioná-las aqui',
                style: TextStyle(fontSize: 13, color: Colors.grey[400])),
          ],
        ),
      ),
      builder: (context, favDocs) {
        final shopIds = favDocs.map((d) => d['shop_id'] as String).toList();
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: shopIds.isEmpty
              ? Future.value([])
              : Supabase.instance.client
                  .from('shops')
                  .select()
                  .inFilter('id', shopIds)
                  .then((res) => List<Map<String, dynamic>>.from(res)),
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
            final bool useGrid = MediaQuery.of(context).size.width > 650;
            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.white,
                  elevation: 0,
                  floating: true,
                  toolbarHeight: 50,
                  titleSpacing: 16,
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(1),
                    child: Container(height: 1, color: const Color(0xFFECEEF2)),
                  ),
                  title: Row(children: [
                    const Icon(Icons.favorite_rounded,
                        color: Color(0xFFE53935), size: 20),
                    const SizedBox(width: 8),
                    const Text('Meus Favoritos',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: Color(0xFF1F2937))),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${shops.length}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFE53935))),
                    ),
                  ]),
                ),
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  sliver: useGrid
                      ? SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 420,
                            mainAxisExtent: 94,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 10,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _ShopCard(
                              shop: shops[i],
                              onTap: () {
                                if (shops[i]['is_available'] == false) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          "Loja ainda configurando o perfil e indisponível para agendamentos."),
                                      duration: Duration(seconds: 3),
                                    ),
                                  );
                                  return;
                                }
                                _openShopProfile(shops[i]);
                              },
                              index: i,
                            ),
                            childCount: shops.length,
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _ShopCard(
                                shop: shops[i],
                                onTap: () {
                                  if (shops[i]['is_available'] == false) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            "Loja ainda configurando o perfil e indisponível para agendamentos."),
                                        duration: Duration(seconds: 3),
                                      ),
                                    );
                                    return;
                                  }
                                  _openShopProfile(shops[i]);
                                },
                                index: i,
                              ),
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
    return ListenableBuilder(
      listenable: Listenable.merge(
          [_cidadeNotifier, _searchNotifier, _categoryNotifier]),
      builder: (context, _) {
        final cidade = _cidadeNotifier.value;
        final searchText = _searchNotifier.value;
        final selectedCategory = _categoryNotifier.value;
        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            if (!isDesktop)
              SliverAppBar(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.white,
                elevation: 0,
                floating: true,
                toolbarHeight: 48,
                titleSpacing: 0,
                title: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      // Logo proporcional e clean
                      Image.asset('assets/images/logo_purple.png', height: 28),

                      const SizedBox(width: 10),

                      // Seletor de Cidade em pílula estilo iFood/ML
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: SeletorDeCidadeButton(
                              cidadeSelecionada: cidade,
                              onTap: _mostrarSeletorDeCidade,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      // Perfil Mini compacto (abre BottomSheet de Perfil moderno ao clicar)
                      if (_userId != null)
                        InkWell(
                          onTap: _showProfileBottomSheet,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.primaryPurple
                                          .withValues(alpha: 0.2),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 15,
                                    backgroundColor: const Color(0xFFF3F4F6),
                                    child: _userPhotoUrl != null
                                        ? ClipOval(
                                            child: CachedNetworkImage(
                                              imageUrl: _userPhotoUrl!,
                                              width: 30,
                                              height: 30,
                                              fit: BoxFit.cover,
                                              placeholder: (_, __) => const Icon(
                                                  Icons.person,
                                                  color: Colors.grey,
                                                  size: 16),
                                              errorWidget: (_, __, ___) =>
                                                  const Icon(Icons.person,
                                                      color: Colors.grey,
                                                      size: 16),
                                            ),
                                          )
                                        : const Icon(Icons.person,
                                            color: Colors.grey, size: 16),
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Icon(Icons.keyboard_arrow_down_rounded,
                                    size: 16, color: Colors.grey[600]),
                              ],
                            ),
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.login_rounded,
                              size: 20, color: AppColors.primaryPurple),
                          tooltip: 'Fazer Login',
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LoginPage())),
                        )
                    ],
                  ),
                ),
              ),

            // Bloco Superior Clean: Busca Compacta + Categorias Estilo Marketplace
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFECEEF2), width: 1),
                  ),
                ),
                padding: const EdgeInsets.only(top: 6, bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Barra de busca compacta (estilo iFood/Mercado Livre)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => _searchNotifier.value = v,
                          style: const TextStyle(
                              fontSize: 13.5, color: Color(0xFF1F2937)),
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: "Buscar lojas ou serviços...",
                            hintStyle: TextStyle(
                                fontSize: 13.5, color: Colors.grey[500]),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: AppColors.primaryPurple,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 38,
                              minHeight: 40,
                            ),
                            suffixIcon: searchText.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 16),
                                    padding: EdgeInsets.zero,
                                    onPressed: () {
                                      _searchController.clear();
                                      _searchNotifier.value = '';
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Categorias estilo Mini-Ícones de Vitrine (iFood / ML)
                    SizedBox(
                      height: 68,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _categories.length,
                        itemBuilder: (context, index) {
                          final cat = _categories[index];
                          final String catName = cat['name'];
                          final bool isSelected = selectedCategory == catName;
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: GestureDetector(
                              onTap: () => _categoryNotifier.value = catName,
                              behavior: HitTestBehavior.opaque,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppColors.primaryPurple
                                          : const Color(0xFFF6F3FA),
                                      borderRadius: BorderRadius.circular(13),
                                      border: Border.all(
                                        color: isSelected
                                            ? AppColors.primaryPurple
                                            : AppColors.primaryPurple
                                                .withValues(alpha: 0.08),
                                        width: 1,
                                      ),
                                      boxShadow: isSelected
                                          ? [
                                              BoxShadow(
                                                color: AppColors.primaryPurple
                                                    .withValues(alpha: 0.22),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              )
                                            ]
                                          : null,
                                    ),
                                    child: Center(
                                      child: cat['isAfroComb'] == true
                                          ? AfroCombIcon(
                                              size: 20,
                                              color: isSelected
                                                  ? Colors.white
                                                  : AppColors.primaryPurple
                                                      .withValues(alpha: 0.85),
                                            )
                                          : Icon(
                                              cat['icon'],
                                              size: 20,
                                              color: isSelected
                                                  ? Colors.white
                                                  : AppColors.primaryPurple
                                                      .withValues(alpha: 0.85),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    catName,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? AppColors.primaryPurple
                                          : const Color(0xFF4B5563),
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Carrossel de Banners (Destaques / Avisos)
            SliverToBoxAdapter(
              child: _BoostBannerCarousel(
                cidadeSelecionada: cidade,
                onShopTap: _openShopProfile,
              ),
            ),

            // GRID / LISTA DE LOJAS E VITRINE HORIZONTAL
            FutureBuilder<List<Map<String, dynamic>>>(
              future: cidade == null
                  ? Future.value([])
                  : ShopDataCacheService().getShopsByCity(cidade.cidade),
              builder: (context, snapshot) {
                if (cidade == null) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_searching_rounded,
                              size: 48, color: Colors.grey[350]),
                          const SizedBox(height: 12),
                          Text(
                            'Selecione uma cidade no topo para\nencontrar estabelecimentos próximos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                                height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: AppColors.primaryPurple,
                            strokeWidth: 2.5,
                          ),
                        ),
                      ),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return SliverToBoxAdapter(
                    child: Center(
                        child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Text("Erro ao carregar lojas: ${snapshot.error}",
                          style:
                              const TextStyle(color: Colors.red, fontSize: 13)),
                    )),
                  );
                }

                final shopsRaw = snapshot.data ?? [];

                if (shopsRaw.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 64),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.location_off_outlined,
                                size: 48, color: Colors.grey[350]),
                            const SizedBox(height: 12),
                            Text(
                              'Nenhuma loja encontrada em ${cidade.cidade}.\nTente selecionar outra cidade.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                  height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                final filtered = shopsRaw.where((doc) {
                  final d = doc;
                  final bool isActive = d['is_active'] ?? d['ativo'] ?? true;
                  final int servicesCount = d['services_count'] ?? 0;
                  final String logoUrl =
                      (d['logo_url'] ?? d['logoUrl'] ?? "").toString().trim();

                  if (logoUrl.isEmpty) return false;

                  // Verifica se a loja está apta a receber clientes (ativa e com serviços)
                  d['is_available'] = isActive && servicesCount > 0;

                  // Filtro adicional por estado se houver ambiguidade (opcional)
                  if (cidade.estado.isNotEmpty) {
                    final String shopEstado =
                        (d['state'] ?? d['uf'] ?? '').toString().toUpperCase();

                    if (shopEstado.isNotEmpty) {
                      final sEst = cidade.estado.toUpperCase();
                      final bool isSameAcronym = shopEstado == sEst;

                      // Verifica se são nomes completos ou siglas que coincidem (ex: MG e MINAS GERAIS)
                      final bool containsEachOther =
                          shopEstado.contains(sEst) ||
                              sEst.contains(shopEstado);

                      // Se for diferente, testa as siglas comuns para evitar falso negativo.
                      // Uma validação básica evita remover uma loja correta. Em caso de dúvida, mantemos.
                      if (!isSameAcronym && !containsEachOther) {
                        final Map<String, String> estadosSiglas = {
                          'ACRE': 'AC',
                          'ALAGOAS': 'AL',
                          'AMAPA': 'AP',
                          'AMAPÁ': 'AP',
                          'AMAZONAS': 'AM',
                          'BAHIA': 'BA',
                          'CEARA': 'CE',
                          'CEARÁ': 'CE',
                          'DISTRITO FEDERAL': 'DF',
                          'ESPIRITO SANTO': 'ES',
                          'ESPÍRITO SANTO': 'ES',
                          'GOIAS': 'GO',
                          'GOIÁS': 'GO',
                          'MARANHAO': 'MA',
                          'MARANHÃO': 'MA',
                          'MATO GROSSO': 'MT',
                          'MATO GROSSO DO SUL': 'MS',
                          'MINAS GERAIS': 'MG',
                          'PARA': 'PA',
                          'PARÁ': 'PA',
                          'PARAIBA': 'PB',
                          'PARAÍBA': 'PB',
                          'PARANA': 'PR',
                          'PARANÁ': 'PR',
                          'PERNAMBUCO': 'PE',
                          'PIAUI': 'PI',
                          'PIAUÍ': 'PI',
                          'RIO DE JANEIRO': 'RJ',
                          'RIO GRANDE DO NORTE': 'RN',
                          'RIO GRANDE DO SUL': 'RS',
                          'RONDONIA': 'RO',
                          'RONDÔNIA': 'RO',
                          'RORAIMA': 'RR',
                          'SANTA CATARINA': 'SC',
                          'SAO PAULO': 'SP',
                          'SÃO PAULO': 'SP',
                          'SERGIPE': 'SE',
                          'TOCANTINS': 'TO'
                        };

                        final mappedState = estadosSiglas[shopEstado];
                        final mappedCityState = estadosSiglas[sEst];

                        if ((mappedState != null && mappedState == sEst) ||
                            (mappedCityState != null &&
                                mappedCityState == shopEstado)) {
                          // Match por mapeamento
                        } else {
                          // Se chegou aqui e realmente não bate, descarta.
                          return false;
                        }
                      }
                    }
                  }

                  final String searchLower = searchText.isEmpty
                      ? ""
                      : StringUtils.removeDiacritics(searchText).toLowerCase();
                  final matchesText = searchLower.isEmpty ||
                      StringUtils.removeDiacritics(d['name'] ?? '')
                          .toLowerCase()
                          .contains(searchLower) ||
                      StringUtils.removeDiacritics(d['category'] ?? '')
                          .toLowerCase()
                          .contains(searchLower);

                  if (!matchesText) return false;

                  final matchesCat = selectedCategory == "Todos" ||
                      (() {
                        final rawCategory = (d['category'] ?? d['categoria'] ?? d['nicho'] ?? '').toString();
                        final cats = rawCategory
                            .split(';')
                            .map((c) => StringUtils.removeDiacritics(c.trim().toLowerCase()));
                        final sel = StringUtils.removeDiacritics(selectedCategory.trim().toLowerCase());

                        // Match flexível para Trancistas / Tranças / Especialistas Afro
                        if (sel.startsWith('tranc')) {
                          final nameLower = StringUtils.removeDiacritics((d['name'] ?? '').toString().toLowerCase());
                          return cats.any((c) => c.contains('tranc') || c.contains('afro')) ||
                              nameLower.contains('tranc') ||
                              nameLower.contains('afro');
                        }

                        return cats.any((c) => c.contains(sel) || sel.contains(c));
                      })();

                  return matchesCat && isActive;
                }).toList();

                // 🏆 Ordenação por Qualidade do Perfil (Media)
                filtered.sort((a, b) {
                  final da = a;
                  final db = b;

                  int getScore(Map<String, dynamic> d) {
                    int s = 0;
                    if (d['is_available'] == false) s -= 1000;

                    if ((d['logo_url'] ?? '').toString().isNotEmpty) s += 10;
                    if ((d['image_url'] ?? '').toString().isNotEmpty) s += 10;

                    // ? Verificação de Boost Ativo (com expiração)
                    final expiresStr = d['boost_expires_at']?.toString();
                    final expires = expiresStr != null
                        ? DateTime.tryParse(expiresStr)
                        : null;
                    final bool isBoostActive = d['is_boosted'] == true &&
                        expires != null &&
                        expires.isAfter(DateTime.now());

                    if (isBoostActive) s += 10000;

                    // ? Verificação de Nota Alta (Mesmo critério visual do card)
                    final googleData =
                        d['google_business'] as Map<String, dynamic>?;
                    final double rt = googleData?['rating']?.toDouble() ??
                        (d['rating']?.toDouble() ?? 0.0);
                    if (rt >= 4.5) s += 50;

                    return s;
                  }

                  return getScore(db).compareTo(getScore(da));
                });

                if (filtered.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 48),
                      child: Center(
                        child: Text(
                          "Nenhuma loja encontrada para este filtro.",
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 13.5),
                        ),
                      ),
                    ),
                  );
                }

                final bool useGrid = MediaQuery.of(context).size.width > 650;
                final now = DateTime.now();
                final availableFeatured = filtered.where((s) {
                  if (s['is_available'] == false) return false;
                  final expiresStr = s['boost_expires_at']?.toString();
                  final expires =
                      expiresStr != null ? DateTime.tryParse(expiresStr) : null;
                  return s['is_boosted'] == true &&
                      expires != null &&
                      expires.isAfter(now);
                }).take(8).toList();
                final bool showHorizontalHighlights = searchText.isEmpty &&
                    selectedCategory == "Todos" &&
                    availableFeatured.isNotEmpty;

                return SliverMainAxisGroup(
                  slivers: [
                    // Vitrine Horizontal "Destaques na região" (Estilo "Famosos no iFood")
                    if (showHorizontalHighlights)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 14, bottom: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  children: [
                                    const Text(
                                      "Destaques na região",
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.2,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 14,
                                      color: AppColors.primaryPurple
                                          .withValues(alpha: 0.8),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 112,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16),
                                  itemCount: availableFeatured.length,
                                  itemBuilder: (ctx, idx) {
                                    final fShop = availableFeatured[idx];
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 10),
                                      child: _MiniShopHighlightCard(
                                        shop: fShop,
                                        onTap: () => _openShopProfile(fShop),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    // Cabeçalho da lista principal
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              searchText.isEmpty
                                  ? (selectedCategory == "Todos"
                                      ? "Lojas disponíveis"
                                      : selectedCategory)
                                  : "Resultados da busca",
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            Text(
                              "${filtered.length} ${filtered.length == 1 ? 'local' : 'locais'}",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Lista / Grid de Lojas
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                      sliver: useGrid
                          ? SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 420,
                                mainAxisExtent: 94,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 10,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final shop = filtered[index];
                                  return _ShopCard(
                                    shop: shop,
                                    onTap: () {
                                      if (shop['is_available'] == false) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                                "Loja ainda configurando o perfil e indisponível para agendamentos."),
                                            duration: Duration(seconds: 3),
                                          ),
                                        );
                                        return;
                                      }
                                      _openShopProfile(shop);
                                    },
                                    index: index,
                                  );
                                },
                                childCount: filtered.length,
                              ),
                            )
                          : SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final shop = filtered[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _ShopCard(
                                      shop: shop,
                                      onTap: () {
                                        if (shop['is_available'] == false) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  "Loja ainda configurando o perfil e indisponível para agendamentos."),
                                              duration: Duration(seconds: 3),
                                            ),
                                          );
                                          return;
                                        }
                                        _openShopProfile(shop);
                                      },
                                      index: index,
                                    ),
                                  );
                                },
                                childCount: filtered.length,
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        );
      },
    );
  }

  // ============ VIEW: AGENDA ============
  Widget _buildScheduleView({required bool isDesktop}) {
    return MyAppointmentsPage(key: _appointmentsKey);
  }

  // --- DESKTOP WIDGETS ---
  Widget _buildSideMenuDesktop() {
    return Container(
      width: 220,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFECEEF2), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Image.asset('assets/images/logo_purple.png', height: 28),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _menuItemDesktop(0, Icons.explore_outlined, "Explorar"),
          _menuItemDesktop(1, Icons.favorite_border_rounded, "Favoritos"),
          _menuItemDesktop(2, Icons.calendar_today_outlined, "Minha Agenda"),
          const Spacer(),
          const Divider(color: Color(0xFFECEEF2)),
        ],
      ),
    );
  }

  Widget _menuItemDesktop(int idx, IconData icon, String lbl) {
    bool isSelected = _selectedIndex == idx;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primaryPurple.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Icon(icon,
            size: 20,
            color:
                isSelected ? AppColors.primaryPurple : const Color(0xFF6B7280)),
        title: Text(lbl,
            style: TextStyle(
                fontSize: 13.5,
                color: isSelected
                    ? AppColors.primaryPurple
                    : const Color(0xFF374151),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
        onTap: () => _onTabChanged(idx),
      ),
    );
  }

  Widget _buildHeaderDesktop() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFECEEF2), width: 1)),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                    _selectedIndex == 0
                        ? "Explorar"
                        : _selectedIndex == 1
                            ? "Meus Favoritos"
                            : "Minha Agenda",
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: Color(0xFF1F2937))),
                if (_selectedIndex == 0) ...[
                  const SizedBox(width: 16),
                  ValueListenableBuilder<CidadeSelecionada?>(
                    valueListenable: _cidadeNotifier,
                    builder: (_, cidade, __) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: SeletorDeCidadeButton(
                        cidadeSelecionada: cidade,
                        onTap: _mostrarSeletorDeCidade,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_userId != null)
            InkWell(
              onTap: _showProfileBottomSheet,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFFF3F4F6),
                      backgroundImage: _userPhotoUrl != null
                          ? CachedNetworkImageProvider(_userPhotoUrl!)
                          : null,
                      child: (_userPhotoUrl == null)
                          ? const Icon(Icons.person, size: 18, color: Colors.grey)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _userName.isNotEmpty ? _userName.split(' ').first : 'Perfil',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 16, color: Colors.grey),
                  ],
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const LoginPage())),
              icon: const Icon(Icons.login_rounded,
                  size: 17, color: AppColors.primaryPurple),
              label: const Text('Fazer Login',
                  style: TextStyle(
                      color: AppColors.primaryPurple,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5)),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// ?? COMPONENTES VISUAIS (DESIGN SYSTEM CLEAN MARKETPLACE)
// =============================================================================

/// Mini-card vertical compacto para a vitrine horizontal "Destaques na região" (estilo "Famosos no iFood")
class _MiniShopHighlightCard extends StatelessWidget {
  final Map<String, dynamic> shop;
  final VoidCallback onTap;

  const _MiniShopHighlightCard({required this.shop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final String name = (shop['name'] ?? shop['nome'] ?? 'Loja').toString();
    final String logoUrl =
        (shop['logo_url'] ?? shop['logoUrl'] ?? '').toString();
    final String rawCat =
        (shop['category'] ?? shop['categoria'] ?? shop['nicho'] ?? 'Serviços')
            .toString();
    final String primaryCat = rawCat.split(';').first.trim();

    final expiresStr = shop['boost_expires_at']?.toString();
    final expires = expiresStr != null ? DateTime.tryParse(expiresStr) : null;
    final bool isBoostActive = shop['is_boosted'] == true &&
        expires != null &&
        expires.isAfter(DateTime.now());

    final googleData = shop['google_business'] as Map<String, dynamic>?;
    final double rating = googleData?['rating']?.toDouble() ??
        (shop['rating']?.toDouble() ?? 5.0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 96,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isBoostActive
                ? const Color(0xFFFFD700).withValues(alpha: 0.6)
                : const Color(0xFFECEEF2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  padding: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isBoostActive
                          ? const Color(0xFFF59E0B)
                          : AppColors.primaryPurple.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                  ),
                  child: ClipOval(
                    child: logoUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: logoUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                Container(color: const Color(0xFFF3F4F6)),
                            errorWidget: (_, __, ___) => Container(
                              color: const Color(0xFFF3F4F6),
                              child: const Icon(Icons.storefront_rounded,
                                  size: 20, color: Colors.grey),
                            ),
                          )
                        : Container(
                            color: const Color(0xFFF3F4F6),
                            child: const Icon(Icons.storefront_rounded,
                                size: 20, color: Colors.grey),
                          ),
                  ),
                ),
                Positioned(
                  bottom: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: const Color(0xFFECEEF2), width: 1),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 10, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 2),
                        Text(
                          rating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              name,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
                letterSpacing: -0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 1),
            Text(
              primaryCat,
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF6B7280),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopCard extends StatefulWidget {
  final Map<String, dynamic> shop;
  final VoidCallback onTap;
  final int index;

  const _ShopCard({required this.shop, required this.onTap, this.index = 0});

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
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _loadingFav = false);
      return;
    }
    final doc = await Supabase.instance.client
        .from('favorites')
        .select()
        .eq('user_id', uid)
        .eq('shop_id', widget.shop['id'])
        .maybeSingle();
    if (mounted) {
      setState(() {
        _isFavorite = doc != null;
        _loadingFav = false;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _isFavorite = !_isFavorite);
    try {
      if (_isFavorite) {
        await Supabase.instance.client.from('favorites').insert({
          'user_id': uid,
          'shop_id': widget.shop['id'],
          'created_at': DateTime.now().toIso8601String(),
        });
      } else {
        await Supabase.instance.client
            .from('favorites')
            .delete()
            .eq('user_id', uid)
            .eq('shop_id', widget.shop['id']);
      }
    } catch (_) {
      if (mounted) setState(() => _isFavorite = !_isFavorite);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.shop;
    final logoUrl = (data['logo_url'] ?? data['logoUrl'] ?? "").toString();
    final rawCategory =
        (data['category'] ?? data['categoria'] ?? data['nicho'] ?? 'Outros')
            .toString();

    // Formata categorias separadas por ';' de forma limpa (ex: "Beleza · Estética")
    final formattedCategory = rawCategory
        .split(';')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .take(2)
        .join(' · ');

    // Bairro ou cidade curta opcional para compor a linha estilo iFood
    final String neighborhood = (data['neighborhood'] ??
            data['bairro'] ??
            (data['endereco'] is Map ? data['endereco']['bairro'] : '') ??
            '')
        .toString()
        .trim();

    final expiresStr = data['boost_expires_at']?.toString();
    final expires = expiresStr != null ? DateTime.tryParse(expiresStr) : null;
    final bool isBoostActive = data['is_boosted'] == true &&
        expires != null &&
        expires.isAfter(DateTime.now());

    final Color fallbackColor = ShopCategoryHelper.getCatColor(rawCategory);
    final IconData fallbackIcon = ShopCategoryHelper.getCatIcon(rawCategory);

    final isAvailable = data['is_available'] ?? true;

    final googleData = data['google_business'] as Map<String, dynamic>?;
    final double rating = googleData?['rating']?.toDouble() ??
        (data['rating']?.toDouble() ?? 5.0);
    final int? totalReviews = googleData?['user_ratings_total'];

    Widget cardContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isBoostActive
              ? AppColors.primaryPurple.withValues(alpha: 0.22)
              : const Color(0xFFECEEF2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // AVATAR / LOGO COMPACTO (54x54) COM BORDA SUTIL
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isBoostActive
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                    : const Color(0xFFF0F0F0),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: logoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: logoUrl,
                      fit: BoxFit.cover,
                      placeholder: (c, u) =>
                          Container(color: const Color(0xFFF3F4F6)),
                      errorWidget: (c, u, e) => Container(
                        color: fallbackColor,
                        child: Icon(fallbackIcon,
                            color: Colors.grey[400], size: 24),
                      ),
                    )
                  : PexelsImageWidget(
                      searchQuery:
                          ShopImageKeywords.getEnglishKeyword(rawCategory),
                      index: widget.index,
                    ),
            ),
          ),
          const SizedBox(width: 12),

          // CONTEÚDO ESTILO IFOOD / MERCADO LIVRE (ALTA DENSIDADE E LIMPEZA)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Linha 1: Nome da Loja + Botão Favoritar
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              data['name'] ?? data['nome'] ?? "Loja",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14.5,
                                color: Color(0xFF1F2937),
                                letterSpacing: -0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isBoostActive) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: AppColors.primaryPurple,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _toggleFavorite,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          _isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 18,
                          color: _isFavorite
                              ? const Color(0xFFE53935)
                              : const Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 3),

                // Linha 2: Nota • Categoria • Bairro (tudo em 1 linha compacta)
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 3),
                    Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFD97706),
                      ),
                    ),
                    if (totalReviews != null && totalReviews > 0) ...[
                      const SizedBox(width: 2),
                      Text(
                        "($totalReviews)",
                        style: const TextStyle(
                            fontSize: 11.5, color: Color(0xFF9CA3AF)),
                      ),
                    ],
                    const Text(
                      "  •  ",
                      style: TextStyle(fontSize: 11, color: Color(0xFFD1D5DB)),
                    ),
                    Expanded(
                      child: Text(
                        neighborhood.isNotEmpty
                            ? "$formattedCategory  •  $neighborhood"
                            : formattedCategory,
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // Linha 3: Micro-tags de status / valor agregado
                if (!isAvailable)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      "Configurando perfil",
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      if (isBoostActive) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: const Color(0xFFFFE082), width: 0.8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt_rounded,
                                  size: 11, color: Color(0xFFD97706)),
                              SizedBox(width: 2),
                              Text(
                                "Destaque",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              AppColors.primaryPurple.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_today_rounded,
                              size: 9.5,
                              color: AppColors.primaryPurple
                                  .withValues(alpha: 0.85),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "Agendamento online",
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: AppColors.primaryPurple
                                    .withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // Seta discreta à direita indicando ação (estilo lista clean)
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: Colors.grey[350],
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: widget.onTap,
      child: isAvailable
          ? cardContent
          : ColorFiltered(
              colorFilter: const ColorFilter.matrix(<double>[
                0.2126,
                0.7152,
                0.0722,
                0,
                0,
                0.2126,
                0.7152,
                0.0722,
                0,
                0,
                0.2126,
                0.7152,
                0.0722,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
              ]),
              child: cardContent,
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

  Map<String, dynamic>? _shopDoc;
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
        final doc = await Supabase.instance.client
            .from('shops')
            .select()
            .eq('id', shopId)
            .maybeSingle();
        if (doc != null) {
          _shopDoc = doc;
          final config = doc['config'] as Map<String, dynamic>?;
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

    final shopData = _shopDoc!;
    final phone =
        shopData['phone'] ?? shopData['whatsapp'] ?? shopData['telefone'];
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

    final String serviceName =
        widget.serviceData['name'] ?? widget.serviceData['nome'] ?? 'Serviço';
    final String shopName = shopData['name'] ?? shopData['nome'] ?? 'loja';
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
    dynamic rawFotos = sData['photos_urls'] ??
        sData['fotos_urls'] ??
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
  final void Function(Map<String, dynamic>) onShopTap;

  const _BoostBannerCarousel({
    required this.cidadeSelecionada,
    required this.onShopTap,
  });

  @override
  State<_BoostBannerCarousel> createState() => _BoostBannerCarouselState();
}

class _BoostBannerCarouselState extends State<_BoostBannerCarousel> {
  final PageController _pageCtrl = PageController(viewportFraction: 1.0);
  int _currentPage = 0;
  Timer? _autoScrollTimer;
  List<Map<String, dynamic>> _slides = [];
  final Set<String> _impressedBannerIds =
      {}; // evita contar impressão dupla por sessão

  @override
  void initState() {
    super.initState();
    _loadAndSetSlides();
  }

  @override
  void didUpdateWidget(_BoostBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cidadeSelecionada?.cidade !=
        widget.cidadeSelecionada?.cidade) {
      _loadAndSetSlides();
    }
  }

  Future<void> _loadAndSetSlides() async {
    final slides = await _fetchSlides();
    if (!mounted) return;
    setState(() => _slides = slides);
    _startAutoScroll(slides.length);
  }

  Future<List<Map<String, dynamic>>> _fetchSlides() async {
    final now = DateTime.now();
    final selectedCityNorm = widget.cidadeSelecionada != null
        ? StringUtils.removeDiacritics(widget.cidadeSelecionada!.cidade)
            .toLowerCase()
        : null;

    // 1. Busca banners fixos do admin (MarkaAI)
    List<Map<String, dynamic>> banners = [];
    try {
      final raw = await Supabase.instance.client
          .from('app_banners')
          .select()
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      banners = List<Map<String, dynamic>>.from(raw)
          .map((d) => {...d, '_slide_type': 'marka'})
          .toList();
    } catch (e) {
      debugPrint('[Carousel] erro ao buscar app_banners: $e');
    }

    // 2. Busca lojas em Destaque (Impulsionadas ou Nota Alta)
    List<Map<String, dynamic>> highlights = [];
    if (selectedCityNorm != null) {
      try {
        // ? OTIMIZAÇÃO: Usamos o cache service de cidade para evitar múltiplas chamadas ao Supabase
        // Como a lista já carrega esses dados, o cache estará quente.
        final raw = await ShopDataCacheService()
            .getShopsByCity(widget.cidadeSelecionada!.cidade);

        highlights = List<Map<String, dynamic>>.from(raw)
            .where((d) {
              final bool isActive = d['is_active'] ?? d['ativo'] ?? true;
              if (!isActive) return false;

              // Filtro de Cidade
              String cityRaw = (d['city'] ?? d['cidade'] ?? '').toString();
              if (cityRaw.isEmpty && d['endereco'] is Map) {
                final em = d['endereco'] as Map;
                cityRaw = (em['cidade'] ?? em['city'] ?? '').toString();
              }
              final cityNorm =
                  StringUtils.removeDiacritics(cityRaw).toLowerCase();
              if (cityNorm != selectedCityNorm) return false;

              // ? Critério de Destaque: Apenas Boost Ativo (pago)
              final expiresStr = d['boost_expires_at']?.toString();
              final expires =
                  expiresStr != null ? DateTime.tryParse(expiresStr) : null;
              final bool isBoostActive = d['is_boosted'] == true &&
                  expires != null &&
                  expires.isAfter(now);

              return isBoostActive;
            })
            .map((d) => {...d, '_slide_type': 'shop'})
            .toList();

        // Ordenação preferencial: primeiro impulsionados, depois nota
        highlights.sort((a, b) {
          final expA = a['boost_expires_at'] != null
              ? DateTime.tryParse(a['boost_expires_at'])
              : null;
          final bstA =
              a['is_boosted'] == true && (expA == null || expA.isAfter(now));

          final expB = b['boost_expires_at'] != null
              ? DateTime.tryParse(b['boost_expires_at'])
              : null;
          final bstB =
              b['is_boosted'] == true && (expB == null || expB.isAfter(now));

          if (bstA && !bstB) return -1;
          if (!bstA && bstB) return 1;
          return 0;
        });

        // Limita a 12 destaques no banner para não poluir
        if (highlights.length > 12) highlights = highlights.sublist(0, 12);
      } catch (e) {
        debugPrint('[Carousel] erro ao buscar destaques: $e');
      }
    }

    return [...highlights, ...banners];
  }

  // ── Tracking ─────────────────────────────────────────────────────────────

  /// Registra uma impressão para banners do tipo 'marka' (apenas uma vez por sessão por banner)
  void _trackImpression(String bannerId) {
    if (_impressedBannerIds.contains(bannerId)) return;
    _impressedBannerIds.add(bannerId);
    _insertBannerEvent(bannerId, 'impression');
  }

  /// Registra um clique para banners do tipo 'marka'
  void _trackClick(String bannerId) {
    _insertBannerEvent(bannerId, 'click');
  }

  /// Insere o evento na tabela banner_events (fire-and-forget — não bloqueia a UI)
  void _insertBannerEvent(String bannerId, String eventType) {
    Supabase.instance.client
        .from('banner_events')
        .insert({
          'banner_id': bannerId,
          'event_type': eventType,
          'platform': 'mobile'
        })
        .then((_) {})
        .catchError((e) {
          debugPrint('[BannerTracking] erro ao registrar $eventType: $e');
        });
  }

  // ─────────────────────────────────────────────────────────────────────────

  void _startAutoScroll(int count) {
    _autoScrollTimer?.cancel();
    if (count <= 1) return;
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageCtrl.hasClients) return;
      final next = (_currentPage + 1) % count;
      _pageCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Widget _buildShopSlide(Map<String, dynamic> d) {
    final img =
        (d['image_url'] ?? d['imageUrl'] ?? d['coverUrl'] ?? '').toString();
    final nome = (d['name'] ?? d['nome'] ?? '').toString();
    final rawCat =
        (d['category'] ?? d['categoria'] ?? d['nicho'] ?? '').toString();
    final cat = rawCat
        .split(';')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .take(2)
        .join(' · ');
    final logo = (d['logo_url'] ?? d['logoUrl'] ?? '').toString();
    return GestureDetector(
      onTap: () => widget.onShopTap(d),
      child: Stack(fit: StackFit.expand, children: [
        if (img.isNotEmpty)
          CachedNetworkImage(
            imageUrl: img,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(color: AppColors.deepPurple),
          )
        else
          Container(color: AppColors.deepPurple),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x11000000), Color(0xCC181028)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.6),
                width: 0.8,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt_rounded, size: 11, color: Color(0xFFFFD700)),
                SizedBox(width: 3),
                Text('DESTAQUE',
                    style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.5)),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 10,
          left: 12,
          right: 12,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (logo.isNotEmpty)
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: ClipOval(
                    child:
                        CachedNetworkImage(imageUrl: logo, fit: BoxFit.cover),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(nome,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (cat.isNotEmpty)
                      Text(cat,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4), width: 0.8),
                ),
                child: const Text('Ver loja',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _buildMarkaBannerSlide(Map<String, dynamic> banner) {
    final title = (banner['title'] ?? 'MarkaAI').toString();
    final subtitle = (banner['subtitle'] ?? '').toString();
    final ctaText = (banner['cta_text'] ?? 'Saiba mais').toString();
    final ctaUrl = (banner['cta_url'] ?? '').toString();
    final imgUrl = (banner['image_url'] ?? '').toString();
    return GestureDetector(
      onTap: () async {
        // Tracking de clique
        final bannerId = banner['id']?.toString() ?? '';
        if (bannerId.isNotEmpty) _trackClick(bannerId);

        if (ctaUrl.isNotEmpty) {
          final uri = Uri.tryParse(ctaUrl);
          if (uri != null) {
            try {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } catch (_) {}
          }
        }
      },
      child: Stack(fit: StackFit.expand, children: [
        // Imagem de fundo (quando fornecida via admin)
        if (imgUrl.isNotEmpty)
          CachedNetworkImage(
            imageUrl: imgUrl,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const SizedBox(),
          ),
        // Sem overlay, pois os banners comerciais devem exibir a imagem pura.
        // Logo branco centralizado (somente quando não há imagem de fundo)
        if (imgUrl.isEmpty)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Image.asset(
                'assets/images/logo_white.png',
                height: 30,
                fit: BoxFit.contain,
              ),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_slides.isEmpty) {
      return const SizedBox.shrink();
    }

    final bool isDesktop = MediaQuery.of(context).size.width > 900;

    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          height: isDesktop ? 175 : 116,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: _slides.length,
              onPageChanged: (p) => setState(() => _currentPage = p),
              itemBuilder: (ctx, i) {
                final slide = _slides[i];
                if (slide['_slide_type'] == 'marka') {
                  // Registra impressão ao renderizar o slide de banner pago
                  final bid = slide['id']?.toString() ?? '';
                  if (bid.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _trackImpression(bid);
                    });
                  }
                  return _buildMarkaBannerSlide(slide);
                }
                return _buildShopSlide(slide);
              },
            ),
          ),
        ),
        if (_slides.length > 1) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_slides.length, (i) {
              final active = i == _currentPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: active ? 14 : 4,
                height: 4,
                decoration: BoxDecoration(
                  color: active ? AppColors.primaryPurple : Colors.grey[350],
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}
