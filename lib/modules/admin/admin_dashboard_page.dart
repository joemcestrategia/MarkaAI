import 'package:flutter/material.dart';
import 'package:markaai/core/services/session_service.dart';
import 'package:markaai/modules/admin/widgets/admin_overview_widget.dart';
import 'package:markaai/modules/admin/widgets/admin_metrics_widget.dart';
import 'package:markaai/modules/admin/widgets/admin_shops_widget.dart';
import 'package:markaai/modules/admin/widgets/admin_users_widget.dart';
import 'package:markaai/modules/admin/widgets/admin_support_widget.dart';
import 'package:markaai/modules/support/admin_tickets_page.dart';
import 'package:markaai/modules/admin/admin_banners_page.dart';
import 'package:markaai/modules/admin/admin_splash_page.dart';
import 'package:markaai/modules/admin/widgets/admin_finance_widget.dart';
import 'package:markaai/modules/admin/widgets/admin_notifications_widget.dart';
import 'package:markaai/modules/admin/widgets/admin_monitoring_widget.dart';
import 'package:markaai/modules/admin/widgets/admin_orphan_payments_widget.dart';
import 'package:markaai/modules/admin/widgets/admin_feature_flags_widget.dart';
import 'package:markaai/modules/admin/widgets/admin_emails_widget.dart';
import 'package:markaai/modules/admin/widgets/admin_whatsapp_widget.dart';
import 'package:markaai/core/theme/app_colors.dart';

