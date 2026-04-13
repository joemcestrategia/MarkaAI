import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

enum AppInfoType { error, success, info, warning }

class AppInfoModal extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final String buttonText;
  final AppInfoType type;
  final VoidCallback? onConfirm;

  const AppInfoModal({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    this.buttonText = 'Entendi',
    this.type = AppInfoType.info,
    this.onConfirm,
  });

  static void show(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    String buttonText = 'Entendi',
    AppInfoType type = AppInfoType.info,
    VoidCallback? onConfirm,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AppInfoModal(
        title: title,
        message: message,
        icon: icon,
        buttonText: buttonText,
        type: type,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color primaryColor;
    switch (type) {
      case AppInfoType.error:
        primaryColor = Colors.redAccent;
        break;
      case AppInfoType.success:
        primaryColor = Colors.green;
        break;
      case AppInfoType.warning:
        primaryColor = Colors.orange;
        break;
      case AppInfoType.info:
      default:
        primaryColor = AppColors.primaryPurple;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            
            CircleAvatar(
              radius: 36,
              backgroundColor: primaryColor.withValues(alpha: 0.1),
              child: Icon(icon, size: 36, color: primaryColor),
            ),
            const SizedBox(height: 20),
            
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 12),
            
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                if (onConfirm != null) onConfirm!();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: Text(
                buttonText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
