import 'package:flutter/foundation.dart';
import 'dart:io' if (dart.library.html) 'package:flutter_application_1/core/utils/io_stub.dart' as io;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_colors.dart';

class CouponShareService {
  /// Captura um widget usando uma GlobalKey e compartilha como imagem
  static Future<void> shareCoupon({
    required BuildContext context,
    required GlobalKey key,
    required String code,
  }) async {
    try {
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      // Aumentar o tempo para garantir carregamento de imagens de rede (logo)
      await Future.delayed(const Duration(milliseconds: 1500));

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();

      if (kIsWeb) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Compartilhamento de cupom não disponível na Web.')),
          );
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final file = await io.File('${tempDir.path}/coupon_$code.png').create();
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Confira este desconto especial para você!',
        text: 'Confira este desconto especial para você! Use o código: $code',
      );
    } catch (e) {
      debugPrint('Erro ao compartilhar cupom: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao gerar imagem: $e')),
        );
      }
    }
  }

  /// Constrói o widget que será capturado para a imagem de compartilhamento
  static Widget buildShareableCoupon({
    required String shopName,
    required String code,
    required int discount,
    String? logoUrl,
    String? description,
    String? subdomain,
    String? validUntil,
  }) {
    return Container(
      width: 400,
      height: 640,
      padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 30),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryPurple,
            Color(0xFF8E24AA),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo da Loja
          if (logoUrl != null && logoUrl.isNotEmpty) ...[
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                image: DecorationImage(
                  image: CachedNetworkImageProvider(logoUrl),
                  fit: BoxFit.cover,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Nome da Loja
          Text(
            shopName.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 1.5,
            width: 30,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 15),

          // Título
          const Text(
            "VOCÊ GANHOU UM",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "SUPER DESCONTO",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),

          // Badge de Desconto
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "$discount% OFF",
              style: const TextStyle(
                color: AppColors.primaryPurple,
                fontSize: 38,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 15),

          // Descrição do Cupom
          if (description != null && description.isNotEmpty) ...[
            Text(
              description,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 15),
          ],

          // Código
          const Text(
            "USE O CÓDIGO:",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              code,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
          ),

          const SizedBox(height: 2), // Espaço mínimo entre moldura e link

          // Rodapé / Link
          if (subdomain != null && subdomain.isNotEmpty) ...[
            Text(
              "markaai.com.br/$subdomain",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ] else ...[
            const Text(
              "Agende agora pelo link da bio",
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],

          const SizedBox(height: 10),

          if (validUntil != null) ...[
            Text(
              "VÁLIDO ATÉ: $validUntil",
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
          ],

          const SizedBox(height: 15),
          Image.asset(
            'assets/images/logo_white.png',
            height: 28, // Um pouco maior conforme pedido
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }
}
