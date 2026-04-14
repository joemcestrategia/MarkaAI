import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'catalog_import_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:cached_network_image/cached_network_image.dart';
import 'store_profile_page.dart';
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
import '../../core/constants/plan_features.dart';
import '../../core/services/plan_features_service.dart';
import '../../widgets/upgrade_modal.dart';
import '../../core/services/session_service.dart';
import '../../core/services/shop_data_cache_service.dart';
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
import '../../core/widgets/supabase_stream_widget.dart';

import 'subscription_plans_page.dart';
import '../../modules/inventory/inventory_home_page.dart';
import 'subscription_service.dart';
import '../help/help_guide_page.dart';
import 'price_adjustment_page.dart';
import '../../pages/privacy_settings_page.dart';
import 'holidays_page.dart';
// import '../clients/client_affiliate_page.dart'; // Removido: sistema de afiliados desativado
import '../fiscal/nfse_dashboard_screen.dart';

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
  int _selectedYear =
      DateTime.now().year; // Comea com o ano atual para economizar
  int _selectedMonth = DateTime.now().month; // Mês atual como padrão
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

  // Dados da loja vindos do stream (evita múltiplos StreamBuilders)
  int _pendingHolidaysCount = 0;

  // Cached futures para evitar re-fetch em cada rebuild
  Future<List<Map<String, dynamic>>>? _statsFuture;
  Future<List<Map<String, dynamic>>>? _todayFuture;
  Future<List<Map<String, dynamic>>>? _commissionFuture;
  Future<List<Map<String, dynamic>>>? _birthdayFuture;
  Future<List<Map<String, dynamic>>>? _employeesFuture;
  List<Map<String, dynamic>> _statsCache = [];
  sb.RealtimeChannel? _appointmentsChannel;
  int _lastDashboardYear = -999; // Sentinel para detectar mudança de ano

  @override
  void initState() {
    super.initState();
    _checkBusinessAndLoad();
    _setupForegroundNotifications();
  }

  @override
  void dispose() {
    _appointmentsChannel?.unsubscribe();
    super.dispose();
  }

  void _setupForegroundNotifications() {
    // Supabase Realtime ou Notificações Locais podem ser implementadas aqui
    // Por enquanto, removemos a dependência do FirebaseMessaging
    debugPrint("Notificações foreground (via Supabase/Local) podem ser configuradas aqui.");
  }

  Future<void> _checkBusinessAndLoad() async {
    try {
      final user = sb.Supabase.instance.client.auth.currentUser;
      
      // Obtém userId e cachedShopId em paralelo para economizar tempo inicial
      final resultsLocal = await Future.wait([
        SessionService.getUserId(),
        SessionService.getShopId(),
      ]);
      
      final String? sessionUserId = resultsLocal[0];
      final String? cachedShopId = resultsLocal[1];
      final String? effectiveUid = user?.id ?? sessionUserId;

      if (effectiveUid == null) {
        _forceLogout();
        return;
      }

      // DISPARO PARALELO: Perfil do usuário e Dados da Loja (se shopId estiver em cache)
      final List<Future<dynamic>> queries = [
        sb.Supabase.instance.client
            .from('users')
            .select()
            .eq('id', effectiveUid)
            .maybeSingle(),
      ];

      // Se temos o shopId em cache, já puxamos os dados da loja agora
      if (cachedShopId != null && cachedShopId.isNotEmpty) {
        queries.add(
          sb.Supabase.instance.client
              .from('shops')
              .select('*, config')
              .eq('id', cachedShopId)
              .maybeSingle(),
        );
      }

      final results = await Future.wait(queries);
      Map<String, dynamic>? userData = results[0];
      Map<String, dynamic>? shopData = results.length > 1 ? results[1] : null;

      // Fallback para metadados (como feito no login_page) para contornar Race Condition/RLS recém-aplicado
      if (userData == null && user?.userMetadata != null && user!.userMetadata!.containsKey('role')) {
        userData = user.userMetadata;
      }

      if (userData == null) {
        _forceLogout();
        return;
      }
      
      final String role = userData['role'] ?? 'cliente';
      final bool isAdmin = (role == 'admin');
      
      // Trust the user document first, then session
      String currentShopId = userData['shop_id'] ?? cachedShopId ?? "";

      if (role != 'dono' && role != 'business' && !isAdmin) {
        _forceLogout();
        return;
      }

      if (currentShopId.isEmpty && !isAdmin) {
        _forceLogout();
        return;
      }

      // Caso o shopId do banco seja diferente do cache, carregamos os dados da loja correta de forma sequencial (raro)
      if (currentShopId.isNotEmpty && currentShopId != cachedShopId) {
        shopData = await sb.Supabase.instance.client
            .from('shops')
            .select('*, config')
            .eq('id', currentShopId)
            .maybeSingle();
      }

      // Tenta buscar anos disponíveis
      final currentYear = DateTime.now().year;
      _availableYears = List.generate(5, (index) => (currentYear - 2) + index);

      // Save the identified shopId to session
      if (currentShopId.isNotEmpty && currentShopId != cachedShopId) {
        await SessionService.saveShopId(currentShopId);
      }

      if (mounted) {
        setState(() {
          shopId = currentShopId;
          userName = userData!['name'] ?? "Profissional";
          userEmail = user?.email ?? "";
          userPhotoUrl = user?.userMetadata?['avatar_url'] as String?;
          
          if (shopData != null) {
            _updateFeaturesFromData(shopData);
          }
          
          // Check admin status across different possible schemas
          final roles = userData['roles'] as List?;
          final roleStr = userData['role'] as String?;
          final isAdminDev = userData['is_admin_dev'] == true;
          
          _isAdmin = roleStr == 'admin' || 
                      (roles?.contains('admin') ?? false) || 
                      isAdminDev;
                       
          _isLoading = false;
        });

        // Inicia canal Realtime para invalidar o dashboard automaticamente
        _startAppointmentsRealtime();

        // 🔔 Inicializar notificações push
        try {
          NotificationService.registerToken(effectiveUid);
          NotificationService.initialize().then((_) {
            debugPrint('✅ Notificações inicializadas para o dono da loja');
          }).catchError((e) {
            debugPrint('❌ Erro ao inicializar notificações (catchError): $e');
          });
        } catch (e) {
          debugPrint('❌ Erro síncrono ao inicializar notificações: $e');
        }
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
      await sb.Supabase.instance.client.auth.signOut();
    } catch (_) {}

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  void _startAppointmentsRealtime() {
    if (shopId == null) return;
    _appointmentsChannel = sb.Supabase.instance.client
        .channel('home_appointments_$shopId')
        .onPostgresChanges(
          event: sb.PostgresChangeEvent.all,
          schema: 'public',
          table: 'appointments',
          filter: sb.PostgresChangeFilter(
            type: sb.PostgresChangeFilterType.eq,
            column: 'shop_id',
            value: shopId!,
          ),
          callback: (payload) {
            if (mounted) {
              setState(() {
                _statsFuture = null;
                _todayFuture = null;
                _commissionFuture = null;
                _employeesFuture = null;
              });
            }
          },
        )
        .subscribe();
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

    // Financeiro (Índice 5) — aberto para Plus (básico) e Pro (avançado)
    if (!_currentFeatures.financialTab) {
      _restrictedIndices.add(5);
    }

    // Reajuste de Valores (Índice 9)
    if (!_currentFeatures.automaticPriceAdjustment) {
      _restrictedIndices.add(9);
    }

    // Comissões
    _canViewCommissions = _currentFeatures.commissionView;

    // Folgas e Feriados (Índice 11)
    if (!_currentFeatures.holidaysManagement) {
      _restrictedIndices.add(11);
    }
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
            24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 24),
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

    return SupabaseStreamWidget<List<Map<String, dynamic>>>(
      initialFuture: shopId != null ? ShopDataCacheService().getShop(shopId!).then((s) => s != null ? [s] : []) : null,
      stream: shopId != null
          ? sb.Supabase.instance.client
              .from('shops')
              .stream(primaryKey: ['id'])
              .eq('id', shopId!)
          : const Stream.empty(),
      builder: (context, snapshotData) {
        if (snapshotData.isNotEmpty) {
          final data = snapshotData.first;
          
          // Extrair dados da stream de forma síncrona (sem setState durante build)
          // Estes valores são lidos diretamente nos widgets filhos
          _updateFeaturesFromData(data);
          shopName = data['name'] ?? "Meu Negócio";

          shopLogoUrl = (data['logo_url'] != null &&
                  data['logo_url'].toString().isNotEmpty)
              ? data['logo_url']
              : null;

          shopImageUrl = (data['image_url'] != null &&
                  data['image_url'].toString().isNotEmpty)
              ? data['image_url']
              : null;

          // Consolidar dados de holidays para evitar StreamBuilders duplicados
          final pendentes = data['pending_holidays'] as List?;
          _pendingHolidaysCount = pendentes?.length ?? 0;
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 1024) return _buildDesktopLayout();
            if (constraints.maxWidth >= 600) return _buildTabletLayout();
            return _buildMobileLayout();
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

  Widget _buildCurrentScreen({required bool isDesktop}) {
    switch (_selectedIndex) {
      case 0: return _buildHomeDashboard(isDesktop: isDesktop);
      case 1: return BusinessSchedulePage(shopId: shopId ?? "");
      case 2: return BusinessHistoryPage(shopId: shopId ?? "");
      case 3: return const ServicesManagementPage();
      case 4: return const BusinessClientsScreen();
      case 5: return const FinancialDashboardPage();
      case 6: return const TeamManagementPage();
      case 7: return const InventoryHomePage();
      case 8: return const BusinessSettingsPage();
      case 9: return const PriceAdjustmentPage();
      case 10: return const PrivacySettingsPage();
      case 11: return HolidaysPage(shopId: shopId ?? "");
      case 12: return const NfseDashboardScreen();
      default: return _buildHomeDashboard(isDesktop: isDesktop);
    }
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
                    child: _buildCurrentScreen(isDesktop: true),
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
                
                // Folgas e Feriados (usa _pendingHolidaysCount do stream principal)
                _buildDesktopMenuItem(
                  11, 
                  Icons.beach_access_rounded, 
                  "Folgas e Feriados",
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_pendingHolidaysCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _pendingHolidaysCount.toString(),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      if (!_currentFeatures.holidaysManagement)
                        const Icon(Icons.lock, size: 16, color: Colors.grey)
                    ],
                  ),
                ),

                _buildDesktopMenuItem(
                    12, Icons.receipt_long_rounded, "Fiscal NFS-e"),

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

                // Item de afiliados removido

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
  // TABLET LAYOUT (600–1024px) — Sidebar compacta + conteúdo
  // ============================================================================

  Widget _buildTabletLayout() {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      body: Row(
        children: [
          // Sidebar compacta para tablet (apenas ícones + label curto)
          SizedBox(
            width: 72,
            child: Material(
              color: Colors.white,
              elevation: 1,
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Image.asset(
                    'assets/images/logo_purple.png',
                    width: 36,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.storefront_rounded,
                      color: AppColors.primaryPurple,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _buildTabletNavIcon(0, Icons.dashboard_rounded, "Painel"),
                        _buildTabletNavIcon(1, Icons.event_note_rounded, "Agenda"),
                        _buildTabletNavIcon(2, Icons.history, "Histórico"),
                        _buildTabletNavIcon(6, Icons.people_outline, "Equipe"),
                        _buildTabletNavIcon(4, Icons.groups_rounded, "Clientes"),
                        _buildTabletNavIcon(3, Icons.design_services_rounded, "Serviços"),
                        _buildTabletNavIcon(5, Icons.account_balance_wallet_rounded, "Financeiro"),
                        _buildTabletNavIcon(7, Icons.inventory_2_outlined, "Estoque"),
                        _buildTabletNavIcon(8, Icons.settings, "Config"),
                        _buildTabletNavIcon(11, Icons.beach_access_rounded, "Folgas",
                            badge: _pendingHolidaysCount),
                        _buildTabletNavIcon(12, Icons.receipt_long_rounded, "NFS-e"),
                      ],
                    ),
                  ),
                  // Logout
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: Colors.grey, size: 22),
                    onPressed: _confirmLogout,
                    tooltip: "Sair",
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _buildDesktopHeader(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildCurrentScreen(isDesktop: true),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletNavIcon(int index, IconData icon, String label, {int badge = 0}) {
    final isSelected = _selectedIndex == index;
    final isRestricted = _restrictedIndices.contains(index);

    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () {
          if (isRestricted) {
            _showUpgradeDialog(label);
          } else {
            setState(() => _selectedIndex = index);
          }
        },
        child: Container(
          width: 72,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryPurple.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isSelected ? AppColors.primaryPurple : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: isSelected
                        ? AppColors.primaryPurple
                        : (isRestricted ? Colors.grey[400] : Colors.grey[600]),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          badge.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (isRestricted)
                    const Positioned(
                      right: -4,
                      bottom: -2,
                      child: Icon(Icons.lock, size: 10, color: Colors.grey),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? AppColors.primaryPurple : Colors.grey[600],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
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
        Expanded(child: _buildCurrentScreen(isDesktop: false)),
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
                
                // Folgas e Feriados (usa _pendingHolidaysCount do stream principal)
                _buildDrawerItem(
                  icon: Icons.beach_access_rounded,
                  title: "Folgas e Feriados",
                  index: 11,
                  trailing: _pendingHolidaysCount > 0 
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _pendingHolidaysCount.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      )
                    : null,
                ),
                _buildDrawerItem(
                  icon: Icons.receipt_long_rounded,
                  title: "Fiscal NFS-e",
                  index: 12,
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: Icon(icon, color: iconColor ?? color, size: 22),
        title: Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.9),
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
  // DASHBOARD - USA shop_monthly_stats (PRÉ-CALCULADO POR TRIGGER)
  // ============================================================================

  Future<List<Map<String, dynamic>>> _fetchDashboardStats(int year) async {
    if (shopId == null || shopId!.isEmpty) return [];
    try {
      final query = sb.Supabase.instance.client
          .from('shop_monthly_stats')
          .select()
          .eq('shop_id', shopId!);
      final result = year == -1
          ? await query.order('year').order('month')
          : await query.eq('year', year).order('month');
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('❌ [DASHBOARD] Erro ao buscar stats: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTodayAppointments() async {
    if (shopId == null || shopId!.isEmpty) return [];
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
      final result = await sb.Supabase.instance.client
          .from('appointments')
          .select('id, scheduled_at, status, client_name, service_name')
          .eq('shop_id', shopId!)
          .gte('scheduled_at', start.toIso8601String())
          .lte('scheduled_at', end.toIso8601String())
          .order('scheduled_at', ascending: true);
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('❌ [DASHBOARD] Erro ao buscar agendamentos de hoje: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchCommissionAppointments(
      DateTime startData, DateTime endData) async {
    if (shopId == null || shopId!.isEmpty) return [];
    try {
      final result = await sb.Supabase.instance.client
          .from('appointments')
          .select('professional_id, status, total_payable, total_price, total_value, valor_com_desconto, labor_value')
          .eq('shop_id', shopId!)
          .gte('scheduled_at', startData.toIso8601String())
          .lte('scheduled_at', endData.toIso8601String());
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('❌ [DASHBOARD] Erro ao buscar dados de comissão: $e');
      return [];
    }
  }

  void _refreshDashboard() {
    setState(() {
      _statsFuture = null;
      _todayFuture = null;
      _commissionFuture = null;
      _birthdayFuture = null;
      _employeesFuture = null;
    });
  }

  Widget _buildHomeDashboard({required bool isDesktop}) {
    final shopIdReady = shopId != null && shopId!.isNotEmpty;
    if (shopIdReady && (_statsFuture == null || _lastDashboardYear != _selectedYear)) {
      _lastDashboardYear = _selectedYear;
      _statsFuture = _fetchDashboardStats(_selectedYear);
      _todayFuture = _fetchTodayAppointments();
      if (_canViewCommissions) {
        DateTime startData;
        DateTime endData;
        if (_selectedYear == -1) {
          startData = DateTime(2023, 1, 1);
          endData = DateTime(2030, 12, 31);
        } else {
          startData = DateTime(_selectedYear, 1, 1);
          endData = DateTime(_selectedYear, 12, 31, 23, 59, 59);
        }
        _commissionFuture = _fetchCommissionAppointments(startData, endData);
      }
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _statsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('❌ [DASHBOARD] Erro no stats: ${snapshot.error}');
          return Center(child: Text("Erro ao carregar dashboard: ${snapshot.error}"));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (_statsCache.isNotEmpty) {
            return _buildDashboardContent(
              stats: _statsCache, isDesktop: isDesktop, isRefreshing: true);
          }
          return const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple));
        }
        if (snapshot.hasData) {
          _statsCache = snapshot.data!;
        }
        return _buildDashboardContent(
          stats: snapshot.data ?? _statsCache, isDesktop: isDesktop, isRefreshing: false);
      },
    );
  }

  Widget _buildDashboardContent({
    required List<Map<String, dynamic>> stats,
    required bool isDesktop,
    bool isRefreshing = false,
  }) {
    debugPrint(
        "📊 [DASHBOARD] ${stats.length} linhas de stats para $shopId (${_selectedYear == -1 ? 'todos' : _selectedYear}).");

    bool isAllYears = _selectedYear == -1;
    double faturamentoTotal = 0;
    int totalAtendimentos = 0;

    List<double> dataMoney = List.filled(12, 0.0);
    List<double> dataQty = List.filled(12, 0.0);
    List<String> chartLabels = [
      'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
    ];

    Map<int, double> yearMoney = {};
    Map<int, int> yearQty = {};

    // Filtrar por mês se selecionado (e não estiver em "todos os anos")
    final filteredStats = (!isAllYears && _selectedMonth > 0)
        ? stats.where((r) => (r['month'] as num?)?.toInt() == _selectedMonth).toList()
        : stats;

    for (var row in filteredStats) {
      final revenue = (row['revenue'] as num?)?.toDouble() ?? 0;
      final count = (row['appointments_count'] as num?)?.toInt() ?? 0;
      final month = (row['month'] as num?)?.toInt() ?? 1;
      final year = (row['year'] as num?)?.toInt() ?? _selectedYear;

      faturamentoTotal += revenue;
      totalAtendimentos += count;

      if (!isAllYears) {
        if (month >= 1 && month <= 12) {
          dataMoney[month - 1] = revenue;
          dataQty[month - 1] = count.toDouble();
        }
      } else {
        yearMoney[year] = (yearMoney[year] ?? 0) + revenue;
        yearQty[year] = (yearQty[year] ?? 0) + count;
      }
    }

    if (isAllYears && yearMoney.isNotEmpty) {
      chartLabels = yearMoney.keys.map((e) => e.toString()).toList();
      chartLabels.sort();
      dataMoney = chartLabels.map((key) => yearMoney[int.parse(key)] ?? 0.0).toList();
      dataQty = chartLabels.map((key) => (yearQty[int.parse(key)] ?? 0).toDouble()).toList();
    }

    double faturamentoMaoDeObra = faturamentoTotal;
    double faturamentoProdutos = 0;
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
        isRefreshing: isRefreshing,
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
        isRefreshing: isRefreshing,
      );
    }
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
    bool isRefreshing = false,
  }) {
    return Column(
      children: [
        if (isRefreshing)
          const LinearProgressIndicator(
            color: AppColors.primaryPurple,
            backgroundColor: Colors.transparent,
            minHeight: 2,
          ),
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
            Row(
              children: [
                _buildMonthDropdown(),
                const SizedBox(width: 8),
                _buildYearDropdown(),
              ],
            ),
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
        if (shopId != null && _canViewCommissions) ...[
          const SizedBox(height: 16),
          _buildEquipeComissoesCard(shopId!),
        ],
      ],
    );
  }

  Widget _buildEquipeComissoesCard(String shopId) {
    if (_commissionFuture == null) return const SizedBox.shrink();

    _employeesFuture ??= sb.Supabase.instance.client
        .from('employees')
        .select('id, name, commission_percent')
        .eq('shop_id', shopId);

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([_commissionFuture!, _employeesFuture!]),
      builder: (context, snap) {
        if (snap.hasError || !snap.hasData) return const SizedBox.shrink();
        final appointmentDocs = snap.data![0] as List<Map<String, dynamic>>;
        final employees = snap.data![1] as List<Map<String, dynamic>>;
        if (employees.isEmpty) return const SizedBox.shrink();

        // Calcular produção por profissional
        Map<String, double> producaoPorProf = {};
        for (var data in appointmentDocs) {
          final status = (data['status'] ?? '').toString().toLowerCase();
          if (status != 'confirmado' && status != 'concluido') continue;
          final pid = data['professional_id']?.toString() ?? '';
          if (pid.isEmpty) continue;
          double valor = 0.0;
          for (final k in ['total_payable', 'total_price', 'total_value', 'valor_com_desconto', 'labor_value']) {
            final v = double.tryParse(data[k]?.toString() ?? '');
            if (v != null && v > 0) { valor = v; break; }
          }
          producaoPorProf[pid] = (producaoPorProf[pid] ?? 0) + valor;
        }
        double totalComissao = 0;
        final List<Map<String, dynamic>> teamData = [];

        // Preparar dados
        for (var ed in employees) {
          final nome = (ed['name'] ?? ed['nome'])?.toString() ?? 'Profissional';
          final p = ed['commission_percent'];
          final percent = (p is num) ? p.toDouble() : 0.0;
          final produzido = producaoPorProf[ed['id']] ?? 0.0;
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
    bool isRefreshing = false,
  }) {
    final fmt = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return RefreshIndicator(
      color: AppColors.primaryPurple,
      onRefresh: () async {
        _refreshDashboard(); // Invalidate cached futures and rebuild
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isRefreshing)
              const LinearProgressIndicator(
                color: AppColors.primaryPurple,
                backgroundColor: Colors.transparent,
                minHeight: 2,
              ),
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
                    Row(
                      children: [
                        _buildMonthDropdown(dark: true),
                        const SizedBox(width: 8),
                        _buildYearDropdown(dark: true),
                      ],
                    ),
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
                _buildHojeSection(),
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

                if (shopId != null && _canViewCommissions) ...[
                  const SizedBox(height: 12),
                  _buildEquipeComissoesCard(shopId!),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
       ),
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

  Widget _buildHojeSection() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _todayFuture,
      builder: (context, snap) {
        final todayDocs = snap.data ?? [];
        final hoje = todayDocs.length;
        final proximosHoje = todayDocs.where((data) {
          final status = (data['status'] ?? '').toString();
          return status == 'agendado' || status == 'confirmado';
        }).toList();
        return _buildHojeCard(hoje, proximosHoje);
      },
    );
  }

  Widget _buildHojeCard(int hoje, List<Map<String, dynamic>> proximosHoje) {
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
            ...proximosHoje.take(3).map((data) {
              final dateStr = data['scheduled_at'] as String?;
              final date = DateTime.tryParse(dateStr ?? '') ?? DateTime.now();
              final hora = DateFormat('HH:mm').format(date);
              final clienteNome =
                  (data['client_name'] ?? 'Cliente').toString();
              final servico = (data['service_name'] ?? '').toString();
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
                    // ✅ FIX: Clamp para evitar flex: 0 que causa Gray Screen no Flutter
                    flex: (pctServico * 100).round().clamp(1, 100),
                    child: Container(color: const Color(0xFF6C3CE2)),
                  ),
                  Flexible(
                    flex: (pctProduto * 100).round().clamp(1, 100),
                    child: Container(color: const Color(0xFF00C9A7)),
                  ),
                  if (pctServico + pctProduto < 0.99)
                    Flexible(
                      flex: ((1 - pctServico - pctProduto) * 100).round().clamp(1, 100),
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

  Widget _buildMonthDropdown({bool dark = false}) {
    final months = [
      'Todos', 'Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun',
      'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'
    ];
    final isAllYears = _selectedYear == -1;
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
          value: isAllYears ? 0 : _selectedMonth,
          icon: Icon(Icons.calendar_month,
              color: dark ? Colors.white : AppColors.primaryPurple, size: 18),
          dropdownColor: dark ? const Color(0xFF6C3CE2) : null,
          isDense: true,
          items: List.generate(13, (i) => DropdownMenuItem<int>(
            value: i,
            child: Text(
              months[i],
              style: TextStyle(
                fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal,
                color: dark
                    ? (i == 0 ? Colors.white : Colors.white70)
                    : (i == 0 ? AppColors.primaryPurple : null),
                fontSize: 13,
              ),
            ),
          )),
          onChanged: isAllYears ? null : (int? newValue) {
            if (newValue != null) {
              setState(() => _selectedMonth = newValue);
            }
          },
        ),
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

  /// Busca aniversariantes entre os clientes que já agendaram nesta loja.
  /// Usa appointments para identificar client_ids, depois filtra birth_date.
  Future<List<Map<String, dynamic>>> _fetchBirthdayClients() async {
    if (shopId == null) return [];
    try {
      final now = DateTime.now();
      final mmdd = '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Busca clientes distintos desta loja via appointments
      final appts = await sb.Supabase.instance.client
          .from('appointments')
          .select('client_id')
          .eq('shop_id', shopId!)
          .limit(200);
      
      final clientIds = (appts as List)
          .map((a) => a['client_id']?.toString())
          .where((id) => id != null && id.isNotEmpty)
          .toSet()
          .toList();

      if (clientIds.isEmpty) return [];

      // Busca perfis desses clientes
      final users = await sb.Supabase.instance.client
          .from('users')
          .select('id, name, phone, photo_url, birth_date')
          .inFilter('id', clientIds);

      // Filtra pelo dia/mês de nascimento
      return List<Map<String, dynamic>>.from(users).where((u) {
        final birth = u['birth_date']?.toString();
        if (birth == null || birth.isEmpty) return false;
        try {
          final dt = DateTime.parse(birth);
          final userMmdd = '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
          return userMmdd == mmdd;
        } catch (_) {
          return false;
        }
      }).toList();
    } catch (e) {
      debugPrint('[BirthdaysSection] Erro: $e');
      return [];
    }
  }

  Widget _buildBirthdaysSection({required bool isDesktop}) {
    if (shopId == null) return const SizedBox.shrink();

    _birthdayFuture ??= _fetchBirthdayClients();

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _birthdayFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final aniversariantes = snapshot.data!;

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
                    final client = aniversariantes[index];
                    final nome = (client['name'] ?? 'Cliente').toString();
                    final phone = client['phone']?.toString();
                    final foto = client['photo_url']?.toString();

                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: InkWell(
                        onTap: () {
                          if (phone != null && phone.isNotEmpty) {
                            _launchWhatsAppFromPhone(phone);
                          }
                        },
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.pink.shade50,
                              backgroundImage: foto != null && foto.isNotEmpty
                                  ? CachedNetworkImageProvider(foto)
                                  : null,
                              child: (foto == null || foto.isEmpty)
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
      case 9:
        return "Reajuste de Preços";
      case 10:
        return "Privacidade";
      case 11:
        return "Gestão de Folgas";
      case 12:
        return "Fiscal NFS-e";
      default:
        return "";
    }
  }
}
