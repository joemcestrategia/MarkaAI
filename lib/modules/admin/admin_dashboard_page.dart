import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_person_rounded, size: 48, color: Colors.redAccent),
                ),
                const SizedBox(height: 32),
                Text(
                  'Acesso Restrito',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Esta área é exclusiva para administradores oficiais do MarkaAI.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _isDarkMode ? Colors.grey[400] : Colors.grey[600], fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Atenção: Por motivos de segurança, não é possível criar contas de administrador pela interface. O processo é 100% manual e direto no banco de dados.',
                          style: TextStyle(color: Colors.amber[700], fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushReplacementNamed(context, '/'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F8EF7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('VOLTAR PARA O INÍCIO', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
                  },
                  child: Text(
                    'Trocar de Conta',
                    style: TextStyle(color: Colors.grey[500], fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;

        return Theme(
          data: (_isDarkMode ? ThemeData.dark() : ThemeData.light()).copyWith(
            scaffoldBackgroundColor: bgColor,
            cardColor: cardColor,
            dividerColor: borderColor,
            primaryColor: const Color(0xFF4F8EF7),
          ),
          child: isDesktop ? _buildDesktopLayout(bgColor, cardColor, textColor, borderColor) : _buildMobileLayout(bgColor, cardColor, textColor, borderColor),
        );
      },
    );
  }

  Widget _buildDesktopLayout(Color bgColor, Color cardColor, Color textColor, Color borderColor) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 260,
            decoration: BoxDecoration(
              color: cardColor,
              border: Border(
                right: BorderSide(
                  color: borderColor,
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MarkaAI',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const Text(
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
                _buildMenuItem(0, Icons.grid_view_rounded, 'Dashboard', textColor),
                _buildMenuItem(1, Icons.people_outline_rounded, 'Usuários', textColor),
                _buildMenuItem(2, Icons.storefront_outlined, 'Negócios', textColor),
                _buildMenuItem(3, Icons.support_agent_rounded, 'Suporte', textColor),
                const Spacer(),
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.03),
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
                        title: Text('Admin Master',
                            style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Sair do sistema',
                            style: TextStyle(color: Colors.grey, fontSize: 10)),
                        onTap: () {
                          FirebaseAuth.instance.signOut();
                          Navigator.pushReplacementNamed(context, '/login');
                        },
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
                _buildTopBar(bgColor, cardColor, textColor, borderColor),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: bgColor,
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

  Widget _buildMobileLayout(Color bgColor, Color cardColor, Color textColor, Color borderColor) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('MarkaAI Admin', style: TextStyle(fontWeight: FontWeight.w900, color: textColor)),
        backgroundColor: cardColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: textColor),
            onPressed: () => setState(() => _isDarkMode = !_isDarkMode),
          ),
        ],
      ),
      body: _buildContent(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: borderColor)),
        ),
        child: BottomNavigationBar(
          backgroundColor: cardColor,
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

  Widget _buildMenuItem(int index, IconData icon, String label, Color textColor) {
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
                color: isSelected ? textColor : Colors.grey,
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

  Widget _buildTopBar(Color bgColor, Color cardColor, Color textColor, Color borderColor) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(
            color: borderColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            _getTitleForIndex(_selectedIndex),
            style: TextStyle(
              color: textColor,
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
              color: textColor.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
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
          // Theme Toggle
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                _buildThemeButton(true, Icons.dark_mode_rounded),
                _buildThemeButton(false, Icons.light_mode_rounded),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Icon(Icons.notifications_none_rounded, color: Colors.grey),
          const SizedBox(width: 24),
          Container(
            height: 32,
            width: 1,
            color: borderColor,
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
                        style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
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

  Widget _buildThemeButton(bool isDark, IconData icon) {
    final isSelected = _isDarkMode == isDark;
    return GestureDetector(
      onTap: () => setState(() => _isDarkMode = isDark),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4F8EF7) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
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
