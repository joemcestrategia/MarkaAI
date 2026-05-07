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

    final Color bgColor = _isDarkMode ? const Color(0xFF0F1117) : const Color(0xFFF8FAFC);
    final Color cardColor = _isDarkMode ? const Color(0xFF1A1D27) : Colors.white;
    final Color textColor = _isDarkMode ? Colors.white : const Color(0xFF1E293B);
    final Color borderColor = _isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06);

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
      body: Row(
        children: [
          // Sidebar
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
                IconButton(
                  icon: Icon(
                    _isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    color: Colors.grey,
                  ),
                  onPressed: () => setState(() => _isDarkMode = !_isDarkMode),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
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
                    padding: const EdgeInsets.symmetric(horizontal: 24),
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

  Widget _buildSidebarItem(int index, IconData icon) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        width: 48,
        height: 48,
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6366F1) : Colors.transparent,
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
