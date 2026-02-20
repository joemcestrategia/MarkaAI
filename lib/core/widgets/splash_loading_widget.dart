import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class SplashLoadingWidget extends StatefulWidget {
  final String? message;
  const SplashLoadingWidget({super.key, this.message});

  @override
  State<SplashLoadingWidget> createState() => _SplashLoadingWidgetState();
}

class _SplashLoadingWidgetState extends State<SplashLoadingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryPurple.withValues(alpha: 0.1),
                ),
                child: const Icon(
                  Icons.auto_awesome, // Or your app logo
                  size: 60,
                  color: AppColors.primaryPurple,
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor:
                    AlwaysStoppedAnimation<Color>(AppColors.primaryPurple),
                backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.2),
              ),
            ),
            if (widget.message != null) ...[
              const SizedBox(height: 24),
              Text(
                widget.message!,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
