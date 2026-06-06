import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/link_preview_service.dart';
import '../../../core/services/image_service.dart';

class ProductFormPage extends StatefulWidget {
  final String shopId;
  final Map<String, dynamic>? productToEdit;

  const ProductFormPage({
    super.key,
    required this.shopId,
    this.productToEdit,
  });

  @override
  State<ProductFormPage> createState() => _ProductFormPageState();
}

class _ProductFormPageState extends State<ProductFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  bool _isAffiliate = false;
  bool _isLoading = false;
  bool _isFetchingPreview = false;

  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _affiliateUrlController = TextEditingController();

  XFile? _pickedImage;

  @override
  void initState() {
    super.initState();
    if (widget.productToEdit != null) {
      final p = widget.productToEdit!;
      _isAffiliate = p['is_affiliate'] == true;
      _nameController.text = p['name'] ?? '';
      _priceController.text = (p['price'] as num?)?.toStringAsFixed(2).replaceAll('.', ',') ?? '';
      _descriptionController.text = p['description'] ?? '';
      _imageUrlController.text = p['image_url'] ?? '';
      _affiliateUrlController.text = p['affiliate_url'] ?? '';
    }
  }

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

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    _affiliateUrlController.dispose();
    super.dispose();
  }

  Future<void> _fetchLinkPreview() async {
    final url = _affiliateUrlController.text.trim();
    if (url.isEmpty || !url.startsWith('http')) return;

    setState(() => _isFetchingPreview = true);

    final preview = await LinkPreviewService.fetchPreview(url);
    
    if (mounted) {
      setState(() {
        _isFetchingPreview = false;
        if (preview != null) {
          if (preview.title != null && _nameController.text.isEmpty) {
            _nameController.text = preview.title!;
          }
          if (preview.imageUrl != null && _imageUrlController.text.isEmpty) {
            _imageUrlController.text = preview.imageUrl!;
          }
          if (preview.description != null && _descriptionController.text.isEmpty) {
            _descriptionController.text = preview.description!;
          }
          if (preview.price != null && _priceController.text.isEmpty) {
            _priceController.text = preview.price!.replaceAll('.', ',');
          }
        }
      });
      
      if (preview != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dados capturados do link com sucesso!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível capturar os dados automaticamente. Preencha os campos abaixo.')),
        );
      }
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final priceStr = _priceController.text.replaceAll(r'R$', '').replaceAll('.', '').replaceAll(',', '.').trim();
      final price = priceStr.isNotEmpty ? double.tryParse(priceStr) : null;
      
      final docId = widget.productToEdit?['id'] ?? const Uuid().v4();
      
      String imageUrlToSave = _imageUrlController.text.trim();

      if (_pickedImage != null) {
        final result = await ImageService.compressImage(file: _pickedImage!, context: ImageContext.service);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final path = 'products/$docId/$timestamp${result.extension}';
        
        imageUrlToSave = await ImageService.uploadImageToSupabase(
          bytes: result.bytes, 
          path: path, 
          bucket: 'services', // Usando bucket de services conforme permissões do app
          contentType: result.contentType,
        );
      }

      final data = {
        'id': docId,
        'shop_id': widget.shopId,
        'name': _nameController.text.trim(),
        'price': price,
        'description': _descriptionController.text.trim(),
        'image_url': imageUrlToSave,
        'is_affiliate': _isAffiliate,
        'affiliate_url': _affiliateUrlController.text.trim(),
      };

      if (widget.productToEdit == null) {
        // Insert
        await _supabase.from('products').insert(data);
      } else {
        // Update
        data['updated_at'] = DateTime.now().toIso8601String();
        await _supabase
            .from('products')
            .update(data)
            .eq('id', docId);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar produto: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.productToEdit == null ? 'Novo Produto' : 'Editar Produto'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: Colors.grey[200], height: 1.0),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tipo do produto
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: SwitchListTile(
                  title: const Text('É um link de afiliado?', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Ex: Mercado Livre, Shopee, Amazon', style: TextStyle(fontSize: 12)),
                  activeTrackColor: AppColors.primaryPurple.withValues(alpha: 0.5),
                  activeThumbColor: AppColors.primaryPurple,
                  value: _isAffiliate,
                  onChanged: (val) => setState(() => _isAffiliate = val),
                ),
              ),
              const SizedBox(height: 24),

              // Campo de Link de Afiliado (se ativado)
              if (_isAffiliate) ...[
                const Text('Link do Produto', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _affiliateUrlController,
                        decoration: InputDecoration(
                          hintText: 'https://...',
                          filled: true,
                          fillColor: Colors.grey[50],
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                        ),
                        validator: (val) {
                          if (_isAffiliate && (val == null || val.isEmpty)) {
                            return 'O link é obrigatório para afiliados';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _isFetchingPreview ? null : _fetchLinkPreview,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPurple,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isFetchingPreview
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.search, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Dica: Cole o link e clique na lupa para preencher foto e título.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 24),
              ],

              // Nome
              const Text('Nome do Produto *', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'Ex: Shampoo Hidratante',
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
                validator: (val) => val == null || val.isEmpty ? 'Informe o nome do produto' : null,
              ),
              const SizedBox(height: 20),

              // Preço
              const Text(r'Preço (R$) *', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: '0,00',
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
                validator: (val) {
                  if (!_isAffiliate && (val == null || val.isEmpty)) {
                    return 'Informe o preço (Opcional para afiliados)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Imagem URL
              const Text('Imagem do Produto', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              
              if (_pickedImage != null || _imageUrlController.text.isNotEmpty) ...[
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _pickedImage != null
                        ? (kIsWeb
                            ? Image.network(_pickedImage!.path, height: 150, fit: BoxFit.cover)
                            : Image.file(File(_pickedImage!.path), height: 150, fit: BoxFit.cover))
                        : CachedNetworkImage(
                            imageUrl: _imageUrlController.text,
                            height: 150,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => const SizedBox(),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                    if (picked != null) {
                      final croppedImage = await _cropImage(picked);
                      if (croppedImage != null) {
                        setState(() {
                          _pickedImage = croppedImage;
                          _imageUrlController.clear();
                        });
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.1),
                    foregroundColor: AppColors.primaryPurple,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.photo_library),
                  label: const Text("Carregar Foto da Galeria"),
                ),
              ),
              const SizedBox(height: 20),

              // Descrição
              const Text('Descrição (Opcional)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Descreva os detalhes do produto...',
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
              ),
              const SizedBox(height: 40),

              // Botão Salvar
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProduct,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Salvar Produto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
