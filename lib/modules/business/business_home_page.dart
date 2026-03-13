// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'catalog_import_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_application_1/modules/business/store_profile_page.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'package:google_sign_in/google_sign_in.dart';
import 'business_history_page.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/widgets/splash_loading_widget.dart';
import 'boost_shop_page.dart';
import '../admin/admin_dashboard_page.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/notification_service.dart';
import '../../core/widgets/trial_banner_widget.dart';
import '../../core/widgets/banner_ad_widget.dart';
import '../../core/constants/plan_features.dart';
import '../../core/services/plan_features_service.dart';
import '../../widgets/upgrade_modal.dart';
import '../../core/services/session_service.dart';
import '../login/login_page.dart';

// --- MÓDULOS ---
import '../services/services_management_page.dart';
import '../team/team_management_page.dart';
import 'business_settings_page.dart';
import 'business_schedule_page.dart';
import 'business_clients_page.dart';
// import '../settings/excel_import_page.dart'; // Import removed  recurso 'Importar Dados' descontinuado
import '../financial/financial_dashboard_page.dart';
// import 'financial_wallet_page.dart';
import 'coupons/manage_coupons_page.dart';

import 'subscription_plans_page.dart';
import '../../modules/inventory/inventory_home_page.dart';
import 'subscription_service.dart';
import '../help/help_guide_page.dart';
import 'price_adjustment_page.dart';
import '../../pages/privacy_settings_page.dart';

class BusinessHomePage extends StatefulWidget {
  const BusinessHomePage({super.key});

  @override
  State<BusinessHomePage> createState() => _BusinessHomePageState();
}

class _BusinessHomePageState extends State<BusinessHomePage> {
  int _selectedIndex = 1;

  String? shopId;
  String userName = "Profissional";
  String userEmail = "";
  String? userPhotoUrl;

  String shopName = "MarkaAI Painel";
  String? shopLogoUrl;
  String? shopImageUrl;

  bool _isLoading = true;
  // --- MOBILE AGENDA STATE ---
  List<DocumentSnapshot> _mobileAppointments = [];
  DocumentSnapshot? _mobileLastDoc;
  DocumentSnapshot? _mobileFirstDoc;
  bool _mobileHasMore = true;
  bool _mobileLoading = false;
  final ScrollController _mobileScrollController = ScrollController();
  final int _mobilePerPage = 20;
  bool _mobileInitialized = false;
  bool _mobilePastHasMore = true;
  GlobalKey? _mobileTodayHeaderKey;

  int _selectedYear =
      DateTime.now().year; // Comea com o ano atual para economizar
  // Lista inicial apenas com o ano atual, ser populada dinamicamente se necessrio
  List<int> _availableYears = [DateTime.now().year];

  // Indices bloqueados para o plano atual
  List<int> _restrictedIndices = [];
  List<int> _hiddenIndices = []; // Indices que nem aparecem no menu
  bool _canViewCommissions = false;

  SubscriptionPlan _currentPlanCode = SubscriptionPlan.free;
  bool _isTrial = false;
  bool _isAdmin = false;
  PlanFeatures _currentFeatures = planFeaturesConfig[PlanKey.free]!;

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

  // --- MOBILE APPOINTMENTS (infinite scroll, chronological) ---
  Future<void> _initMobileAppointmentsOnce() async {
    if (_mobileInitialized) return;
    _mobileInitialized = true;
    _mobileScrollController.addListener(() {
      // load more future when near bottom
      if (_mobileScrollController.position.pixels >=
          _mobileScrollController.position.maxScrollExtent * 0.9) {
        _loadMoreMobileAppointments();
      }
      // load more past when near top
      if (_mobileScrollController.position.pixels <= 200) {
        _loadMorePastAppointments();
      }
    });
    await _loadMobileAppointmentsInitial();
  }

