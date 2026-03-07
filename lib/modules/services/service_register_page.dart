import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:image_cropper/image_cropper.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

class ServiceRegisterPage extends StatefulWidget {
  final DocumentSnapshot? serviceToEdit;
  final VoidCallback onClose;

  const ServiceRegisterPage(
      {super.key, this.serviceToEdit, required this.onClose});

  @override
  State<ServiceRegisterPage> createState() => _ServiceRegisterPageState();
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

  final List<XFile> _newImages = [];
  List<String> _existingUrls = [];

  List<Map<String, dynamic>> _variations = [];

  bool _isSaving = false;
  bool _isDragging = false;
  double _uploadProgress = 0;
  bool _ativo = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.serviceToEdit != null) {
      final data = widget.serviceToEdit!.data() as Map<String, dynamic>;
      _nameController.text = data['nome'] ?? "";
      _priceController.text = data['preco']?.toString() ?? "";
      _custoController.text = data['custo']?.toString() ?? "0";
      _timeController.text = data['tempo_min']?.toString() ?? "";
      _descriptionController.text = data['descricao'] ?? "";
      _existingUrls = List<String>.from(data['fotos_urls'] ?? []);
      _ativo = data['ativo'] ?? true;

      if (data['variations'] != null) {
        _variations = List<Map<String, dynamic>>.from(data['variations']);
      }

      _requerAviso = data['requer_aviso'] ?? false;
      _avisoController.text = data['mensagem_aviso'] ?? "";
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

  /// Chamado quando o app volta ao foreground (ex: após fechar a Activity do crop)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restoreSystemUI();
    }
  }

  /// Prepara o SystemUI antes de abrir o ImageCropper no Android.
  /// Ativa edge-to-edge com barras transparentes para que a Activity
  /// nativa do cropper gerencie corretamente seus próprios insets,
  /// evitando sobreposição da toolbar com a status bar e dos botões
  /// inferiores com a navigation bar.
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
                keyboardType: TextInputType.number,
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
                setState(() {
                  _variations.add({
                    'name': nameVar.text,
                    'price':
                        double.tryParse(priceVar.text.replaceAll(',', '.')) ??
                            0.0,
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

  Future<XFile?> _cropImage(XFile imageFile) async {
    try {
      // Pula crop no mobile web para evitar problemas de UI
      if (kIsWeb) {
        try {
          final width = MediaQuery.of(context).size.width;
          if (width < 900) {
            debugPrint(
                'âš ï¸ Mobile web detected - skipping crop UI to avoid issues.');
            return imageFile;
          }
        } catch (_) {}
      }

      // âœ… FIX DEFINITIVO para Android:
      // Ativa edge-to-edge ANTES de abrir o cropper. Isso faz com que a
      // Activity nativa do ImageCropper receba insets corretos do sistema,
      // posicionando a toolbar abaixo da status bar e os controles acima
      // da navigation bar â€” sem nenhuma sobreposição.
      if (!kIsWeb) {
        _prepareSystemUIForCrop();
        // Aguarda o frame para garantir que o canal de plataforma aplicou
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

      // Restaura o SystemUI após fechar o cropper
      if (!kIsWeb) {
        _restoreSystemUI();
      }

      if (croppedFile != null) {
        return XFile(croppedFile.path);
      }
      return null;
    } catch (e) {
      debugPrint("âš ï¸ Erro no Crop: $e");
      // Garante restauração mesmo em caso de erro
      if (!kIsWeb) {
        _restoreSystemUI();
      }
      return imageFile;
    }
  }

  Future<void> _pickImages() async {
    if ((_newImages.length + _existingUrls.length) >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Máximo de 5 fotos."), backgroundColor: Colors.red),
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
        int available = 5 - (_newImages.length + _existingUrls.length);
        int addedCount = 0;

        for (int i = 0; i < picked.length && i < available; i++) {
          final image = picked[i];
          final croppedImage = await _cropImage(image);

          if (croppedImage != null) {
            setState(() => _newImages.add(croppedImage));
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
      debugPrint("âŒ Erro ao selecionar: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Erro ao selecionar imagens"),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editNewImage(int index) async {
    final image = _newImages[index];
    final croppedImage = await _cropImage(image);

    if (croppedImage != null) {
      setState(() {
        _newImages[index] = croppedImage;
      });
      _showSnackBar("Imagem atualizada!");
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
      debugPrint(
          'DEBUG Save Serviço: shopId inicial do SessionService: ${shopId ?? "NULL"}');

      if (shopId == null || shopId.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          shopId = userDoc.data()?['shopId'] as String?;
          debugPrint(
              'DEBUG Save Serviço: shopId fallback do users/{uid}: ${shopId ?? "NULL"}');

          if (shopId != null && shopId.isNotEmpty) {
            await SessionService.saveShopId(shopId);
            debugPrint(
                'DEBUG Save Serviço: shopId salvo na sessão via fallback: $shopId');
          }
        }
      }

      if (shopId == null || shopId.isEmpty) {
        _showSnackBar("Erro: Loja não identificada. Crie uma loja primeiro.",
            isError: true);
        setState(() => _isSaving = false);
        return;
      }

      debugPrint(
          'DEBUG Save Serviço: shopId final usado para salvar serviço: $shopId');

      final docId = widget.serviceToEdit?.id ??
          FirebaseFirestore.instance.collection('services').doc().id;
      List<String> uploadedUrls = List.from(_existingUrls);

      for (int i = 0; i < _newImages.length; i++) {
        try {
          final XFile imageXFile = _newImages[i];
          final String fileName =
              "${DateTime.now().millisecondsSinceEpoch}_$i.jpg";
          final Reference ref =
              FirebaseStorage.instance.ref().child('services/$docId/$fileName');

          UploadTask uploadTask;

          if (kIsWeb) {
            final Uint8List bytes = await imageXFile.readAsBytes();
            final metadata = SettableMetadata(contentType: 'image/jpeg');
            uploadTask = ref.putData(bytes, metadata);
          } else {
            final File file = File(imageXFile.path);
            uploadTask = ref.putFile(file);
          }

          uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
            if (snapshot.totalBytes > 0) {
              final double progress =
                  snapshot.bytesTransferred / snapshot.totalBytes;
              final double overallProgress =
                  ((i + progress) / _newImages.length);

              if (mounted) {
                setState(() {
                  _uploadProgress = overallProgress;
                });
              }
            }
          });

          await uploadTask;
          final String url = await ref.getDownloadURL();
          uploadedUrls.add(url);
        } catch (e) {
          debugPrint("âŒ Erro upload imagem $i: $e");
          _showSnackBar("Erro ao enviar imagem ${i + 1}", isError: true);
          continue;
        }
      }

      await FirebaseFirestore.instance.collection('services').doc(docId).set({
        'nome': _nameController.text.trim(),
        'preco':
            double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0,
        'custo':
            double.tryParse(_custoController.text.replaceAll(',', '.')) ?? 0,
        'tempo_min': int.tryParse(_timeController.text) ?? 30,
        'descricao': _descriptionController.text.trim(),
        'fotos_urls': uploadedUrls,
        'shopId': shopId,
        'ativo': _ativo,
        'variations': _variations,
        'requer_aviso': _requerAviso,
        'mensagem_aviso': _requerAviso ? _avisoController.text.trim() : "",
        'atualizado_em': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await SessionService.saveShopId(shopId);
      debugPrint(
          'DEBUG Save Serviço: shopId garantido na sessão após salvar serviço: $shopId');

      if (mounted) {
        widget.onClose();
        _showSnackBar("Serviço salvo com sucesso!");
      }
    } catch (e) {
      debugPrint("âŒ Erro geral ao salvar serviço: $e");
      _showSnackBar("Erro ao salvar serviço: ${e.toString()}", isError: true);
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
    final bool hasImages = _existingUrls.isNotEmpty || _newImages.isNotEmpty;
    final int totalImages = _existingUrls.length + _newImages.length;

    return DropTarget(
      onDragDone: (detail) async {
        final int newTotal = totalImages + detail.files.length;
        if (newTotal > 5) {
          _showSnackBar("Limite de 5 fotos excedido.", isError: true);
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
            if ((_newImages.length + _existingUrls.length) >= 5) break;
            final croppedImage = await _cropImage(file);
            if (croppedImage != null) {
              setState(() => _newImages.add(croppedImage));
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

              // CORPO SCROLLÃVEL
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ÃREA DE FOTOS
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
                              : Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    ListView(
                                      controller: _scrollController,
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 40, vertical: 10),
                                      children: [
                                        if (totalImages < 5)
                                          GestureDetector(
                                            onTap: _pickImages,
                                            child: Container(
                                              width: 90,
                                              margin: const EdgeInsets.only(
                                                  right: 12),
                                              decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                      color: AppColors
                                                          .primaryPurple
                                                          .withValues(
                                                              alpha: 0.5),
                                                      width: 2)),
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Icon(
                                                      Icons.add_photo_alternate,
                                                      color: AppColors
                                                          .primaryPurple,
                                                      size: 32),
                                                  const SizedBox(height: 4),
                                                  Text("+${5 - totalImages}",
                                                      style: const TextStyle(
                                                          fontSize: 11,
                                                          color: Colors.grey,
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ..._existingUrls.map((url) =>
                                            _buildExistingImageThumb(url)),
                                        ..._newImages.asMap().entries.map(
                                            (entry) => _buildNewImageThumb(
                                                entry.value, entry.key)),
                                      ],
                                    ),
                                    if (hasImages &&
                                        _scrollController.hasClients &&
                                        _scrollController
                                                .position.maxScrollExtent >
                                            0)
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
                                Text("$totalImages de 5 fotos",
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey)),
                                Text(" â€¢ Clique no âœ‚ï¸ para recortar",
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
                              final value =
                                  double.tryParse(v.replaceAll(',', '.'));
                              if (value == null || value <= 0) {
                                return "Preço inválido";
                              }
                              return null;
                            },
                          )),
                          const SizedBox(width: 12),
                          Expanded(
                              child: TextFormField(
                            controller: _timeController,
                            decoration: const InputDecoration(
                                labelText: "Tempo (min)",
                                isDense: true,
                                border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            validator: (v) {
                              if (v == null || v.isEmpty) return "Obrigatório";
                              final value = int.tryParse(v);
                              if (value == null || value <= 0) {
                                return "Tempo inválido";
                              }
                              return null;
                            },
                          )),
                        ]),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _custoController,
                          decoration: const InputDecoration(
                            labelText:
                                "Custo do serviço (R\$) - para cálculo de margem de lucro",
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (v) {
                            if (v == null || v.isEmpty) return null;
                            final value =
                                double.tryParse(v.replaceAll(',', '.'));
                            if (value != null && value < 0) {
                              return "Custo não pode ser negativo";
                            }
                            return null;
                          },
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
                              labelText: "Descrição Detalhada",
                              alignLabelWithHint: true,
                              border: OutlineInputBorder()),
                          validator: (v) =>
                              v == null || v.isEmpty ? "Obrigatório" : null,
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
  }

  Widget _buildExistingImageThumb(String url) {
    return Stack(
      children: [
        Container(
          width: 90,
          height: 90,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            color: Colors.grey.shade100,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
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
                debugPrint("âŒ Erro ao carregar: $url - $error");
                return Container(
                  color: Colors.red.shade50,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 30),
                      SizedBox(height: 4),
                      Text("Erro",
                          style: TextStyle(fontSize: 10, color: Colors.red)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          right: 16,
          top: 4,
          child: GestureDetector(
            onTap: () => setState(() => _existingUrls.remove(url)),
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

  Widget _buildNewImageThumb(XFile file, int index) {
    return Stack(
      children: [
        Container(
          width: 90,
          height: 90,
          margin: const EdgeInsets.only(right: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.primaryPurple.withValues(alpha: 0.3),
                width: 2),
            color: Colors.grey.shade100,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FutureBuilder<Uint8List>(
              future: file.readAsBytes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2));
                } else if (snapshot.hasError) {
                  debugPrint("âŒ Erro ao ler: ${snapshot.error}");
                  return Container(
                    color: Colors.orange.shade50,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning_amber,
                            color: Colors.orange, size: 30),
                        Text("Erro",
                            style:
                                TextStyle(fontSize: 10, color: Colors.orange)),
                      ],
                    ),
                  );
                } else if (snapshot.hasData) {
                  return Image.memory(snapshot.data!, fit: BoxFit.cover);
                } else {
                  return const Icon(Icons.image, color: Colors.grey, size: 30);
                }
              },
            ),
          ),
        ),
        Positioned(
          left: 4,
          top: 4,
          child: GestureDetector(
            onTap: () => _editNewImage(index),
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
            onTap: () => setState(() => _newImages.removeAt(index)),
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