enum AdminSection {
  overview,
  metrics,
  tenants,
  users,
  finance,
  notifications,
  monitoring,
  orphanPayments,
  featureFlags,
  support,
  tickets,
  banners,
  splash,
  emails,
  whatsapp,
}

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  bool _loading = true;
  bool _isAdmin = false;
  bool _isDarkMode = true;
  AdminSection _currentSection = AdminSection.overview;

  @override
  void initState() {
    super.initState();
    _checkAdminAccess();
  }

  Future<void> _checkAdminAccess() async {
    final isAdmin = await SessionService.isAdmin();
    setState(() {
      _isAdmin = isAdmin;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: cs.error),
                const SizedBox(height: 16),
                Text('Acesso Restrito', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: cs.onSurface)),
                const SizedBox(height: 8),
                Text('Você não tem permissão para acessar esta área.', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
              ],
            ),
          ),
        ),
      );
    }

    final isMobile = MediaQuery.of(context).size.width < 1100;
    
    final localTheme = _isDarkMode 
      ? ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          primaryColor: AppColors.primaryPurple,
          scaffoldBackgroundColor: const Color(0xFF0A0C10),
          cardColor: const Color(0xFF141820),
          dividerColor: Colors.white10,
          textTheme: const TextTheme(
            bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
            bodyMedium: TextStyle(color: Colors.white70, fontSize: 14),
            titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF141820),
            foregroundColor: Colors.white,
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.white),
          ),
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primaryPurple,
            surface: Color(0xFF141820),
            onSurface: Colors.white,
            secondary: AppColors.gold,
          ),
        )
      : ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          primaryColor: AppColors.primaryPurple,
          scaffoldBackgroundColor: const Color(0xFFF0F2F5),
          cardColor: Colors.white,
          dividerColor: Colors.black12,
          textTheme: const TextTheme(
            bodyLarge: TextStyle(color: Color(0xFF1A1A1A), fontSize: 16),
            bodyMedium: TextStyle(color: Color(0xFF4A4A4A), fontSize: 14),
            titleLarge: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF1A1A1A),
            elevation: 0,
            iconTheme: IconThemeData(color: Color(0xFF1A1A1A)),
          ),
          colorScheme: const ColorScheme.light(
            primary: AppColors.primaryPurple,
            surface: Colors.white,
            onSurface: Color(0xFF1A1A1A),
            secondary: AppColors.gold,
          ),
        );

    return Theme(
      data: localTheme,
      child: Scaffold(
        backgroundColor: localTheme.scaffoldBackgroundColor,
        drawer: isMobile ? _buildSidebar(isMobile: true, localTheme: localTheme) : null,
        appBar: isMobile
            ? AppBar(
                iconTheme: IconThemeData(color: localTheme.colorScheme.onSurface),
                title: Text(_getSectionTitle(_currentSection), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: localTheme.colorScheme.onSurface)),
                backgroundColor: localTheme.scaffoldBackgroundColor,
                elevation: 0,
                actions: [
                  IconButton(
                    icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode, color: localTheme.colorScheme.onSurface),
                    onPressed: () => setState(() => _isDarkMode = !_isDarkMode),
                  ),
                  const SizedBox(width: 8),
                ],
              )
            : null,
        body: Container(
          color: localTheme.scaffoldBackgroundColor,
          child: Row(
            children: [
              if (!isMobile) _buildSidebar(isMobile: false, localTheme: localTheme),
              Expanded(
                child: Column(
                  children: [
                    if (!isMobile) _buildHeader(localTheme.colorScheme),
                    Expanded(
                      child: Container(
                        margin: isMobile ? EdgeInsets.zero : const EdgeInsets.only(left: 0, right: 24, bottom: 24),
                        decoration: BoxDecoration(
                          color: localTheme.scaffoldBackgroundColor,
                          borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(24),
                        ),
                        child: ClipRRect(
                          borderRadius: isMobile ? BorderRadius.zero : BorderRadius.circular(24),
                          child: Container(
                            color: localTheme.cardColor,
                            child: _buildContent(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_getSectionTitle(_currentSection), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: cs.onSurface)),
              Text('Painel de Controle Administrativo', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6), fontSize: 14)),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 14, color: cs.primary),
                const SizedBox(width: 6),
                Text('Admin Mode', style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode, color: cs.onSurface.withValues(alpha: 0.5)),
            onPressed: () => setState(() => _isDarkMode = !_isDarkMode),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: cs.onSurface.withValues(alpha: 0.5)),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar({required bool isMobile, required ThemeData localTheme}) {
    final cs = localTheme.colorScheme;
    final cardColor = cs.surface;
    final textColor = cs.onSurface;

    return Drawer(
      backgroundColor: cardColor,
      child: Container(
        width: isMobile ? null : 280,
        color: cardColor,
        child: Column(
          children: [
            if (!isMobile) ...[
              const SizedBox(height: 40),
              Icon(Icons.auto_awesome, size: 40, color: cs.primary),
              const SizedBox(height: 12),
              Text('MarkaAI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor)),
              const SizedBox(height: 40),
            ],
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildSidebarGroup('MÉTRICAS', localTheme),
                  _buildSidebarItem(AdminSection.overview, Icons.grid_view_rounded, 'Overview', localTheme),
                  _buildSidebarItem(AdminSection.metrics, Icons.analytics_outlined, 'KPIs Financeiros', localTheme),
                  
                  const SizedBox(height: 24),
                  _buildSidebarGroup('OPERAÇÕES', localTheme),
                  _buildSidebarItem(AdminSection.tenants, Icons.store_rounded, 'Lojas', localTheme),
                  _buildSidebarItem(AdminSection.users, Icons.people_outline, 'Usuários', localTheme),
                  _buildSidebarItem(AdminSection.finance, Icons.payments_outlined, 'Financeiro', localTheme),
                  
                  const SizedBox(height: 24),
                  _buildSidebarGroup('COMUNICAÇÃO', localTheme),
                  _buildSidebarItem(AdminSection.notifications, Icons.campaign_outlined, 'Notificações', localTheme),
                  _buildSidebarItem(AdminSection.banners, Icons.photo_library_outlined, 'Banners', localTheme),
                  _buildSidebarItem(AdminSection.splash, Icons.auto_awesome_outlined, 'Splash Screen', localTheme),
                  _buildSidebarItem(AdminSection.emails, Icons.email_outlined, 'Emails', localTheme),
                  _buildSidebarItem(AdminSection.whatsapp, Icons.chat_bubble_outline, 'WhatsApp Logs', localTheme),
                  
                  const SizedBox(height: 24),
                  _buildSidebarGroup('SISTEMA', localTheme),
                  _buildSidebarItem(AdminSection.monitoring, Icons.monitor_heart_outlined, 'Monitoramento', localTheme),
                  _buildSidebarItem(AdminSection.orphanPayments, Icons.warning_amber_rounded, 'Pagamentos Órfãos', localTheme),
                  _buildSidebarItem(AdminSection.featureFlags, Icons.flag_outlined, 'Feature Flags', localTheme),
                  
                  const SizedBox(height: 24),
                  _buildSidebarGroup('SUPORTE', localTheme),
                  _buildSidebarItem(AdminSection.tickets, Icons.confirmation_number_outlined, 'Tickets', localTheme),
                  _buildSidebarItem(AdminSection.support, Icons.handyman_outlined, 'Ferramentas', localTheme),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text('v1.2.0 • Prod', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5), fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarGroup(String title, ThemeData localTheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Text(title, style: TextStyle(color: Colors.grey.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
    );
  }

  Widget _buildSidebarItem(AdminSection section, IconData icon, String title, ThemeData localTheme) {
    final cs = localTheme.colorScheme;
    final isSelected = _currentSection == section;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        onTap: () {
          setState(() => _currentSection = section);
          if (MediaQuery.of(context).size.width < 1100) Navigator.pop(context);
        },
        leading: Icon(icon, color: isSelected ? cs.primary : cs.onSurface.withValues(alpha: 0.5), size: 20),
        title: Text(title, style: TextStyle(color: isSelected ? cs.primary : null, fontWeight: isSelected ? FontWeight.bold : null, fontSize: 14)),
        selected: isSelected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selectedTileColor: cs.primary.withValues(alpha: 0.05),
      ),
    );
  }

  Widget _buildContent() {
    switch (_currentSection) {
      case AdminSection.overview: return const AdminOverviewWidget();
      case AdminSection.metrics: return const AdminMetricsWidget();
      case AdminSection.tenants: return const AdminShopsWidget();
      case AdminSection.users: return const AdminUsersWidget();
      case AdminSection.finance: return const AdminFinanceWidget();
      case AdminSection.notifications: return const AdminNotificationsWidget();
      case AdminSection.monitoring: return const AdminMonitoringWidget();
      case AdminSection.orphanPayments: return const AdminOrphanPaymentsWidget();
      case AdminSection.featureFlags: return const AdminFeatureFlagsWidget();
      case AdminSection.support: return const AdminSupportWidget();
      case AdminSection.tickets: return const AdminTicketsPage(embedded: true);
      case AdminSection.banners: return const AdminBannersPage();
      case AdminSection.splash: return const AdminSplashPage();
      case AdminSection.emails: return const AdminEmailsWidget();
      case AdminSection.whatsapp: return const AdminWhatsappWidget();
    }
  }

  String _getSectionTitle(AdminSection section) {
    switch (section) {
      case AdminSection.overview: return 'Overview';
      case AdminSection.metrics: return 'KPIs Financeiros';
      case AdminSection.tenants: return 'Lojas';
      case AdminSection.users: return 'Usuários';
      case AdminSection.finance: return 'Financeiro';
      case AdminSection.notifications: return 'Comunicação';
      case AdminSection.monitoring: return 'Monitoramento';
      case AdminSection.orphanPayments: return 'Pagamentos Órfãos';
      case AdminSection.featureFlags: return 'Feature Flags';
      case AdminSection.support: return 'Suporte';
      case AdminSection.tickets: return 'Tickets';
      case AdminSection.banners: return 'Marketing Banners';
      case AdminSection.splash: return 'Splash Screen';
      case AdminSection.emails: return 'Emails';
      case AdminSection.whatsapp: return 'WhatsApp Logs';
    }
  }
}
