import 'package:flutter/material.dart';

/// Ícone vetorial do Pente Garfo Afro (Afro Pick), desenvolvido para seguir
/// exatamente o peso visual, escala de grid (24x24) e estilo dos ícones
/// nativos do Material Design do MarkaAI.
class AfroCombIcon extends StatelessWidget {
  final double size;
  final Color color;

  const AfroCombIcon({
    super.key,
    this.size = 20,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _AfroCombPainter(color: color),
    );
  }
}

class _AfroCombPainter extends CustomPainter {
  final Color color;

  const _AfroCombPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final s = size.width / 24.0;
    final path = Path();

    // 1. Barra horizontal de suporte dos dentes
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTRB(3.4 * s, 8.5 * s, 20.6 * s, 11.2 * s),
      Radius.circular(1.3 * s),
    ));

    // 2. Cabo ergonômico no topo (estilo clássico de pente garfo)
    path.addRRect(RRect.fromRectAndRadius(
      Rect.fromLTRB(7.2 * s, 1.8 * s, 16.8 * s, 6.2 * s),
      Radius.circular(2.2 * s),
    ));
    // Pescoço de transição unindo cabo e barra
    path.addRect(Rect.fromLTRB(9.6 * s, 5.0 * s, 14.4 * s, 9.5 * s));

    // 3. Cinco dentes longos, retos e com pontas arredondadas (alto contraste)
    final toothW = 1.8 * s;
    final toothTop = 9.8 * s;
    final toothBottom = 22.0 * s;
    final xs = [4.6 * s, 8.3 * s, 12.0 * s, 15.7 * s, 19.4 * s];

    for (final tx in xs) {
      path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(tx - toothW / 2, toothTop, tx + toothW / 2, toothBottom),
        Radius.circular(toothW / 2),
      ));
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AfroCombPainter oldDelegate) =>
      oldDelegate.color != color;
}
