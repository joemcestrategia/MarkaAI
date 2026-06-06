import 'dart:io' if (dart.library.html) 'package:markaai/core/utils/io_stub.dart' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:image_picker/image_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../core/services/auth_service.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/constants/plan_features.dart';
import '../../core/services/plan_features_service.dart';
import '../../core/models/service_model.dart';
import '../../core/services/shop_data_cache_service.dart';
import '../../core/services/image_service.dart';

class ServiceRegisterPage extends StatefulWidget {
  final Map<String, dynamic>? serviceToEdit;
  final VoidCallback onClose;

  const ServiceRegisterPage(
      {super.key, this.serviceToEdit, required this.onClose});

  @override
  State<ServiceRegisterPage> createState() => _ServiceRegisterPageState();
}

class _ServicePhotoItem {
  final String id;
  final String? url;
  final XFile? file;
  
  _ServicePhotoItem({this.url, this.file}) : id = const Uuid().v4();
}

class _ServiceRegisterPageState extends State<ServiceRegisterPage>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _custoController = TextEditingController(text: '0');
  final _timeController = TextEditingController();
  final _descriptionController = TextEditingController();

  final _avisoController = TextEditingController();
  bool _requerAviso = false;

  final ScrollController _scrollController = ScrollController();

  List<_ServicePhotoItem> _photos = [];

  List<Map<String, dynamic>> _variations = [];

  bool _isSaving = false;
  bool _isDragging = false;
  double _uploadProgress = 0;
  bool _ativo = true;
  bool _isFeatured = false;
  List<String> _categoryIds = [];
  late PlanFeatures _currentFeatures = planFeaturesConfig[PlanKey.free]!;

  @override
  void initState() {
    super.initState();
    _loadShopId();
    WidgetsBinding.instance.addObserver(this);

    if (widget.serviceToEdit != null) {
      final data = widget.serviceToEdit!;
      _nameController.text = data['name'] ?? "";
      _priceController.text = data['price']?.toString() ?? "";
      _custoController.text = data['cost']?.toString() ?? "0";
      _timeController.text = data['duration_min']?.toString() ?? "";
      _descriptionController.text = data['description'] ?? "";
      _photos = (data['photos_urls'] as List<dynamic>? ?? [])
          .map((url) => _ServicePhotoItem(url: url.toString()))
          .toList();
      _ativo = data['is_active'] ?? true;
      _isFeatured = data['is_featured'] ?? false;

      if (data['variations'] != null) {
        _variations = List<Map<String, dynamic>>.from(data['variations']);
      }

      _requerAviso = data['requires_warning'] ?? false;
      _avisoController.text = data['warning_message'] ?? "";
      
      // Suporte para migração ou carga do novo campo
      if (data['category_ids'] != null) {
        _categoryIds = List<String>.from(data['category_ids']);
      } else if (data['categoryId'] != null) {
        _categoryIds = [data['categoryId']];
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _priceController.dispose();
    _custoController.dispose();
    _timeController.dispose();
    _descriptionController.dispose();
    _avisoController.dispose();
    _scrollController.dispose();
    super.dispose();
  }


  Future<void> _loadShopId() async {
    final sId = await SessionService.getShopId();
    if (mounted) {
      setState(() {
        _shopId = sId;
      });
    }
  }

  String? _shopId;

  /// Prepara o SystemUI antes de abrir o ImageCropper no Android.
  void _prepareSystemUIForCrop() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  /// Restaura o SystemUI ao estado padrão do app após o crop fechar.
  void _restoreSystemUI() {
    if (!mounted) return;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return "$minutes min";
    final int hours = minutes ~/ 60;
    final int mins = minutes % 60;

    if (mins == 0) {
      return hours == 1 ? "1 hora" : "$hours horas";
    }

    final String hourLabel = hours == 1 ? "1 hora" : "$hours horas";
    return "$hourLabel e $mins min";
  }

  void _scrollLeft() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.offset - 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollRight() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.offset + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showAddVariationDialog() {
    final nameVar = TextEditingController();
    final priceVar = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Adicionar Variação"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameVar,
                decoration:
                    const InputDecoration(labelText: "Nome (Ex: Orgânico)")),
            const SizedBox(height: 10),
            TextField(
                controller: priceVar,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: "Preço (R\$)"))
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () {
              if (nameVar.text.isNotEmpty && priceVar.text.isNotEmpty) {
                // Remove R$ e espaços, depois trata formato BR (1.000,00 -> 1000.00)
                String raw = priceVar.text.replaceAll(RegExp(r'[R\$\s]'), '');
                if (raw.contains(',')) {
                  raw = raw.replaceAll('.', '').replaceAll(',', '.');
                }
                
                setState(() {
                  _variations.add({
                    'name': nameVar.text,
                    'price': double.tryParse(raw) ?? 0.0,
                  });
                });
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white,
            ),
            child:
                const Text("Adicionar", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  Future<void> _editPhoto(int index) async {
    final photo = _photos[index];
    if (photo.file != null) {
      final croppedImage = await _cropImage(photo.file!);
      if (croppedImage != null) {
        setState(() {
          _photos[index] = _ServicePhotoItem(file: croppedImage);
        });
        _showSnackBar("Imagem atualizada!");
      }
    } else if (photo.url != null) {
      try {
        setState(() => _isSaving = true);
        final response = await http.get(Uri.parse(photo.url!));
        final tempDir = await getTemporaryDirectory();
        final file = io.File('${tempDir.path}/temp_crop_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await file.writeAsBytes(response.bodyBytes);
        
        final cropped = await _cropImage(XFile(file.path));
        if (cropped != null) {
          setState(() {
            _photos[index] = _ServicePhotoItem(file: cropped);
          });
          _showSnackBar("Imagem atualizada!");
        }
      } catch (e) {
        _showSnackBar("Erro ao preparar imagem para recorte: $e", isError: true);
      } finally {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<XFile?> _cropImage(XFile imageFile) async {
    try {
      if (kIsWeb) {
        try {
          final width = MediaQuery.of(context).size.width;
          if (width < 900) {
            return imageFile;
          }
        } catch (_) {}
      }

      if (!kIsWeb) {
        _prepareSystemUIForCrop();
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (!mounted) return imageFile;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Ajustar Foto',
            toolbarColor: AppColors.primaryPurple,
            toolbarWidgetColor: Colors.white,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: AppColors.primaryPurple,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: false,
            showCropGrid: true,
            hideBottomControls: false,
            dimmedLayerColor: Colors.black54,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
          ),
          IOSUiSettings(
            title: 'Ajustar Foto',
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
          ),
          WebUiSettings(context: context),
        ],
      );

      if (!kIsWeb) {
        _restoreSystemUI();
      }

      if (croppedFile != null) {
        return XFile(croppedFile.path);
      }
      return null;
    } catch (e) {
      if (!kIsWeb) {
        _restoreSystemUI();
      }
      return imageFile;
    }
  }

  Future<void> _pickImages() async {
    if (_photos.length >= _currentFeatures.maxPhotosPerService) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Máximo de ${_currentFeatures.maxPhotosPerService} fotos."), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      final ImagePicker picker = ImagePicker();
      final List<XFile> picked = await picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1024,
      );

      if (picked.isNotEmpty) {
        int available = _currentFeatures.maxPhotosPerService - _photos.length;
        int addedCount = 0;

        for (int i = 0; i < picked.length && i < available; i++) {
          final image = picked[i];
          final croppedImage = await _cropImage(image);

          if (croppedImage != null) {
            setState(() => _photos.add(_ServicePhotoItem(file: croppedImage)));
            addedCount++;
          }
        }

        if (addedCount > 0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text("$addedCount foto(s) adicionada(s)!"),
                backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Erro ao selecionar imagens"),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _uploadProgress = 0;
    });

    try {
      String? shopId = await SessionService.getShopId();
      if (shopId == null || shopId.isEmpty) {
        final user = AuthService().currentUser;
        if (user != null) {
          final userDoc = await sb.Supabase.instance.client
              .from('users')
              .select()
              .eq('id', user.id)
              .maybeSingle();
          shopId = userDoc?['shop_id'] as String?;
          if (shopId != null && shopId.isNotEmpty) {
            await SessionService.saveShopId(shopId);
          }
        }
      }

      if (shopId == null || shopId.isEmpty) {
        _showSnackBar("Erro: Loja não identificada. Crie uma loja primeiro.",
            isError: true);
        setState(() => _isSaving = false);
        return;
      }

      final docId = widget.serviceToEdit?['id'] ??
          Uuid().v4();
      List<XFile> filesToUpload = _photos.where((p) => p.file != null).map((p) => p.file!).toList();
      List<String> uploadedNewUrls = [];
      if (filesToUpload.isNotEmpty) {
        uploadedNewUrls = await ImageService.uploadServicePhotos(
          filesToUpload,
          docId,
          onProgress: (p) {
            if (mounted) {
              setState(() => _uploadProgress = p);
            }
          },
        );
      }

      int newUrlIndex = 0;
      List<String> finalPhotosUrls = [];
      for (var photo in _photos) {
        if (photo.url != null) {
          finalPhotosUrls.add(photo.url!);
        } else if (photo.file != null) {
          if (newUrlIndex < uploadedNewUrls.length) {
            finalPhotosUrls.add(uploadedNewUrls[newUrlIndex]);
            newUrlIndex++;
          }
        }
      }

      final service = ServiceModel(
        id: docId,
        shopId: shopId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        price: () {
          String raw = _priceController.text.replaceAll(RegExp(r'[R\$\s]'), '');
          if (raw.contains(',')) raw = raw.replaceAll('.', '').replaceAll(',', '.');
          return double.tryParse(raw) ?? 0.0;
        }(),
        cost: () {
          String raw = _custoController.text.replaceAll(RegExp(r'[R\$\s]'), '');
          if (raw.contains(',')) raw = raw.replaceAll('.', '').replaceAll(',', '.');
          return double.tryParse(raw) ?? 0.0;
        }(),
        durationMin: int.tryParse(_timeController.text) ?? 30,
        photosUrls: finalPhotosUrls,
        categoryIds: _categoryIds,
        isActive: _ativo,
        isFeatured: _isFeatured,
        variations: _variations,
        requiresWarning: _requerAviso,
        warningMessage: _requerAviso ? _avisoController.text.trim() : "",
      );

      await sb.Supabase.instance.client
          .from('services')
          .upsert(service.toMap(), onConflict: 'id');

      if (mounted) {
        ShopDataCacheService().invalidate(shopId, 'services');
        widget.onClose();
        _showSnackBar("✅ Serviço e imagens salvos com sucesso!");
      }
    } on sb.PostgrestException catch (e) {
      _showSnackBar("Erro de banco (Supabase): ${e.message}", isError: true);
    } catch (e) {
      _showSnackBar("Erro inesperado: ${e.toString()}", isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_shopId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<PlanFeatures>(
      stream: PlanFeaturesService.streamFeaturesByShopId(_shopId!),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          _currentFeatures = snapshot.data!;
        }

        final bool hasImages = _photos.isNotEmpty;
        final int totalImages = _photos.length;

        return DropTarget(
          onDragDone: (detail) async {
            final int newTotal = totalImages + detail.files.length;
            if (newTotal > _currentFeatures.maxPhotosPerService) {
              _showSnackBar("Limite de ${_currentFeatures.maxPhotosPerService} fotos excedido.", isError: true);
              return;
            }

            final validFiles = <XFile>[];
            for (final file in detail.files) {
              final fileName = file.name.toLowerCase();
              if (fileName.endsWith('.jpg') ||
                  fileName.endsWith('.jpeg') ||
                  fileName.endsWith('.png')) {
                validFiles.add(file);
              }
            }

            if (validFiles.isNotEmpty) {
              for (final file in validFiles) {
                if (_photos.length >= _currentFeatures.maxPhotosPerService) break;
                final croppedImage = await _cropImage(file);
                if (croppedImage != null) {
                  setState(() => _photos.add(_ServicePhotoItem(file: croppedImage)));
                }
              }
              setState(() => _isDragging = false);
            }
          },
          onDragEntered: (detail) => setState(() => _isDragging = true),
          onDragExited: (detail) => setState(() => _isDragging = false),
          child: Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: Column(
                children: [
                  // HEADER
                  Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: Colors.grey.shade200))),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            widget.serviceToEdit != null
                                ? "Editar"
                                : "Novo Serviço",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: widget.onClose,
                          tooltip: "Fechar",
                        ),
                      ],
                    ),
                  ),

                  // CORPO SCROLLÁVEL
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ÁREA DE FOTOS
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: 120,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: _isDragging
                                    ? AppColors.primaryPurple.withValues(alpha: 0.1)
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _isDragging
                                      ? AppColors.primaryPurple
                                      : Colors.grey.shade300,
                                  width: _isDragging ? 2 : 1,
                                ),
                              ),
                              child: !hasImages
                                  ? Center(
                                      child: GestureDetector(
                                        onTap: _pickImages,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.add_photo_alternate,
                                                size: 40,
                                                color: _isDragging
                                                    ? AppColors.primaryPurple
                                                    : Colors.grey.shade400),
                                            const SizedBox(height: 8),
                                            Text(
                                                _isDragging
                                                    ? "SOLTE AQUI!"
                                                    : "Adicionar Fotos",
                                                style: TextStyle(
                                                    color: _isDragging
                                                        ? AppColors.primaryPurple
                                                        : Colors.grey.shade600,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14)),
                                            const SizedBox(height: 4),
                                            Text("Clique ou arraste",
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey.shade500)),
                                          ],
                                        ),
                                      ),
                                    )
                                  : Row(
                                            children: [
                                              if (totalImages < _currentFeatures.maxPhotosPerService)
                                                Padding(
                                                  padding: const EdgeInsets.only(left: 40, top: 10, bottom: 10),
                                                  child: GestureDetector(
                                                    onTap: _pickImages,
                                                    child: Container(
                                                      width: 90,
                                                      margin: const EdgeInsets.only(right: 12),
                                                      decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius: BorderRadius.circular(12),
                                                          border: Border.all(
                                                              color: AppColors.primaryPurple.withValues(alpha: 0.5),
                                                              width: 2)),
                                                      child: Column(
                                                        mainAxisAlignment: MainAxisAlignment.center,
                                                        children: [
                                                          const Icon(Icons.add_photo_alternate,
                                                              color: AppColors.primaryPurple, size: 32),
                                                          const SizedBox(height: 4),
                                                          Text("+${_currentFeatures.maxPhotosPerService - totalImages}",
                                                              style: const TextStyle(
                                                                  fontSize: 11,
                                                                  color: Colors.grey,
                                                                  fontWeight: FontWeight.bold)),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              Expanded(
                                                child: ReorderableListView(
                                                  scrollController: _scrollController,
                                                  scrollDirection: Axis.horizontal,
                                                  padding: EdgeInsets.only(
                                                      left: (totalImages < _currentFeatures.maxPhotosPerService) ? 0 : 40,
                                                      right: 40,
                                                      top: 10,
                                                      bottom: 10),
                                                  onReorder: (oldIndex, newIndex) {
                                                    setState(() {
                                                      if (oldIndex < newIndex) {
                                                        newIndex -= 1;
                                                      }
                                                      final item = _photos.removeAt(oldIndex);
                                                      _photos.insert(newIndex, item);
                                                    });
                                                  },
                                                  children: [
                                                    for (int i = 0; i < _photos.length; i++)
                                                      _buildPhotoThumb(_photos[i], i, ValueKey(_photos[i].id)),
                                                  ],
                                                ),
                                              ),
                                          Positioned(
                                              left: 4,
                                              child: GestureDetector(
                                                onTap: _scrollLeft,
                                                child: Container(
                                                    padding:
                                                        const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                        color: Colors.white
                                                            .withValues(alpha: 0.9),
                                                        shape: BoxShape.circle,
                                                        boxShadow: const [
                                                          BoxShadow(
                                                              color: Colors.black12,
                                                              blurRadius: 4)
                                                        ]),
                                                    child: const Icon(
                                                        Icons.chevron_left,
                                                        color: Colors.black87,
                                                        size: 20)),
                                              )),
                                        if (hasImages &&
                                            _scrollController.hasClients &&
                                            _scrollController
                                                    .position.maxScrollExtent >
                                                0)
                                          Positioned(
                                              right: 4,
                                              child: GestureDetector(
                                                onTap: _scrollRight,
                                                child: Container(
                                                    padding:
                                                        const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                        color: Colors.white
                                                            .withValues(alpha: 0.9),
                                                        shape: BoxShape.circle,
                                                        boxShadow: const [
                                                          BoxShadow(
                                                              color: Colors.black12,
                                                              blurRadius: 4)
                                                        ]),
                                                    child: const Icon(
                                                        Icons.chevron_right,
                                                        color: Colors.black87,
                                                        size: 20)),
                                              )),
                                      ],
                                    ),
                            ),

                            if (hasImages)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(
                                  children: [
                                    Text("$totalImages de ${_currentFeatures.maxPhotosPerService} fotos",
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.grey)),
                                    Text(" • Segure para reordenar. Clique no âœ‚ï¸  para recortar.",
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                            fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 24),

                            // CAMPOS PRINCIPAIS
                            TextFormField(
                                controller: _nameController,
                                decoration: const InputDecoration(
                                    labelText: "Nome do Serviço",
                                    isDense: true,
                                    border: OutlineInputBorder()),
                                validator: (v) {
                                  return v == null || v.isEmpty
                                      ? "Obrigatório"
                                      : null;
                                }),

                            const SizedBox(height: 16),

                            // CATEGORIAS (Múltipla Seleção)
                            StreamBuilder<List<Map<String, dynamic>>>(
                              stream: sb.Supabase.instance.client
                                  .from('categories')
                                  .stream(primaryKey: ['id'])
                                  .eq('shop_id', _shopId!),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) return const SizedBox();
                                
                                final categories = snapshot.data!;
                                if (categories.isEmpty) return const SizedBox();

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("Categorias", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: categories.map((cat) {
                                        final catId = cat['id'];
                                        final catName = cat['name'];
                                        final isSelected = _categoryIds.contains(catId);

                                        return FilterChip(
                                          label: Text(catName),
                                          selected: isSelected,
                                          onSelected: (selected) {
                                            setState(() {
                                              if (selected) {
                                                _categoryIds.add(catId);
                                              } else {
                                                _categoryIds.remove(catId);
                                              }
                                            });
                                          },
                                          selectedColor: AppColors.primaryPurple.withValues(alpha: 0.2),
                                          checkmarkColor: AppColors.primaryPurple,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 24),
                                  ],
                                );
                              },
                            ),

                            const SizedBox(height: 16),

                            // PREÇO E CUSTO NA MESMA LINHA
                            Row(children: [
                              Expanded(
                                  child: TextFormField(
                                controller: _priceController,
                                decoration: const InputDecoration(
                                    labelText: "Preço Padrão (R\$)",
                                    isDense: true,
                                    border: OutlineInputBorder()),
                                keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return "Obrigatório";
                                  String raw = v.replaceAll(RegExp(r'[R\$\s]'), '');
                                  if (raw.contains(',')) raw = raw.replaceAll('.', '').replaceAll(',', '.');
                                  final value = double.tryParse(raw);
                                  if (value == null || value <= 0) {
                                    return "Preço inválido";
                                  }
                                  return null;
                                },
                              )),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: TextFormField(
                                controller: _custoController,
                                enabled: _currentFeatures.financialTab,
                                decoration: InputDecoration(
                                    labelText: "Custo (R\$)",
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                    suffixIcon: !_currentFeatures.financialTab ? const Icon(Icons.lock, size: 16) : null,
                                ),
                                keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return null;
                                  String raw = v.replaceAll(RegExp(r'[R\$\s]'), '');
                                  if (raw.contains(',')) raw = raw.replaceAll('.', '').replaceAll(',', '.');
                                  final value = double.tryParse(raw);
                                  if (value != null && value < 0) {
                                    return "Custo não pode ser negativo";
                                  }
                                  return null;
                                },
                              )),
                            ]),

                            const SizedBox(height: 20),

                            // DURAÇÃO EM LINHA SOZINHA
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "Duração do Serviço",
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey),
                                    ),
                                    Text(
                                      _formatDuration(
                                          int.tryParse(_timeController.text) ?? 30),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryPurple,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Slider(
                                  value: (int.tryParse(_timeController.text) ?? 30)
                                      .toDouble()
                                      .clamp(5, 480),
                                  min: 5,
                                  max: 480,
                                  divisions: 95,
                                  activeColor: AppColors.primaryPurple,
                                  inactiveColor: AppColors.primaryPurple
                                      .withValues(alpha: 0.1),
                                  onChanged: (double value) {
                                    setState(() {
                                      _timeController.text =
                                          value.round().toString();
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(children: [
                              Transform.scale(
                                  scale: 0.8,
                                  child: Switch(
                                      value: _ativo,
                                      activeThumbColor: AppColors.primaryPurple,
                                      onChanged: (val) =>
                                          setState(() => _ativo = val))),
                              Text(_ativo ? "Serviço Visível" : "Serviço Oculto",
                                  style: TextStyle(
                                      color: _ativo ? Colors.black87 : Colors.grey,
                                      fontSize: 13)),
                            ]),

                            const SizedBox(height: 12),

                            // TOGGLE: DESTACAR NA VITRINE
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: _isFeatured
                                    ? Colors.amber.shade50
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _isFeatured
                                      ? Colors.amber.shade400
                                      : Colors.grey.shade300,
                                  width: _isFeatured ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isFeatured ? Icons.star_rounded : Icons.star_outline_rounded,
                                    color: _isFeatured ? Colors.amber.shade700 : Colors.grey,
                                    size: 26,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Destacar na Vitrine",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: _isFeatured
                                                ? Colors.amber.shade800
                                                : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          "Este serviço aparecerá nos Destaques da Vitrine para os clientes.",
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: _isFeatured
                                                ? Colors.amber.shade700
                                                : Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Transform.scale(
                                    scale: 0.85,
                                    child: Switch(
                                      value: _isFeatured,
                                      activeColor: Colors.amber.shade600,
                                      activeTrackColor: Colors.amber.shade200,
                                      onChanged: (val) => setState(() => _isFeatured = val),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // SEÇÃO DE VARIAÇÕES
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade300)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text("Variações / Materiais",
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14)),
                                        TextButton.icon(
                                            onPressed: _showAddVariationDialog,
                                            icon: const Icon(
                                                Icons.add_circle_outline,
                                                size: 16),
                                            label: const Text("Adicionar"),
                                            style: TextButton.styleFrom(
                                                foregroundColor:
                                                    AppColors.primaryPurple))
                                      ]),
                                  if (_variations.isEmpty)
                                    const Text("Nenhuma variação.",
                                        style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic))
                                  else
                                    ..._variations.asMap().entries.map((entry) {
                                      final index = entry.key;
                                      final item = entry.value;
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                                color: Colors.grey.shade200)),
                                        child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text("${item['name']}",
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.w500)),
                                              Row(children: [
                                                Text("R\$ ${item['price']}",
                                                    style: const TextStyle(
                                                        color: Colors.green,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                const SizedBox(width: 10),
                                                GestureDetector(
                                                    onTap: () => setState(() =>
                                                        _variations
                                                            .removeAt(index)),
                                                    child: const Icon(
                                                        Icons.delete_outline,
                                                        color: Colors.red,
                                                        size: 18))
                                              ])
                                            ]),
                                      );
                                    }),
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            // SEÇÃO DE AVISO
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: Colors.orange.shade200)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    const Icon(Icons.info_outline,
                                        color: Colors.orange, size: 20),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                        child: Text("Aviso Prévio / Consentimento",
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Colors.brown))),
                                    Transform.scale(
                                        scale: 0.8,
                                        child: Switch(
                                            value: _requerAviso,
                                            activeThumbColor: Colors.orange,
                                            onChanged: (val) => setState(
                                                () => _requerAviso = val))),
                                  ]),
                                  const SizedBox(height: 5),
                                  const Text(
                                      "Ex: O cliente precisa aceitar 'Trazer o cabelo' antes de pagar.",
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.brown)),
                                  if (_requerAviso) ...[
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: _avisoController,
                                      maxLines: 2,
                                      decoration: const InputDecoration(
                                          labelText: "Mensagem do Aviso",
                                          filled: true,
                                          fillColor: Colors.white,
                                          border: OutlineInputBorder(),
                                          hintText:
                                              "Ex: A mão de obra não inclui o material..."),
                                      validator: _requerAviso
                                          ? (v) {
                                              if (v == null || v.trim().isEmpty) {
                                                return "Mensagem obrigatória quando aviso está ativo";
                                              }
                                              return null;
                                            }
                                          : null,
                                    ),
                                  ]
                                ],
                              ),
                            ),

                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _descriptionController,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                  labelText: "Descrição (Opcional)",
                                  alignLabelWithHint: true,
                                  border: OutlineInputBorder()),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // RODAPÉ
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        border:
                            Border(top: BorderSide(color: Colors.grey.shade200))),
                    child: Column(
                      children: [
                        if (_isSaving) ...[
                          Column(
                            children: [
                              LinearProgressIndicator(
                                  value: _uploadProgress,
                                  color: AppColors.primaryPurple,
                                  backgroundColor: Colors.grey.shade200),
                              const SizedBox(height: 8),
                              Text(
                                "Enviando... ${(_uploadProgress * 100).toStringAsFixed(0)}%",
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryPurple,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              disabledBackgroundColor:
                                  AppColors.primaryPurple.withValues(alpha: 0.5),
                            ),
                            child: _isSaving
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Text("Salvando...",
                                          style: TextStyle(color: Colors.white)),
                                    ],
                                  )
                                : const Text("SALVAR",
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPhotoThumb(_ServicePhotoItem photo, int index, Key key) {
    return Stack(
      key: key,
      children: [
        Container(
          width: 90,
          height: 90,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: photo.file != null 
                    ? AppColors.primaryPurple.withValues(alpha: 0.3) 
                    : Colors.grey.shade300,
                width: photo.file != null ? 2 : 1),
            color: Colors.grey.shade100,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: photo.file != null 
              ? FutureBuilder<Uint8List>(
                  future: photo.file!.readAsBytes(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                    } else if (snapshot.hasError) {
                      return Container(
                        color: Colors.orange.shade50,
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.warning_amber, color: Colors.orange, size: 30),
                            Text("Erro", style: TextStyle(fontSize: 10, color: Colors.orange)),
                          ],
                        ),
                      );
                    } else if (snapshot.hasData) {
                      return Image.memory(snapshot.data!, fit: BoxFit.cover);
                    } else {
                      return const Icon(Icons.image, color: Colors.grey, size: 30);
                    }
                  },
                )
              : Image.network(
                  photo.url!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: loadingProgress.expectedTotalBytes != null
                            ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                            : null,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.red.shade50,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, color: Colors.red, size: 30),
                          SizedBox(height: 4),
                          Text("Erro", style: TextStyle(fontSize: 10, color: Colors.red)),
                        ],
                      ),
                    );
                  },
                ),
          ),
        ),
        Positioned(
          left: 4,
          top: 4,
          child: GestureDetector(
            onTap: () => _editPhoto(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)],
              ),
              child: const CircleAvatar(
                  radius: 10,
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.crop, size: 12, color: Colors.white)),
            ),
          ),
        ),
        Positioned(
          right: 16,
          top: 4,
          child: GestureDetector(
            onTap: () => setState(() => _photos.removeAt(index)),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3)],
              ),
              child: const CircleAvatar(
                  radius: 10,
                  backgroundColor: Colors.red,
                  child: Icon(Icons.close, size: 12, color: Colors.white)),
            ),
          ),
        )
      ],
    );
  }
}
