import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/widgets/splash_loading_widget.dart';
import 'widgets/admin_overview_widget.dart';
import 'widgets/admin_users_widget.dart';
import 'widgets/admin_shops_widget.dart';
import 'widgets/admin_support_widget.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  bool _loading = true;
  bool _isAdmin = false;
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

    if (!_isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Acesso Negado'),
          backgroundColor: AppColors.primaryPurple,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, size: 80, color: Colors.grey[400]),
              const SizedBox(height: 20),
              const Text(
                'Acesso Restrito',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'Você não tem permissão para acessar esta área.',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Voltar'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;

        return Theme(
          data: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF0F1117),
            cardColor: const Color(0xFF1A1D27),
            dividerColor: Colors.white.withValues(alpha: 0.06),
          ),
          child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
        );
      },
    );
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 260,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1D27),
              border: Border(
                right: BorderSide(
                  color: Colors.white.withValues(alpha: 0.06),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4F8EF7), Color(0xFF7C5CFC)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF4F8EF7).withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.analytics_outlined,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MarkaAI',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Text(
                            'PANEL ADMIN',
                            style: TextStyle(
                              color: Color(0xFF4F8EF7),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                _buildMenuItem(0, Icons.grid_view_rounded, 'Dashboard'),
                _buildMenuItem(1, Icons.people_outline_rounded, 'Usuários'),
                _buildMenuItem(2, Icons.storefront_outlined, 'Negócios'),
                _buildMenuItem(3, Icons.support_agent_rounded, 'Suporte'),
                const Spacer(),
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: const Color(0xFF4F8EF7).withValues(alpha: 0.2),
                          child: const Icon(Icons.person, color: Color(0xFF4F8EF7), size: 20),
                        ),
                        title: const Text('Admin Master',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Sair do sistema',
                            style: TextStyle(color: Colors.grey, fontSize: 10)),
                        onTap: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          // Main Content
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F1117),
                    ),
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

  Widget _buildMobileLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MarkaAI Admin', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: const Color(0xFF1A1D27),
        elevation: 0,
      ),
      body: _buildContent(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
        ),
        child: BottomNavigationBar(
          backgroundColor: const Color(0xFF1A1D27),
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFF4F8EF7),
          unselectedItemColor: Colors.grey,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Dash'),
            BottomNavigationBarItem(icon: Icon(Icons.people_outline_rounded), label: 'Usuários'),
            BottomNavigationBarItem(icon: Icon(Icons.storefront_outlined), label: 'Lojas'),
            BottomNavigationBarItem(icon: Icon(Icons.support_agent_rounded), label: 'Suporte'),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F8EF7).withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected 
              ? Border.all(color: const Color(0xFF4F8EF7).withValues(alpha: 0.2))
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFF4F8EF7) : Colors.grey,
              size: 20,
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 14,
              ),
            ),
            if (isSelected) ...[
              const Spacer(),
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Color(0xFF4F8EF7),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1117),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            _getTitleForIndex(_selectedIndex),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          // Search Mockup
          Container(
            width: 300,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: Colors.grey, size: 18),
                const SizedBox(width: 12),
                Text('Pesquisa global...', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 24),
          const Icon(Icons.notifications_none_rounded, color: Colors.grey),
          const SizedBox(width: 24),
          Container(
            height: 32,
            width: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
          const SizedBox(width: 24),
          FutureBuilder<User?>(
            future: Future.value(FirebaseAuth.instance.currentUser),
            builder: (context, snapshot) {
              final user = snapshot.data;
              return Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        user?.displayName ?? 'Admin Master',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        'Full Access',
                        style: TextStyle(color: Color(0xFF4F8EF7), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF4F8EF7).withValues(alpha: 0.1),
                    child: const Icon(Icons.person_outline, color: Color(0xFF4F8EF7), size: 20),
                  ),
                ],
              );
            },
          ),
        ],
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
      default:
        return 'Admin Dashboard';
    }
  }
}
