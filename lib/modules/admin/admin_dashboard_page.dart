import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:markaai/core/services/session_service.dart';
import 'package:markaai/core/widgets/splash_loading_widget.dart';
import 'package:markaai/modules/admin/widgets/admin_overview_widget.dart';
import 'package:markaai/modules/admin/widgets/admin_users_widget.dart';
import 'package:markaai/modules/admin/widgets/admin_shops_widget.dart';
import 'package:markaai/modules/admin/widgets/admin_support_widget.dart';
import 'package:markaai/modules/support/admin_tickets_page.dart';
import 'package:markaai/modules/admin/admin_banners_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  bool _loading = true;
  bool _isAdmin = false;
  bool _isDarkMode = true;
  int _selectedIndex = 0;

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
    if (_loading) {
      return const SplashLoadingWidget(message: "Verificando permissões...");
    }

    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 900;
    final bgColor = theme.scaffoldBackgroundColor;
    final cardColor = theme.cardColor;
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.white;
    final borderColor = theme.dividerColor.withValues(alpha: 0.1);

    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Colors.red[400]),
              const SizedBox(height: 24),
              Text(
                'Acesso Negado',
                style: TextStyle(
                  color: textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Você não tem permissão para acessar esta área.',
                style: TextStyle(color: textColor.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Voltar'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      drawer: isMobile ? _buildDrawer() : null,
      appBar: isMobile 
        ? AppBar(
            title: Text(_getTitleForIndex(_selectedIndex), style: const TextStyle(fontSize: 18)),
            backgroundColor: cardColor,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.grey),
                onPressed: () => setState(() {}),
              ),
            ],
          )
        : null,
      body: Row(
        children: [
          // Sidebar (Desktop only)
          if (!isMobile)
            Container(
              width: 80,
              decoration: BoxDecoration(
                color: cardColor,
                border: Border(right: BorderSide(color: borderColor)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  _buildSidebarItem(0, Icons.grid_view_rounded),
                  _buildSidebarItem(1, Icons.people_rounded),
                  _buildSidebarItem(2, Icons.store_rounded),
                  _buildSidebarItem(3, Icons.handyman_rounded),
                  _buildSidebarItem(4, Icons.confirmation_number_rounded),
                  _buildSidebarItem(5, Icons.campaign_rounded),
                  const Spacer(),
                  const SizedBox(height: 24),
                ],
              ),
            ),

          // Main Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header (Desktop only)
                if (!isMobile)
                  Container(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Text(
                          _getTitleForIndex(_selectedIndex),
                          style: TextStyle(
                            color: textColor,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, color: Colors.grey),
                          onPressed: () => setState(() {}),
                        ),
                      ],
                    ),
                  ),

                // Content Area
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24),
                    child: _buildContent(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: AppColors.primaryPurple),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.admin_panel_settings, color: Colors.white, size: 48),
                  const SizedBox(height: 8),
                  Text('MarkaAI Admin', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          _buildDrawerItem(0, Icons.grid_view_rounded, 'Overview'),
          _buildDrawerItem(1, Icons.people_rounded, 'Usuários'),
          _buildDrawerItem(2, Icons.store_rounded, 'Negócios'),
          _buildDrawerItem(3, Icons.handyman_rounded, 'Suporte'),
          _buildDrawerItem(4, Icons.confirmation_number_rounded, 'Tickets'),
          _buildDrawerItem(5, Icons.campaign_rounded, 'Banners'),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(int index, IconData icon, String title) {
    final isSelected = _selectedIndex == index;
    return ListTile(
      leading: Icon(icon, color: isSelected ? AppColors.primaryPurple : Colors.grey),
      title: Text(title, style: TextStyle(color: isSelected ? AppColors.primaryPurple : null, fontWeight: isSelected ? FontWeight.bold : null)),
      selected: isSelected,
      onTap: () {
        setState(() => _selectedIndex = index);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildSidebarItem(int index, IconData icon) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        width: 48,
        height: 48,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryPurple : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isSelected ? Colors.white : Colors.grey,
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return const AdminOverviewWidget();
      case 1:
        return const AdminUsersWidget();
      case 2:
        return const AdminShopsWidget();
      case 3:
        return const AdminSupportWidget();
      case 4:
        return const AdminTicketsPage(embedded: true);
      case 5:
        return const AdminBannersPage();
      default:
        return const Center(child: Text('Página não encontrada'));
    }
  }

  String _getTitleForIndex(int index) {
    switch (index) {
      case 0:
        return 'Overview';
      case 1:
        return 'Gerenciar Usuários';
      case 2:
        return 'Gerenciar Negócios';
      case 3:
        return 'Ferramentas de Suporte';
      case 4:
        return 'Tickets de Suporte';
      case 5:
        return 'Banners de Marketing';
      default:
        return 'Admin Dashboard';
    }
  }
}
