import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class ProfileCompletionWidget extends StatelessWidget {
  final String shopId;
  final Map<String, dynamic>? shopData;
  final VoidCallback? onTap;

  const ProfileCompletionWidget({
    super.key,
    required this.shopId,
    this.shopData,
    this.onTap,
  });

  Future<int> _calculateCompletion() async {
    if (shopData == null) return 0;

    int score = 0;
    int total = 5;

    // 1. Basic Info (Name, Category)
    if ((shopData!['nome'] as String?)?.isNotEmpty == true &&
        (shopData!['categoria'] as String?)?.isNotEmpty == true) {
      score++;
    }

    // 2. Logo
    if ((shopData!['logo'] as String?)?.isNotEmpty == true) {
      score++;
    }

    // 3. Description/Bio
    final desc = shopData!['descricao'] as String?;
    if (desc != null && desc.length > 10) {
      score++;
    }

    // 4. Address
    if ((shopData!['endereco'] as String?)?.isNotEmpty == true) {
      score++;
    }

    // 5. Opening Hours (or similar)
    if (shopData!['horarios'] != null) {
      score++;
    }

    return (score / total * 100).toInt();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _calculateCompletion(),
      builder: (context, snapshot) {
        final percentage = snapshot.data ?? 0;

        // Don't show if complete
        if (percentage >= 100) return const SizedBox.shrink();

        return GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(
                horizontal: 0,
                vertical: 8), // Adjusted margin as it's inside padding
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryPurple,
                  AppColors.primaryPurple.withValues(alpha: 0.8)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryPurple.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.rocket_launch,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            "Complete seu perfil!",
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Atraia mais clientes preenchendo todas as informações.",
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percentage / 100,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(Colors.white),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    "$percentage%",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