  Future<void> _loadMobileAppointmentsInitial() async {
    if (_mobileLoading || shopId == null) return;
    setState(() {
      _mobileLoading = true;
      _mobileAppointments = [];
      _mobileLastDoc = null;
      _mobileHasMore = true;
      _mobilePastHasMore = true;
    });
    try {
      // Default initial behavior: start from today (most relevant) and show future appointments ascending.
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day, 0, 0, 0);
      // fetch a reasonable window around today to populate multiple days (avoid single-day-only view)
      final windowStart = startOfToday.subtract(const Duration(days: 7));
      final windowEnd = startOfToday.add(const Duration(days: 14));

      Query windowQuery = FirebaseFirestore.instance
          .collection('appointments')
          .where('shopId', isEqualTo: shopId)
          .where('data_agendamento',
              isGreaterThanOrEqualTo: Timestamp.fromDate(windowStart))
          .where('data_agendamento',
              isLessThanOrEqualTo: Timestamp.fromDate(windowEnd))
          .orderBy('data_agendamento', descending: false)
          .limit(100);

      final windowSnap = await windowQuery.get();
      final combined = windowSnap.docs;

      // Estimate hasMore flags based on edges
      _mobileHasMore =
          combined.isNotEmpty && (combined.length >= 100) ? true : true;
      _mobilePastHasMore = true;

      if (mounted) {
        setState(() {
          _mobileAppointments = combined;
          if (combined.isNotEmpty) {
            _mobileFirstDoc = combined.first;
            _mobileLastDoc = combined.last;
          }
          // prepare a key for today's header to scroll to it after build
          _mobileTodayHeaderKey = GlobalKey();
        });

        // ensure today's header visible
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            if (_mobileTodayHeaderKey?.currentContext != null) {
              Scrollable.ensureVisible(_mobileTodayHeaderKey!.currentContext!,
                  duration: const Duration(milliseconds: 300), alignment: 0.1);
            }
          } catch (e) {
            // ignore
          }
        });
      }
    } catch (e) {
      debugPrint("Erro carregar mobile appointments: $e");
    } finally {
      if (mounted) setState(() => _mobileLoading = false);
    }
  }

  Future<void> _loadMorePastAppointments() async {
    if (_mobileLoading ||
        !_mobilePastHasMore ||
        shopId == null ||
        _mobileFirstDoc == null) {
      return;
    }
    setState(() {
      _mobileLoading = true;
    });
    try {
      final firstDate = (_mobileFirstDoc!.data()
          as Map<String, dynamic>)['data_agendamento'] as Timestamp;
      Query query = FirebaseFirestore.instance
          .collection('appointments')
          .where('shopId', isEqualTo: shopId)
          .where('data_agendamento', isLessThan: firstDate)
          .orderBy('data_agendamento', descending: true)
          .limit(_mobilePerPage);
      final snap = await query.get();
      if (mounted) {
        final newDocs = snap.docs.reversed.toList();
        setState(() {
          _mobileAppointments = [...newDocs, ..._mobileAppointments];
          if (newDocs.isNotEmpty) _mobileFirstDoc = newDocs.first;
          if (snap.docs.length < _mobilePerPage) _mobilePastHasMore = false;
        });
      }
    } catch (e) {
      debugPrint("Erro carregar mais past mobile appointments: $e");
    } finally {
      if (mounted) setState(() => _mobileLoading = false);
    }
  }

  Future<void> _loadMoreMobileAppointments() async {
    if (_mobileLoading ||
        !_mobileHasMore ||
        shopId == null ||
        _mobileLastDoc == null) {
      return;
    }
    setState(() {
      _mobileLoading = true;
    });
    try {
      Query query = FirebaseFirestore.instance
          .collection('appointments')
          .where('shopId', isEqualTo: shopId)
          .orderBy('data_agendamento', descending: false)
          .startAfterDocument(_mobileLastDoc!)
          .limit(_mobilePerPage);
      final snap = await query.get();
      if (mounted) {
        setState(() {
          if (snap.docs.isNotEmpty) {
            _mobileLastDoc = snap.docs.last;
            _mobileAppointments.addAll(snap.docs);
          }
          if (snap.docs.length < _mobilePerPage) _mobileHasMore = false;
        });
      }
    } catch (e) {
      debugPrint("Erro carregar mais mobile appointments: $e");
    } finally {
      if (mounted) setState(() => _mobileLoading = false);
    }
  }

  Future<void> _checkBusinessAndLoad() async {
    try {
      final id = await SessionService.getShopId();
      final sessionUserId = await SessionService.getUserId();
      final user = FirebaseAuth.instance.currentUser;

      // Prioritize session ID (for linked accounts via email)
      final effectiveUid = sessionUserId ?? user?.uid;

      if (effectiveUid == null) {
        _forceLogout();
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(effectiveUid)
          .get();

      if (!userDoc.exists) {
        _forceLogout();
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      String tipo = userData['tipo'] ?? 'cliente';
      
      // Trust the user document first, then session (consistently with recent backend changes)
      String currentShopId = userData['shopId'] ?? id ?? "";

      final roles = userData['roles'] as List?;
      final role = userData['role'] as String?;
      final isAdmin = role == 'admin' || 
                      (roles?.contains('admin') ?? false) || 
                      userData['is_admin_dev'] == true;

      if (tipo != 'dono' && tipo != 'business' && !isAdmin) {
        _forceLogout();
        return;
      }

      if (currentShopId.isEmpty) {
        _forceLogout();
        return;
      }

      // Tenta buscar anos disponveis (opcional, para popular o dropdown)
      // Para economizar, podemos manter fixo ou fazer uma query leve de agregao futuramente
      // Por enquanto, vou gerar de 2024 at o ano atual + 1
      final currentYear = DateTime.now().year;
      _availableYears = List.generate(5, (index) => (currentYear - 2) + index);

      // Save the identified shopId to session to ensure all sub-pages can access it
      if (currentShopId.isNotEmpty) {
        await SessionService.saveShopId(currentShopId);
      }

      if (mounted) {
        setState(() {
          shopId = currentShopId;
          userName = userData['nome'] ?? "Profissional";
          userEmail = user?.email ?? "";
          userPhotoUrl = user?.photoURL;
          
          // Note: _currentFeatures will be updated via the StreamBuilder on shops collection below
          
          // Check admin status across different possible schemas
          final roles = userData['roles'] as List?;
          final role = userData['role'] as String?;
          final isAdminDev = userData['is_admin_dev'] == true;
          
          _isAdmin = role == 'admin' || 
                      (roles?.contains('admin') ?? false) || 
                      isAdminDev;
                      
          _isLoading = false;
        });

        // Verificar restrições do plano
        _checkPlanRestrictions();

        // ðŸ”” Inicializar notificações push para o dono da loja
        NotificationService.initialize().then((_) {
          debugPrint('âœ… Notificações inicializadas para o dono da loja');
        }).catchError((e) {
          debugPrint('âŒ Erro ao inicializar notificações: $e');
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
    // Remover token FCM, limpar sessão local e desconectar providers (Google)
    try {
      await NotificationService.removeToken();
    } catch (_) {}

    try {
      // Limpa preferências locais da sessão
      await SessionService.logout();
    } catch (_) {}

    try {
      // Garantir que o GoogleSignIn não mantenha sessão automática
      await GoogleSignIn().signOut();
      await GoogleSignIn().disconnect();
    } catch (_) {}

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  Future<void> _checkPlanRestrictions() async {
    // This method is now effectively handled by the StreamBuilder in the build method
    // to ensure instantaneous updates when plan changes.
    if (shopId != null) {
      final doc = await FirebaseFirestore.instance.collection('shops').doc(shopId).get();
      if (doc.exists) {
        if (mounted) {
          setState(() {
            _updateFeaturesFromData(doc.data());
          });
        }
      }
    }
  }

  void _updateFeaturesFromData(Map<String, dynamic>? data) {
    if (data == null) return;
    
    // 1. Detectar Plano e Trial de forma centralizada
    final detection = PlanFeaturesService.detectPlan(data);
    _currentPlanCode = detection['plan'];
    _isTrial = detection['trial'];
    
    _currentFeatures = PlanFeaturesService.getFeaturesForShop(data);
    
    _restrictedIndices = [];
    _hiddenIndices = [];

    // Estoque (Índice 7)
    if (!_currentFeatures.stockManagement) {
      _restrictedIndices.add(7);
    }

    // Financeiro (Índice 5)
    if (!_currentFeatures.financialTab || !_currentFeatures.financialDashboard) {
      _restrictedIndices.add(5);
    }

    // Reajuste de Valores (Índice 9)
    if (!_currentFeatures.automaticPriceAdjustment) {
      _restrictedIndices.add(9);
    }

    // Comissões
    _canViewCommissions = _currentFeatures.commissionView;
  }

  void _showUpgradeDialog(String feature) {
    UpgradeModal.show(context, featureName: feature, requiredPlan: 'Plus');
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
              "Tem certeza que deseja sair do painel?\nVocê precisará fazer login novamente.",
              textAlign: TextAlign.left,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
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
                  _forceLogout();
                },
              ),
            ),
            const SizedBox(height: 10),
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

  // --- MENU ACTIONS ---
  Future<void> _handleMenuAction(String value) async {
    switch (value) {
      case 'perfil':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => StoreProfilePage()));
        break;
      case 'assinatura':
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SubscriptionPlansPage()));
        // No need for _checkBusinessAndLoad() here anymore as StreamBuilder handles it
        break;
      case 'importar':
        // Importar legado removido — mantido para compatibilidade
        break;
      case 'catalogo_import':
        if (kIsWeb) {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const CatalogImportPage()));
        }
        break;
      case 'sair':
        _confirmLogout();
        break;
      case 'impulsionar':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const BoostShopPage()));
        break;
      case 'admin':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AdminDashboardPage()));
        break;
      case 'ajuda':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const HelpGuidePage(),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SplashLoadingWidget(
        message: "Carregando seu painel...",
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: shopId != null
          ? FirebaseFirestore.instance
              .collection('shops')
              .doc(shopId)
              .snapshots()
          : null,
      builder: (context, snapshot) {

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          shopName = data['nome'] ?? "Meu Negócio";

          shopLogoUrl =
              (data['logoUrl'] != null && data['logoUrl'].toString().isNotEmpty)
                  ? data['logoUrl']
                  : data['foto'];

          shopImageUrl = (data['imageUrl'] != null &&
                  data['imageUrl'].toString().isNotEmpty)
              ? data['imageUrl']
              : null;

          // Atualiza as features em tempo real
          _updateFeaturesFromData(data);
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth > 900;
            return isDesktop ? _buildDesktopLayout() : _buildMobileLayout();
          },
        );
      },
    );
  }

  String _getPlanDisplayName() {
    final plan = _currentPlanCode;
    final isTrial = _isTrial;
    
    String planName = SubscriptionService.getPlanDetails(plan)['name'].toString().toUpperCase();
    if (isTrial) {
      planName += " (TESTE)";
    }
    return planName;
  }

  List<Widget> _buildScreens({required bool isDesktop}) {
    return [
      _buildHomeDashboard(isDesktop: isDesktop), // 0
      BusinessSchedulePage(shopId: shopId ?? ""), // 1
      BusinessHistoryPage(shopId: shopId ?? ""), // 2
      const ServicesManagementPage(), // 3
      const BusinessClientsScreen(), // 4
      const FinancialDashboardPage(), // 5
      const TeamManagementPage(), // 6
      const InventoryHomePage(), // 7
      const BusinessSettingsPage(), // 8
      const PriceAdjustmentPage(), // 9
      const PrivacySettingsPage(), // 10
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
            'assets/images/logo_purple.png',
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
                _buildDesktopMenuItem(
                    0, Icons.dashboard_rounded, "Visão Geral"),
                _buildDesktopMenuItem(
                    1, Icons.event_note_rounded, "Agenda Completa"),
                _buildDesktopMenuItem(2, Icons.history, "Histórico"),
                _buildDesktopMenuItem(6, Icons.people_outline, "Equipe"),
                _buildDesktopMenuItem(
                    4, Icons.groups_rounded, "Clientes"),
                _buildDesktopMenuItem(7, Icons.inventory_2_outlined, "Estoque"),
                
                _buildDesktopMenuItem(
                    5,
                    Icons.account_balance_wallet_rounded,
                    "Financeiro",
                    trailing: !_currentFeatures.financialDashboard
                        ? const Icon(Icons.lock_outline,
                            size: 14, color: Colors.grey)
                        : null),

                _buildDesktopMenuItem(
                    3, Icons.design_services_rounded, "Meus Serviços"),
                _buildDesktopMenuItem(
                    9, Icons.trending_up_rounded, "Reajuste de Valores"),

                // Cupons
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(Icons.local_offer_outlined,
                        size: 20, color: Colors.grey),
                    title: const Text("Meus Cupons",
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87)),
                    onTap: () {
                      if (!_currentFeatures.coupons) {
                        _showUpgradeDialog('Cupons de Desconto');
                        return;
                      }
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ManageCouponsPage(shopId: shopId ?? "")));
                    },
                    trailing: !_currentFeatures.coupons
                        ? const Icon(Icons.lock, size: 16, color: Colors.grey)
                        : null,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Divider(height: 1),
                ),

                _buildHighlightedMenuItem(
                  icon: Icons.rocket_launch_rounded,
                  label: "Impulsionar Negócio",
                  color: const Color(0xFF7C3AED),
                  iconColor: const Color(0xFF7C3AED),
                  onTap: () => _handleMenuAction('impulsionar'),
                ),
                _buildHighlightedMenuItem(
                  icon: Icons.star_rounded,
                  label: "Planos & Assinatura",
                  color: Colors.orange,
                  iconColor: Colors.orange,
                  onTap: () => _handleMenuAction('assinatura'),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Divider(height: 1),
                ),
                _buildDesktopMenuItem(8, Icons.settings, "Configurações"),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Divider(height: 1),
                ),

                // Importar Catálogo WhatsApp apenas Web/PC
                if (kIsWeb)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                    child: ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: const Icon(Icons.upload_file_rounded,
                          size: 20, color: Color(0xFF25D366)),
                      title: const Text("Importar Catálogo WhatsApp",
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF25D366))),
                      onTap: () => _handleMenuAction('catalogo_import'),
                    ),
                  ),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Divider(height: 1),
                ),

                _buildDesktopMenuItem(
                    10, Icons.privacy_tip_rounded, "Privacidade & Segurança"),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Divider(height: 1),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                  child: ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(Icons.help_outline,
                        size: 20, color: AppColors.primaryPurple),
                    title: const Text("Ajuda / Tutorial",
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.primaryPurple)),
                    onTap: () => _handleMenuAction('ajuda'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text("v1.0 ${_getPlanDisplayName()}",
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopMenuItem(int index, IconData icon, String label,
      {Widget? trailing}) {
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
            fontSize: 15,
          ),
        ),
        onTap: () {
          if (_restrictedIndices.contains(index)) {
            _showUpgradeDialog(label);
          } else {
            setState(() => _selectedIndex = index);
          }
        },
        trailing: trailing ??
            (_restrictedIndices.contains(index)
                ? const Icon(Icons.lock, size: 16, color: Colors.grey)
                : null),
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
                // Mostrar apenas o avatar para economizar espaço
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
                const SizedBox(width: 6),
                const Icon(Icons.keyboard_arrow_down,
                    size: 18, color: Colors.grey),
              ],
            ),
            itemBuilder: (context) => [
              _buildPopupItem('perfil', Icons.store, "Perfil da Loja"),
              _buildPopupItem(
                  'assinatura', Icons.star_border, "Assinatura (Planos)",
                  isRed: false),
              if (_isAdmin)
                _buildPopupItem(
                    'admin', Icons.admin_panel_settings, "Painel Admin"),
              if (kIsWeb)
                PopupMenuItem<String>(
                  value: 'catalogo_import',
                  child: Row(children: const [
                    Icon(Icons.upload_file_rounded,
                        size: 18, color: Color(0xFF25D366)),
                    SizedBox(width: 10),
                    Text('Importar Catálogo WhatsApp',
                        style:
                            TextStyle(color: Color(0xFF25D366), fontSize: 13)),
                  ]),
                ),
              const PopupMenuDivider(),
              _buildPopupItem('sair', Icons.logout, "Sair", isRed: true),
            ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(
      String value, IconData icon, String text,
      {bool isRed = false}) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: isRed ? Colors.red : Colors.grey[700]),
          const SizedBox(width: 10),
          Text(text,
              style: TextStyle(
                  color: isRed ? Colors.red : Colors.black87, fontSize: 13)),
        ],
      ),
    );
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
                  // Apenas avatar no topo mobile para economizar espaço
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white,
                    backgroundImage: shopLogoUrl != null
                        ? CachedNetworkImageProvider(shopLogoUrl!)
                        : (userPhotoUrl != null
                            ? CachedNetworkImageProvider(userPhotoUrl!)
                            : null),
                    child: (shopLogoUrl == null && userPhotoUrl == null)
                        ? const Icon(Icons.store,
                            color: AppColors.primaryPurple)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                ],
              ),
            ),
            itemBuilder: (context) => [
              _buildPopupItem('perfil', Icons.store, "Perfil da Loja"),
              _buildPopupItem(
                  'assinatura', Icons.star_border, "Assinatura (Planos)"),
              _buildPopupItem(
                  'impulsionar', Icons.rocket_launch, "Impulsionar Negócio"),
              _buildPopupItem('ajuda', Icons.help_outline, "Ajuda / Tutorial"),
              const PopupMenuDivider(),
              _buildPopupItem('sair', Icons.logout, "Sair", isRed: true),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (_selectedIndex == 0) // Show only on dashboard
          const SizedBox(height: 8),
        Expanded(child: _buildScreens(isDesktop: false)[_selectedIndex]),
        const BannerAdWidget(),
      ]),
      bottomNavigationBar: _buildMobileBottomNav(),
    );
  }

  Widget _buildMobileBottomNav() {
    final mainItems = [
      0,
      1,
      3,
      8
    ]; // Index 8 is Settings (BusinessSettingsPage). Histórico e Clientes estão no menu lateral.
    int currentBottomIndex = mainItems.contains(_selectedIndex)
        ? mainItems.indexOf(_selectedIndex)
        : 0;

    return BottomNavigationBar(
      currentIndex: currentBottomIndex,
      onTap: (index) {
        final newSelected = mainItems[index];

        if (_restrictedIndices.contains(newSelected)) {
          // Identify label for dialog
          String label = "Este recurso";
          if (newSelected == 5) label = "Financeiro";
          if (newSelected == 7) label = "Estoque";
          _showUpgradeDialog(label);
          return;
        }

        setState(() {
          _selectedIndex = newSelected;
        });
        // initialize agenda list only when navigating to Agenda tab
        if (newSelected == 1) {
          _initMobileAppointmentsOnce();
        }
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
          icon: Icon(Icons.settings, size: 24),
          label: "Config",
        ),
      ],
    );
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
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
            child: Center(
              child: Image.asset(
                'assets/images/logo_white.png',
                height: 40,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(
                  icon: Icons.history,
                  title: "Histórico",
                  index: 2,
                ),
                _buildDrawerItem(
                  icon: Icons.people,
                  title: "Equipe",
                  index: 6,
                ),
                _buildDrawerItem(
                  icon: Icons.groups,
                  title: "Clientes",
                  index: 4,
                ),
                _buildDrawerItem(
                  icon: Icons.inventory_2_outlined,
                  title: "Estoque",
                  index: 7,
                ),
                _buildDrawerItem(
                    icon: Icons.account_balance_wallet,
                    title: "Financeiro",
                    index: 5,
                    trailing: !_currentFeatures.financialDashboard
                        ? const Icon(Icons.lock_outline,
                            size: 16, color: Colors.grey)
                        : null),
                _buildDrawerItem(
                  icon: Icons.trending_up,
                  title: "Reajuste de Valores",
                  index: 9,
                ),
                _buildDrawerItem(
                  icon: Icons.local_offer_outlined,
                  title: "Meus Cupons",
                  index: -1,
                  onTap: () {
                    if (!_currentFeatures.coupons) {
                      _showUpgradeDialog('Cupons de Desconto');
                      return;
                    }
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ManageCouponsPage(shopId: shopId ?? "")));
                  },
                  trailing: !_currentFeatures.coupons
                      ? const Icon(Icons.lock, size: 16, color: Colors.grey)
                      : null,
                ),

                const Divider(),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    "CRESCIMENTO",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),

                _buildHighlightedMenuItem(
                  icon: Icons.rocket_launch,
                  label: "Impulsionar Negócio",
                  color: const Color(0xFF7C3AED),
                  iconColor: const Color(0xFF7C3AED),
                  onTap: () => _handleMenuAction('impulsionar'),
                ),
                _buildHighlightedMenuItem(
                  icon: Icons.star,
                  label: "Planos & Assinatura",
                  color: Colors.orange,
                  iconColor: Colors.orange,
                  onTap: () => _handleMenuAction('assinatura'),
                ),

                const Divider(),

                _buildDrawerItem(
                  icon: Icons.privacy_tip_outlined,
                  title: "Privacidade & Segurança",
                  index: 10,
                  isPrimary: true,
                ),
                _buildDrawerItem(
                  icon: Icons.help_outline,
                  title: "Ajuda / Tutorial",
                  index: -1, // Custom action
                  isPrimary: true,
                  onTap: () => _handleMenuAction('ajuda'),
                ),
                if (_isAdmin) ...[
                  const Divider(),
                  _buildDrawerItem(
                    icon: Icons.admin_panel_settings_outlined,
                    title: "Painel Administrativo",
                    index: -1,
                    isPrimary: true,
                    onTap: () => _handleMenuAction('admin'),
                  ),
                ],
              ],
            ),
          ),
          Builder(
            builder: (context) {
              final plan = _currentPlanCode;
              final isTrial = _isTrial;
              
              String planName = SubscriptionService.getPlanDetails(plan)['name'].toString().toUpperCase();
              if (isTrial) {
                planName += " (TESTE)";
              }

              final isFree = plan == SubscriptionPlan.free;

              return SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    border: Border(top: BorderSide(color: Colors.grey[200]!)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Seu Plano: ",
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                          Text(
                            planName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isFree
                                  ? Colors.grey[600]
                                  : AppColors.primaryPurple,
                            ),
                          ),
                        ],
                      ),
                      if (isFree || isTrial) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _handleMenuAction('assinatura');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryPurple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: Text(isTrial ? "ASSINAR AGORA" : "FAZER UPGRADE"),
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightedMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
    Color? iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Icon(icon, color: iconColor ?? color, size: 22),
        title: Text(
          label,
          style: TextStyle(
            color: color.withOpacity(0.9),
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, 
          size: 12, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required int index,
    Widget? trailing,
    VoidCallback? onTap,
    double opacity = 1.0,
    bool isPrimary = false,
  }) {
    bool isSelected = index != -1 && _selectedIndex == index;
    return Opacity(
      opacity: opacity,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryPurple.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(
            icon,
            color: isSelected || isPrimary ? AppColors.primaryPurple : Colors.grey[600],
            size: 20,
          ),
          title: Text(
            title,
            style: TextStyle(
              color: isSelected || isPrimary ? AppColors.primaryPurple : Colors.grey[800],
              fontWeight: isSelected || isPrimary ? FontWeight.bold : FontWeight.w500,
              fontSize: 15,
            ),
          ),
          onTap: () {
            Navigator.pop(context);
            if (onTap != null) {
              onTap();
            } else if (index != -1) {
              if (_restrictedIndices.contains(index)) {
                _showUpgradeDialog(title);
              } else {
                setState(() => _selectedIndex = index);
              }
            }
          },
          trailing: trailing ??
              (index != -1 && _restrictedIndices.contains(index)
                  ? const Icon(Icons.lock, size: 16, color: Colors.grey)
                  : null),
        ),
      ),
    );
  }

  // ============================================================================
  // DASHBOARD - OTIMIZADO E COM MONITOR DE CUSTO
  // ============================================================================

  Widget _buildHomeDashboard({required bool isDesktop}) {
    // 1. Definio do Intervalo de Tempo para Leitura (Range)
    // Se selecionado "Todos" (-1), pegamos um range amplo, mas idealmente voc limitaria.
    // Aqui vamos focar na otimizao do ano selecionado.

    DateTime startData;
    DateTime endData;

    if (_selectedYear == -1) {
      // CUIDADO: Ler tudo pode ser caro.
      // Em produo, recomendo limitar aos ltimos 2 anos.
      startData = DateTime(2023, 1, 1);
      endData = DateTime(2030, 12, 31);
    } else {
      startData = DateTime(_selectedYear, 1, 1);
      endData = DateTime(_selectedYear, 12, 31, 23, 59, 59);
    }

    return StreamBuilder<QuerySnapshot>(
      // ðŸ”¥ QUERY BLINDADA: Filtra por Shop + Intervalo de Data
      // Isso exige um Índice Composto no Firebase (ShopId + Data Asc/Desc)
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('shopId', isEqualTo: shopId)
          .where('data_agendamento', isGreaterThanOrEqualTo: startData)
          .where('data_agendamento', isLessThanOrEqualTo: endData)
          .snapshots(), // Ordenao pode ser feita em memria para economizar ndice ou no .orderBy
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: Text(
                  "Erro (Verifique ndices no Console): ${snapshot.error}"));
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
          debugPrint(
              "ðŸ’° [ECONOMIA] Lendo ${docs.length} agendamentos do CACHE Local.");
        } else {
          debugPrint(
              "ðŸ’¸ [CUSTO] Baixando ${docs.length} documentos do SERVIDOR ($shopId).");
        }

        // --- LÃ“GICA DE CÁLCULO (Mantida, mas operando sobre o subset filtrado) ---

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
          'Jan',
          'Fev',
          'Mar',
          'Abr',
          'Mai',
          'Jun',
          'Jul',
          'Ago',
          'Set',
          'Out',
          'Nov',
          'Dez'
        ];
        dataMoney = List.filled(12, 0.0);
        dataQty = List.filled(12, 0.0);

        for (var doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['data_agendamento'] is! Timestamp) continue;

          DateTime date = (data['data_agendamento'] as Timestamp).toDate();

          // Filtra status concludo
          if ((data['status'] ?? 'agendado') == 'concluido') {
            double total = double.tryParse(data['valor_total']?.toString() ??
                    data['valor']?.toString() ??
                    '0') ??
                0.0;
            double maoObra =
                double.tryParse(data['valor_mao_de_obra']?.toString() ?? '0') ??
                    0.0;
            double produtos =
                double.tryParse(data['valor_produtos']?.toString() ?? '0') ??
                    0.0;

            if (maoObra == 0 && produtos == 0) maoObra = total;

            // Se for visualizao mensal (ano selecionado)
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

        // Se for "Todos os anos", ajustamos o grfico para ser por Ano, no por Ms
        if (isAllYears) {
          // Lgica simplificada para multiplos anos (recalculando baseada nos docs recebidos)
          Map<int, double> yearMoney = {};
          Map<int, double> yearQty = {};
          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            DateTime date = (data['data_agendamento'] as Timestamp).toDate();
            if ((data['status'] ?? 'agendado') == 'concluido') {
              double total =
                  double.tryParse(data['valor_total']?.toString() ?? '0') ?? 0;
              yearMoney[date.year] = (yearMoney[date.year] ?? 0) + total;
              yearQty[date.year] = (yearQty[date.year] ?? 0) + 1;
            }
          }
          chartLabels = yearMoney.keys.map((e) => e.toString()).toList();
          chartLabels.sort();
          dataMoney =
              chartLabels.map((key) => yearMoney[int.parse(key)]!).toList();
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

  // ... (RESTANTE DOS WIDGETS DE UI - _buildDesktopDashboard, _buildMobileDashboard, ETC. PERMANECEM IGUAIS PARA NO QUEBRAR O DESIGN)

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

        // --- ANIVERSARIANTES DO DIA (DESKTOP) ---
        _buildBirthdaysSection(isDesktop: true),

        if (_currentFeatures.financialTab) ...[
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
                  "Ticket Mdio",
                  ticketMedio,
                  Icons.receipt_long,
                  AppColors.primaryPurple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (_currentFeatures.financialTab)
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
        if (shopId != null &&
            appointmentDocs != null &&
            appointmentDocs.isNotEmpty &&
            _canViewCommissions) ...[
          const SizedBox(height: 16),
          _buildEquipeComissoesCard(shopId!, appointmentDocs),
        ],
      ],
    );
  }

  Widget _buildEquipeComissoesCard(
      String shopId, List<QueryDocumentSnapshot> appointmentDocs) {
    // Calcular produo por profissional
    final concluidos = appointmentDocs.where((d) {
      final data = d.data() as Map<String, dynamic>;
      return (data['status'] ?? '') == 'confirmado' ||
          (data['status'] ?? '') == 'concluido';
    }).toList();

    Map<String, double> producaoPorProf = {};
    for (var d in concluidos) {
      final data = d.data() as Map<String, dynamic>;
      final pid = data['profissionalId']?.toString() ?? '';
      if (pid.isEmpty) continue;
      final valor = double.tryParse(data['valor_pago']?.toString() ??
              data['valor_total']?.toString() ??
              '0') ??
          0;
      producaoPorProf[pid] = (producaoPorProf[pid] ?? 0) + valor;
    }

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('employees')
          .where('shopId', isEqualTo: shopId)
          .get(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final employees = snap.data!.docs;
        double totalComissao = 0;
        final List<Map<String, dynamic>> teamData = [];

        // Preparar dados
        for (var emp in employees) {
          final ed = emp.data() as Map<String, dynamic>?;
          final nome = ed?['nome']?.toString() ?? 'Profissional';
          final p = ed?['comissao_percent'];
          final percent = (p is num) ? p.toDouble() : 0.0;
          final produzido = producaoPorProf[emp.id] ?? 0.0;
          final aReceber = percent > 0 ? (produzido * percent / 100) : 0.0;

          if (produzido > 0 || aReceber > 0) {
            totalComissao += aReceber;
            teamData.add({
              'nome': nome,
              'produzido': produzido,
              'aReceber': aReceber,
              'percent': percent,
            });
          }
        }

        // Se ningum produziu nada, no mostra ou mostra vazio elegante
        if (teamData.isEmpty) return const SizedBox.shrink();

        // Ordenar por valor a receber (maior para menor)
        teamData.sort((a, b) =>
            (b['aReceber'] as double).compareTo(a['aReceber'] as double));

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header com Gradiente
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryPurple,
                      AppColors.primaryPurple.withValues(alpha: 0.8)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.people_alt_outlined,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Comisses da Equipe",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            "Produo e valores a repassar",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          "Total a Pagar",
                          style: TextStyle(color: Colors.white70, fontSize: 10),
                        ),
                        Text(
                          NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
                              .format(totalComissao),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Lista de Profissionais
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: teamData.length,
                separatorBuilder: (_, __) => const Divider(height: 24),
                itemBuilder: (context, index) {
                  final item = teamData[index];
                  return Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor:
                            AppColors.primaryPurple.withValues(alpha: 0.1),
                        child: Text(
                          item['nome'].toString().substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.primaryPurple,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['nome'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              "Produziu: ${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(item['produzido'])}",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "Comisso (${item['percent']}%)",
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 10),
                          ),
                          Text(
                            NumberFormat.currency(
                                    locale: 'pt_BR', symbol: 'R\$')
                                .format(item['aReceber']),
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),

              // Footer
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(16)),
                ),
                child: Text(
                  "Valores calculados com base nos agendamentos concludos do perodo selecionado.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ),
            ],
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
    final now = DateTime.now();
    final hoje = appointmentDocs == null
        ? 0
        : appointmentDocs.where((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final ts = d['data_agendamento'];
            if (ts is! Timestamp) return false;
            final dt = ts.toDate();
            return dt.year == now.year &&
                dt.month == now.month &&
                dt.day == now.day;
          }).length;

    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -- Hero Header com gradiente ------------------------------------
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6C3CE2), Color(0xFF9B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
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
                            isAllYears
                                ? 'Visão Geral  Todos os anos'
                                : 'Resultados de $_selectedYear',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            shopName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildYearDropdown(dark: true),
                  ],
                ),
                const SizedBox(height: 20),
                // Faturamento em destaque no header
                Text(
                  fmt.format(faturamentoTotal),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Faturamento total',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),

          // --- CARDS PRINCIPAIS ----------------------------------------
          const TrialBannerWidget(),
          Transform.translate(
            offset: const Offset(0, -14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildKpiCard(
                      title: 'Atendimentos',
                      value: totalAtendimentos.toString(),
                      subtitle:
                          isAllYears ? 'total geral' : 'em $_selectedYear',
                      icon: Icons.people_alt_rounded,
                      color: const Color(0xFF4F8EF7),
                      isMoney: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildKpiCard(
                      title: 'Ticket Mdio',
                      value: fmt.format(ticketMedio),
                      subtitle: 'por atendimento',
                      icon: Icons.receipt_long_rounded,
                      color: const Color(0xFF00C9A7),
                      isMoney: true,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                // -- Aniversariantes do Dia --------------------------------
                _buildBirthdaysSection(isDesktop: false),
                const SizedBox(height: 12),

                // -- Card Hoje ---------------------------------------------
                _buildHojeCard(hoje, appointmentDocs),
                const SizedBox(height: 12),

                if (_currentFeatures.financialTab) ...[
                  // -- Breakdown Servios vs Produtos ------------------------
                  _buildBreakdownVisual(
                    faturamentoMaoDeObra,
                    faturamentoProdutos,
                    faturamentoTotal,
                  ),
                  const SizedBox(height: 12),

                  // -- Grfico -----------------------------------------------
                  _buildMobileChart(dataMoney, dataQty, chartLabels, isAllYears),
                ],

                if (shopId != null &&
                    appointmentDocs != null &&
                    appointmentDocs.isNotEmpty &&
                    _canViewCommissions) ...[
                  const SizedBox(height: 12),
                  _buildEquipeComissoesCard(shopId!, appointmentDocs),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isMoney,
  }) {
    return GestureDetector(
      onTap: () {
        if (!_hiddenIndices.contains(5)) {
          if (_restrictedIndices.contains(5)) {
            _showUpgradeDialog('Dashboard Financeiro');
          } else {
            setState(() => _selectedIndex = 5);
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        color.withValues(alpha: 0.15),
                        color.withValues(alpha: 0.05)
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const Spacer(),
                Icon(Icons.trending_up_rounded, color: color, size: 14),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1D2E)),
              ),
            ),
            const SizedBox(height: 2),
            Text(subtitle,
                style: TextStyle(fontSize: 10, color: Colors.grey[400])),
          ],
        ),
      ),
    );
  }

  Widget _buildHojeCard(int hoje, List<QueryDocumentSnapshot>? allDocs) {
    final now = DateTime.now();
    // Prximos agendamentos de hoje (somente agendado/confirmado)
    final proximosHoje = allDocs?.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          final ts = d['data_agendamento'];
          if (ts is! Timestamp) return false;
          final dt = ts.toDate();
          final status = (d['status'] ?? '').toString();
          return dt.year == now.year &&
              dt.month == now.month &&
              dt.day == now.day &&
              (status == 'agendado' || status == 'confirmado');
        }).toList() ??
        [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0EEFF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F0FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.today_rounded,
                    color: AppColors.primaryPurple, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Agenda de Hoje',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(
                      proximosHoje.isEmpty
                          ? 'Nenhum agendamento pendente'
                          : '${proximosHoje.length} agendamento${proximosHoje.length > 1 ? 's' : ''} pendente${proximosHoje.length > 1 ? 's' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: hoje == 0 ? Colors.grey[100] : const Color(0xFFF3F0FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$hoje realizados',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: hoje == 0 ? Colors.grey : AppColors.primaryPurple,
                  ),
                ),
              ),
            ],
          ),
          if (proximosHoje.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            ...proximosHoje.take(3).map((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final ts = d['data_agendamento'] as Timestamp;
              final hora = TimeOfDay.fromDateTime(ts.toDate()).format(context);
              final clienteNome =
                  (d['client_name'] ?? d['clientName'] ?? 'Cliente').toString();
              final servico = (d['service_name'] ??
                      d['serviceName'] ??
                      d['descricao'] ??
                      '')
                  .toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF9B5CF6), Color(0xFF6C3CE2)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          hora,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(clienteNome,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          if (servico.isNotEmpty)
                            Text(servico,
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[500])),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildBreakdownVisual(double servico, double produto, double total) {
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final pctServico = total > 0 ? servico / total : 0.0;
    final pctProduto = total > 0 ? produto / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0EEFF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_rounded,
                  color: AppColors.primaryPurple, size: 18),
              const SizedBox(width: 8),
              const Text('Composio do Faturamento',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Flexible(
                    flex: (pctServico * 100).round(),
                    child: Container(color: const Color(0xFF6C3CE2)),
                  ),
                  Flexible(
                    flex: (pctProduto * 100).round(),
                    child: Container(color: const Color(0xFF00C9A7)),
                  ),
                  if (pctServico + pctProduto < 0.99)
                    Flexible(
                      flex: ((1 - pctServico - pctProduto) * 100).round(),
                      child: Container(color: Colors.grey[200]),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _breakdownRow(
              'Serviços', servico, pctServico, const Color(0xFF6C3CE2), fmt),
          const SizedBox(height: 8),
          _breakdownRow(
              'Produtos', produto, pctProduto, const Color(0xFF00C9A7), fmt),
        ],
      ),
    );
  }

  Widget _breakdownRow(
      String label, double value, double pct, Color color, NumberFormat fmt) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(fmt.format(value),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(width: 6),
        Text('${(pct * 100).toStringAsFixed(0)}%',
            style: TextStyle(fontSize: 11, color: Colors.grey[400])),
      ],
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
          const SizedBox(height: 30),
          SizedBox(
            height: 220,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // Start scroll from the end to see the most recent months
              reverse: true,
              child: SizedBox(
                width: max(MediaQuery.of(context).size.width - 60,
                    labels.length * 60.0),
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: 150,
                    minY: 0,
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        fitInsideHorizontally: true,
                        fitInsideVertically: true,
                        tooltipPadding: const EdgeInsets.all(8),
                        tooltipMargin: 8,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          String label = labels[groupIndex];
                          // Money
                          if (rodIndex == 0) {
                            final val = moneyData[groupIndex];
                            final fmt = NumberFormat.currency(
                                locale: 'pt_BR', symbol: 'R\$');
                            return BarTooltipItem(
                              '$label\n${fmt.format(val)}',
                              const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            );
                          }
                          // Qty
                          else {
                            final val = qtyData[groupIndex].toInt();
                            return BarTooltipItem(
                              '$label\n$val atend.',
                              const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            );
                          }
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (double value, TitleMeta meta) {
                            final i = value.toInt();
                            if (i < 0 || i >= labels.length) {
                              return const SizedBox.shrink();
                            }
                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              space: 8,
                              child: Text(
                                labels[i],
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles:
                          AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 50,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: Colors.grey.withValues(alpha: 0.1),
                        strokeWidth: 1,
                        dashArray: [5, 5],
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: List.generate(labels.length, (i) {
                      double moneyH = (moneyData[i] / maxMoney) * 150;
                      double qtyH = (qtyData[i] / maxQty) * 150;

                      // Min height so empty bars are slightly visible for tooltips
                      if (moneyH < 2) moneyH = 2;
                      if (qtyH < 2) qtyH = 2;

                      return BarChartGroupData(
                        x: i,
                        barsSpace: 4,
                        showingTooltipIndicators: [], // Could be used to always show labels
                        barRods: [
                          BarChartRodData(
                            toY: moneyH,
                            color: AppColors.primaryPurple,
                            width: 14,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                          ),
                          BarChartRodData(
                            toY: qtyH,
                            color: AppColors.gold,
                            width: 14,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearDropdown({bool dark = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.15) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.4)
              : AppColors.primaryPurple.withValues(alpha: 0.3),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _availableYears.contains(_selectedYear) || _selectedYear == -1
              ? _selectedYear
              : -1,
          icon: Icon(Icons.filter_list,
              color: dark ? Colors.white : AppColors.primaryPurple, size: 18),
          dropdownColor: dark ? const Color(0xFF6C3CE2) : null,
          isDense: true,
          items: [
            DropdownMenuItem<int>(
              value: -1,
              child: Text(
                "Todos",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: dark ? Colors.white : AppColors.primaryPurple,
                  fontSize: 13,
                ),
              ),
            ),
            ..._availableYears.map(
              (int year) => DropdownMenuItem<int>(
                value: year,
                child: Text(
                  year.toString(),
                  style: TextStyle(
                      fontSize: 13, color: dark ? Colors.white70 : null),
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

    return GestureDetector(
      onTap: () {
        if (!_hiddenIndices.contains(5)) {
          if (_restrictedIndices.contains(5)) {
            _showUpgradeDialog('Dashboard Financeiro');
          } else {
            setState(() => _selectedIndex = 5);
          }
        }
      },
      child: Container(
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
                "Evoluo de Performance",
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

  Widget _buildBirthdaysSection({required bool isDesktop}) {
    if (shopId == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final todayStr = DateFormat('dd/MM').format(now);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('lojasVinculadas', arrayContains: shopId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final aniversariantes = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final birth = data['data_nascimento'] ??
              data['nascimento'] ??
              data['birthDate'];
          if (birth == null) return false;

          String clientBirthStr = "";
          if (birth is Timestamp) {
            clientBirthStr = DateFormat('dd/MM').format(birth.toDate());
          } else if (birth is String) {
            // Tenta parsear string DD/MM/AAAA ou AAAA-MM-DD
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
        }).toList();

        if (aniversariantes.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: EdgeInsets.only(bottom: isDesktop ? 20 : 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.pink.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.pink.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.pink.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.cake_rounded,
                        color: Colors.pink.shade400, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    "Aniversariantes do Dia!",
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF1A1D2E)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: aniversariantes.length,
                  itemBuilder: (context, index) {
                    final client =
                        aniversariantes[index].data() as Map<String, dynamic>;
                    final nome = client['nome'] ?? "Cliente";
                    final phone = client['telefone'] ?? client['whatsapp'];
                    final foto = client['fotoUrl'] ?? client['foto'];

                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: InkWell(
                        onTap: () {
                          if (phone != null) {
                            _launchWhatsAppFromPhone(phone.toString());
                          }
                        },
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.pink.shade50,
                              backgroundImage: foto != null
                                  ? CachedNetworkImageProvider(foto)
                                  : null,
                              child: foto == null
                                  ? const Icon(Icons.person,
                                      size: 20, color: Colors.pink)
                                  : null,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              nome.split(' ')[0],
                              style: const TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w500),
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
        );
      },
    );
  }

  Future<void> _launchWhatsAppFromPhone(String phoneRaw) async {
    String phone = phoneRaw.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone.length <= 11) phone = '55$phone';

    final url = Uri.parse(
        'https://wa.me/$phone?text=Parabéns pelo seu aniversário! 🎉');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
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
        return "Histórico";
      case 3:
        return "Serviços";
      case 4:
        return "Clientes";
      case 5:
        return "Financeiro";
      case 6:
        return "Equipe";
      case 7:
        return "Estoque";
      case 8:
        return "Configurações";
      default:
        return "";
    }
  }
}
