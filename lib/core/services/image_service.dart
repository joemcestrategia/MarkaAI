import 'dart:io' if (dart.library.html) 'package:markaai/core/utils/io_stub.dart' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image/image.dart' as img;


enum ImageContext { avatar, cover, service }

class CompressionResult {
  final Uint8List bytes;
  final int size;
  final double quality;
  final int width;
  final int height;
  final bool isJpeg;

  CompressionResult({
    required this.bytes,
    required this.size,
    required this.quality,
    required this.width,
    required this.height,
    this.isJpeg = false,
  });

  String get extension => isJpeg ? '.jpg' : '.webp';
  String get contentType => isJpeg ? 'image/jpeg' : 'image/webp';
}

class ImageService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Detecta iOS de forma segura (retorna false na Web)
  static bool get _isIOS => !kIsWeb && io.Platform.isIOS;

  /// Função central para compressão inteligente
  static Future<CompressionResult> compressImage({
    required dynamic file, // File (mobile) ou Uint8List/XFile (web)
    required ImageContext context,
  }) async {
    int maxWidth;
    int maxHeight;
    double targetQuality;
    int maxSizeBytes;
    bool shouldCrop = false;

    // Configurações por contexto
    switch (context) {
      case ImageContext.cover:
        maxWidth = 1200;
        maxHeight = 400;
        targetQuality = 0.80;
        maxSizeBytes = 200 * 1024; // 200 KB
        shouldCrop = true;
        break;
      case ImageContext.avatar:
        maxWidth = 400;
        maxHeight = 400;
        targetQuality = 0.85;
        maxSizeBytes = 150 * 1024; // 150 KB (increased from 80 KB — iPhone HEIC photos need more room)
        shouldCrop = true;
        break;
      case ImageContext.service:
        maxWidth = 800;
        maxHeight = 600;
        targetQuality = 0.82;
        maxSizeBytes = 150 * 1024; // 150 KB
        shouldCrop = false;
        break;
    }

    // Lê bytes IMEDIATAMENTE — no iOS o path temporário pode ser invalidado após qualquer await
    Uint8List originalBytes;
    if (file is XFile) {
      originalBytes = await file.readAsBytes();
    } else if (file is io.File) {
      originalBytes = Uint8List.fromList(await file.readAsBytes());
    } else if (file is Uint8List) {
      originalBytes = file;
    } else {
      throw Exception('Tipo de arquivo não suportado para compressão: ${file.runtimeType}');
    }

    if (originalBytes.isEmpty) {
      throw Exception('Arquivo de imagem vazio — não foi possível ler os bytes.');
    }

    // 1. Processamento Inicial (Resize/Crop se necessário usando 'image' package)
    img.Image? decodedImage = img.decodeImage(originalBytes);
    if (decodedImage == null) throw Exception('Não foi possível decodificar a imagem');

    img.Image processedImage;
    if (shouldCrop) {
      // Calcula proporção alvo
      double targetAspect = maxWidth / maxHeight;
      double originalAspect = decodedImage.width / decodedImage.height;

      int cropWidth, cropHeight, cropX, cropY;

      if (originalAspect > targetAspect) {
        // Original é mais larga que o alvo -> corta laterais
        cropHeight = decodedImage.height;
        cropWidth = (decodedImage.height * targetAspect).toInt();
        cropX = (decodedImage.width - cropWidth) ~/ 2;
        cropY = 0;
      } else {
        // Original é mais alta que o alvo -> corta topo/fundo
        cropWidth = decodedImage.width;
        cropHeight = (decodedImage.width / targetAspect).toInt();
        cropX = 0;
        cropY = (decodedImage.height - cropHeight) ~/ 2;
      }

      processedImage = img.copyCrop(decodedImage, x: cropX, y: cropY, width: cropWidth, height: cropHeight);
      processedImage = img.copyResize(processedImage, width: maxWidth, height: maxHeight, interpolation: img.Interpolation.average);
    } else {
      // Apenas redimensiona mantendo proporção
      processedImage = img.copyResize(decodedImage, width: maxWidth, height: maxHeight, interpolation: img.Interpolation.average, maintainAspect: true);
    }

    Uint8List processedBytes = Uint8List.fromList(img.encodeJpg(processedImage)); // Usa JPG intermediário para o compress
    
    // 2. Loop de Compressão Inteligente
    // Na Web e no iOS, usar JPEG (WebP pode falhar em Safari/iOS; HEIC→WebP falha silenciosamente)
    final bool useJpeg = kIsWeb || _isIOS;
    final CompressFormat outputFormat = useJpeg ? CompressFormat.jpeg : CompressFormat.webp;

    final List<double> scales = [1.0, 0.75, 0.5];
    final List<double> qualities = [targetQuality, 0.60, 0.40, 0.20];
    
    Uint8List? bestEffortBytes;
    int bestEffortSize = 0;
    double finalQuality = targetQuality;
    int finalWidth = processedImage.width;
    int finalHeight = processedImage.height;
    bool achievedTarget = false;
    Uint8List? compressedBytes;

    for (final scale in scales) {
      final int currentWidth = (maxWidth * scale).toInt();
      final int currentHeight = (maxHeight * scale).toInt();

      for (final double quality in qualities) {
        if (quality > targetQuality) continue; // Respeita a qualidade original do contexto
        
        Uint8List compressed;
        try {
          compressed = await FlutterImageCompress.compressWithList(
            processedBytes,
            minWidth: currentWidth,
            minHeight: currentHeight,
            quality: (quality * 100).toInt(),
            format: outputFormat,
          );
        } catch (e) {
          // Fallback: Na web, FlutterImageCompress pode falhar com certos formatos.
          // Usa o pacote 'image' puro (Dart puro, funciona em todas as plataformas).
          if (kDebugMode) {
            print('AVISO: FlutterImageCompress falhou ($e). Usando fallback Dart puro.');
          }
          final fallbackImage = img.copyResize(processedImage,
              width: currentWidth, height: currentHeight,
              interpolation: img.Interpolation.average);
          compressed = Uint8List.fromList(
            img.encodeJpg(fallbackImage, quality: (quality * 100).toInt()),
          );
        }

        final currentSize = compressed.length;

        // Mantém o menor resultado possível em memória para um eventual fallback
        bestEffortBytes = compressed;
        bestEffortSize = currentSize;
        finalQuality = quality;
        finalWidth = currentWidth;
        finalHeight = currentHeight;

        if (currentSize <= maxSizeBytes) {
          compressedBytes = compressed;
          achievedTarget = true;
          break;
        }
      }
      if (achievedTarget) break;
    }

    if (!achievedTarget && bestEffortBytes != null) {
      // Loga um warning em vez de lançar exceção, mantendo o fluxo funcionando
      if (kDebugMode) {
        print('AVISO: Não foi possível atingir o tamanho alvo de ${maxSizeBytes ~/ 1024}KB. '
              'Tamanho final retornado: ${bestEffortSize ~/ 1024}KB.');
      }
      compressedBytes = bestEffortBytes;
    } else if (compressedBytes == null) {
      // Trata cenário inesperado (se compressWithList falhar sempre)
      compressedBytes = processedBytes;
      bestEffortSize = compressedBytes.length;
    }

    if (compressedBytes.isEmpty) {
      throw Exception('Compressão resultou em imagem vazia.');
    }

    return CompressionResult(
      bytes: compressedBytes,
      size: bestEffortSize,
      quality: finalQuality,
      width: finalWidth,
      height: finalHeight,
      isJpeg: useJpeg,
    );
  }

  /// Upload genérico para o Supabase Storage com suporte a progresso
  static Future<String> uploadImageToSupabase({
    required Uint8List bytes,
    required String path,
    required String bucket,
    String contentType = 'image/webp',
    void Function(double)? onProgress,
  }) async {
    try {
      if (bytes.isEmpty) {
        throw Exception('Tentativa de upload com 0 bytes.');
      }

      // Nota: O SDK do Supabase Flutter não fornece progresso nativo para uploadBinary ainda.
      // Para arquivos pequenos (< 1MB), simulamos o progresso para feedback visual do usuário.
      if (onProgress != null) {
        onProgress(0.1);
        await Future.delayed(const Duration(milliseconds: 100));
        onProgress(0.3);
      }

      await _supabase.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: contentType,
            ),
          );

      if (onProgress != null) {
        onProgress(0.8);
        await Future.delayed(const Duration(milliseconds: 50));
        onProgress(1.0);
      }

      final String publicUrl = _supabase.storage.from(bucket).getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      rethrow;
    }
  }

  // --- Funções de Alto Nível ---

  static Future<String> uploadStoreCover(
    dynamic file, 
    String storeId, 
    {void Function(double)? onProgress, bool updateDatabase = true}
  ) async {
    try {
      final result = await compressImage(file: file, context: ImageContext.cover);
      final path = '$storeId/cover${result.extension}';
      final url = await uploadImageToSupabase(
        bytes: result.bytes, 
        path: path, 
        bucket: 'stores',
        contentType: result.contentType,
        onProgress: onProgress,
      );

      if (updateDatabase) {
        await _supabase.from('shops').update({'image_url': url}).eq('id', storeId);
      }
      return url;
    } catch (e) {
      throw Exception('Falha no upload da capa: $e');
    }
  }

  static Future<String> uploadStoreLogo(
    dynamic file, 
    String storeId, 
    {void Function(double)? onProgress, bool updateDatabase = true}
  ) async {
    try {
      final result = await compressImage(file: file, context: ImageContext.avatar);
      final path = '$storeId/logo${result.extension}';
      final url = await uploadImageToSupabase(
        bytes: result.bytes, 
        path: path, 
        bucket: 'stores',
        contentType: result.contentType,
        onProgress: onProgress,
      );

      if (updateDatabase) {
        await _supabase.from('shops').update({'logo_url': url}).eq('id', storeId);
      }
      return url;
    } catch (e) {
      throw Exception('Falha no upload da logo: $e');
    }
  }

  static Future<String> uploadProfilePhoto(
    dynamic file, 
    String userId,
    {void Function(double)? onProgress, bool updateDatabase = true}
  ) async {
    try {
      final result = await compressImage(file: file, context: ImageContext.avatar);
      final path = '$userId/avatar${result.extension}';
      final url = await uploadImageToSupabase(
        bytes: result.bytes, 
        path: path, 
        bucket: 'profiles',
        contentType: result.contentType,
        onProgress: onProgress,
      );

      if (updateDatabase) {
        await _supabase.from('users').update({'photo_url': url}).eq('id', userId);
      }
      return url;
    } catch (e) {
      throw Exception('Falha no upload da foto de perfil: $e');
    }
  }

  static Future<List<String>> uploadServicePhotos(
    List<dynamic> files, 
    String serviceId,
    {void Function(double)? onProgress, bool updateDatabase = true}
  ) async {
    if (files.length > 8) {
      throw Exception('Limite máximo de 8 imagens por serviço excedido.');
    }

    final List<String> urls = [];

    for (int i = 0; i < files.length; i++) {
      final result = await compressImage(file: files[i], context: ImageContext.service);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '$serviceId/$timestamp-$i${result.extension}';
      
      final url = await uploadImageToSupabase(
        bytes: result.bytes, 
        path: path, 
        bucket: 'services',
        contentType: result.contentType,
        onProgress: (p) {
          if (onProgress != null) {
            // Calcula o progresso total baseado na média dos arquivos
            double individualWeight = 1.0 / files.length;
            onProgress((i * individualWeight) + (p * individualWeight));
          }
        },
      );
      urls.add(url);
    }

    if (updateDatabase) {
      await _supabase.from('services').update({
        'photos_urls': urls,
      }).eq('id', serviceId);
    }

    return urls;
  }
}
