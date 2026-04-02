import 'package:flutter/material.dart';

class SplashLoadingWidget extends StatefulWidget {
  final String? message;
  const SplashLoadingWidget({super.key, this.message});

  @override
  State<SplashLoadingWidget> createState() => _SplashLoadingWidgetState();
}

class _SplashLoadingWidgetState extends State<SplashLoadingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _floatController;
  late Animation<Offset> _floatAnimation;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _floatAnimation = Tween<Offset>(
      begin: const Offset(0.0, -0.05),
      end: const Offset(0.0, 0.05),
    ).animate(CurvedAnimation(
      parent: _floatController,
      curve: Curves.easeInOutSine,
    ));
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [
              Color(0xFF8B25C6), // Light vivid purple center
              Color(0xFF4A1081), // Deep purple middle
              Color(0xFF230245), // Very dark purple edges
            ],
            radius: 1.5,
            focal: Alignment.center,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SlideTransition(
                    position: _floatAnimation,
                    child: Column(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.1),
                                blurRadius: 40,
                                spreadRadius: -10,
                                offset: const Offset(0, 0),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Image.asset(
                              'assets/images/icon.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'MarkaAI',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.5,
                            shadows: [
                              Shadow(
                                color: Colors.black26,
                                offset: Offset(0, 2),
                                blurRadius: 6,
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Bottom Area with simple loading
            Padding(
              padding: const EdgeInsets.only(bottom: 64.0),
              child: Column(
                children: [
                  if (widget.message != null) ...[
                    Text(
                      widget.message!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        shadows: const [
                          Shadow(
                            color: Colors.black26,
                            offset: Offset(0, 1),
                            blurRadius: 2,
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  // Loading simples (linha)
                  SizedBox(
                    width: 150, // Linha de loading no centro
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: const LinearProgressIndicator(
                        minHeight: 4,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
