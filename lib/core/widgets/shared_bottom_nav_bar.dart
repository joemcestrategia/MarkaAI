import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../../modules/clients/client_home_page.dart';

class SharedBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;

  const SharedBottomNavBar({
    super.key,
    required this.selectedIndex,
    this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (idx) {
        if (onDestinationSelected != null) {
          onDestinationSelected!(idx);
        } else {
          if (idx == selectedIndex) return;
          // Redireciona para a home page do cliente com a aba correta
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => ClientHomePage(initialTabIndex: idx),
            ),
            (r) => false,
          );
        }
      },
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
    );
  }
}
