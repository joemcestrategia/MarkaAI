import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class AppLoadingPage extends StatelessWidget {
  final String? message;
  const AppLoadingPage({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/logo_purple.png', height: 72),
              const SizedBox(height: 20),
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  color: AppColors.primaryPurple,
                  strokeWidth: 3.5,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(message!, style: TextStyle(color: Colors.grey[700])),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
