import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Para saber se é Web

class WebContainer extends StatelessWidget {
  final Widget child;
  // Define uma cor de fundo para o site (fora do app)
  final Color backgroundColor;

  const WebContainer({
    super.key,
    required this.child,
    this.backgroundColor = const Color(0xFFF0F2F5), // Cinza clarinho padrão web
  });

  @override
  Widget build(BuildContext context) {
    // Se for Web, aplica a contenção
    if (kIsWeb) {
      return Container(
        color: backgroundColor, // Fundo da página inteira
        child: Center(
          child: ConstrainedBox(
            // TÁTICA: Limita a largura a 500px (tamanho de um tablet/celular grande)
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white, // Fundo do App
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    // Se for Android/iOS, não faz nada (deixa ocupar tudo)
    return child;
  }
}
