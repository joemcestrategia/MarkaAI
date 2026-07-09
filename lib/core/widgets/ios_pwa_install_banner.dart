import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:markaai/core/theme/app_colors.dart';
import 'package:markaai/core/utils/pwa_utils.dart';
import 'package:flutter/cupertino.dart';

class IosPwaInstallBanner extends StatefulWidget {
  final Widget child;
  const IosPwaInstallBanner({super.key, required this.child});

  @override
  State<IosPwaInstallBanner> createState() => _IosPwaInstallBannerState();
}

class _IosPwaInstallBannerState extends State<IosPwaInstallBanner> with SingleTickerProviderStateMixin {
  bool _showBanner = false;
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, 1.5), // Começa abaixo da tela
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));
    _checkIosInstall();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkIosInstall() async {
    if (!kIsWeb) return;
    
    // Check if it's iOS
    final bool isIos = defaultTargetPlatform == TargetPlatform.iOS;
    if (!isIos) return;

    if (isPwaStandalone()) return;

    // Aguarda um pouco para o usuário não ser bombardeado logo ao abrir a página
    await Future.delayed(const Duration(seconds: 3));

    // Check SharedPreferences if already dismissed
    final prefs = await SharedPreferences.getInstance();
    final bool dismissed = prefs.getBool('ios_pwa_install_dismissed') ?? false;

    if (!dismissed) {
      if (mounted) {
        setState(() {
          _showBanner = true;
        });
        _controller.forward();
      }
    }
  }

  void _dismissBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ios_pwa_install_dismissed', true);
    
    await _controller.reverse();
    if (mounted) {
      setState(() {
        _showBanner = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showBanner)
          Positioned(
            bottom: 32, // Acima de uma possível barra de navegação do iPhone
            left: 20,
            right: 20,
            child: Material(
              color: Colors.transparent,
              child: SlideTransition(
                position: _offsetAnimation,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 24,
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    border: Border.all(color: AppColors.primaryPurple.withOpacity(0.15)),
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.primaryPurple.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                CupertinoIcons.share,
                                color: AppColors.primaryPurple,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Instale nosso App',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 17,
                                      color: Color(0xFF111827),
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Para um acesso rápido e uma experiência nativa, instale o MarkaAI na sua tela de início.',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF4B5563),
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  RichText(
                                    text: const TextSpan(
                                      style: TextStyle(fontSize: 14, color: Color(0xFF111827), height: 1.5),
                                      children: [
                                        TextSpan(text: 'Toque em '),
                                        WidgetSpan(
                                          child: Icon(CupertinoIcons.share, size: 16, color: AppColors.primaryPurple),
                                          alignment: PlaceholderAlignment.middle,
                                        ),
                                        TextSpan(text: ' abaixo e depois selecione '),
                                        TextSpan(text: '"Adicionar à Tela de Início"', style: TextStyle(fontWeight: FontWeight.w600)),
                                        TextSpan(text: '.'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          onPressed: _dismissBanner,
                          icon: const Icon(Icons.close_rounded, size: 22, color: Color(0xFF9CA3AF)),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          splashRadius: 20,
                        ),
                      ),
                      // Setinha apontando para baixo
                      Positioned(
                        bottom: -10,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: AppColors.primaryPurple.withOpacity(0.5),
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
