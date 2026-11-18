import 'package:flutter/material.dart';
import 'package:markaai/core/widgets/premium_splash_widget.dart';

class SplashLoadingWidget extends StatelessWidget {
  final String? message;

  const SplashLoadingWidget({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return PremiumSplashWidget(message: message);
  }
}
