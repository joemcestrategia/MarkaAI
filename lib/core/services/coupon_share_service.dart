import 'package:flutter/foundation.dart';
import 'dart:io' if (dart.library.html) 'package:markaai/core/utils/io_stub.dart' as io;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_colors.dart';
import '../../modules/business/web_helper_stub.dart'
    if (dart.library.js_interop) '../../modules/business/web_helper_real.dart' as web_helper;

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
        web_helper.downloadImageWeb(bytes, 'coupon_$code.png');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Imagem do cupom baixada com sucesso!')),
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
              width: 90, // Aumentado de 70 para 90
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.white, width: 3),
                image: DecorationImage(
                  image: CachedNetworkImageProvider(logoUrl),
                  fit: BoxFit.cover,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Nome da Loja
          Text(
            shopName.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20, // Aumentado
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 2,
            width: 40,
            color: Colors.white.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 20),

          // Título
          const Text(
            "VOCÊ GANHOU UM",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "SUPER DESCONTO",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),

          // Badge de Desconto
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              "$discount% OFF",
              style: const TextStyle(
                color: AppColors.primaryPurple,
                fontSize: 44, // Aumentado
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Descrição do Cupom
          if (description != null && description.isNotEmpty) ...[
            Text(
              description,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Código
          const Text(
            "USE O CÓDIGO NO SITE:",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withValues(alpha: 0.1),
            ),
            child: Text(
              code,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
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
