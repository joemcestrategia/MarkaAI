import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

class StoreProfilePage extends StatefulWidget {
  const StoreProfilePage({super.key});

  @override
  State<StoreProfilePage> createState() => _StoreProfilePageState();
}

class _StoreProfilePageState extends State<StoreProfilePage> {
  final _formKey = GlobalKey<FormState>();
  
  // Controladores
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _slugController = TextEditingController();
  final _instagramController = TextEditingController();
  final _whatsappController = TextEditingController();

  // Imagens
  String? _logoUrl;
  String? _coverUrl;
  XFile? _newLogoFile;
  XFile? _newCoverFile;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _shopId;

  @override
  void initState() {
    super.initState();
    _loadStoreData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _slugController.dispose();
    _instagramController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  Future<void> _loadStoreData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        String? id = await SessionService.getShopId();
        
        if (id == null || id.isEmpty) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          id = userDoc.data()?['shopId'];
        }

        if (id != null) {
          final shopDoc = await FirebaseFirestore.instance
              .collection('shops')
              .doc(id)
              .get();
          if (shopDoc.exists) {
            final data = shopDoc.data() as Map<String, dynamic>;
            
            if (mounted) {
              setState(() {
                _shopId = id;
                _nameController.text = data['nome'] ?? "";
                _descController.text = data['descricao'] ?? "";
                _addressController.text = data['endereco'] ?? "";
                _phoneController.text = data['telefone'] ?? "";
                _slugController.text = data['slug'] ?? "";
                _instagramController.text = data['instagram'] ?? "";
                _whatsappController.text = data['whatsapp'] ?? "";
                _logoUrl = data['logoUrl'];
                _coverUrl = data['imageUrl'];
                _isLoading = false;
              });
            }
          } else {
            if (mounted) {
              setState(() {
                _shopId = id;
                _isLoading = false;
              });
            }
          }
        } else {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        }
      } catch (e) {
        debugPrint("Erro ao carregar dados: $e");
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 🎨 FUNÇÃO CORRIGIDA: Abrir editor de imagem
  Future<void> _pickAndEditImage({required bool isCover}) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
    );
    
    if (image != null && mounted) {
      // Abrir editor
      final editedImage = await Navigator.push<XFile>(
        context,
        MaterialPageRoute(
          builder: (context) => _ImageAdjustmentPage(
            imageFile: image,
            aspectRatio: isCover ? 16 / 9 : 1.0,
          ),
        ),
      );
      
      if (editedImage != null) {
        setState(() {
          if (isCover) {
            _newCoverFile = editedImage;
          } else {
            _newLogoFile = editedImage;
          }
        });
      }
    }
  }

  Future<String> _uploadFile(XFile file, String type) async {
    final ref = FirebaseStorage.instance.ref().child(
        'shops/$_shopId/${type}_${DateTime.now().millisecondsSinceEpoch}.jpg');
    
    if (kIsWeb) {
      await ref.putData(
        await file.readAsBytes(),
        SettableMetadata(contentType: 'image/jpeg'),
      );
    } else {
      await ref.putFile(File(file.path));
    }
    
    return await ref.getDownloadURL();
  }

  Future<bool> _isSlugAvailable(String slug) async {
    if (slug.isEmpty) return true;
    
    final querySnapshot = await FirebaseFirestore.instance
        .collection('shops')
        .where('slug', isEqualTo: slug)
        .get();
    
    // Se não encontrou nenhum, está disponível
    if (querySnapshot.docs.isEmpty) return true;
    
    // Se encontrou, verifica se é o próprio shop
    return querySnapshot.docs.first.id == _shopId;
  }

  String _normalizeSlug(String input) {
    // Remove espaços, acentos e caracteres especiais
    String slug = input.toLowerCase().trim();
    slug = slug.replaceAll(RegExp(r'[áàâãä]'), 'a');
    slug = slug.replaceAll(RegExp(r'[éèêë]'), 'e');
    slug = slug.replaceAll(RegExp(r'[íìîï]'), 'i');
    slug = slug.replaceAll(RegExp(r'[óòôõö]'), 'o');
    slug = slug.replaceAll(RegExp(r'[úùûü]'), 'u');
    slug = slug.replaceAll(RegExp(r'[ç]'), 'c');
    slug = slug.replaceAll(RegExp(r'[^a-z0-9-]'), '');
    return slug;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Validar slug se foi preenchido
    if (_slugController.text.trim().isNotEmpty) {
      final slugNormalizado = _normalizeSlug(_slugController.text.trim());
      final isAvailable = await _isSlugAvailable(slugNormalizado);
      
      if (!isAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este link já está em uso. Escolha outro.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      _slugController.text = slugNormalizado;
    }
    
    setState(() => _isSaving = true);

    try {
      String? logoDownloadUrl = _logoUrl;
      String? coverDownloadUrl = _coverUrl;

      if (_newLogoFile != null) {
        logoDownloadUrl = await _uploadFile(_newLogoFile!, "logo");
      }
      
      if (_newCoverFile != null) {
        coverDownloadUrl = await _uploadFile(_newCoverFile!, "cover");
      }

      await FirebaseFirestore.instance
          .collection('shops')
          .doc(_shopId)
          .set({
        'nome': _nameController.text.trim(),
        'descricao': _descController.text.trim(),
        'endereco': _addressController.text.trim(),
        'telefone': _phoneController.text.trim(),
        'slug': _slugController.text.trim().isNotEmpty ? _slugController.text.trim() : null,
        'instagram': _instagramController.text.trim(),
        'whatsapp': _whatsappController.text.trim(),
        'logoUrl': logoDownloadUrl,
        'imageUrl': coverDownloadUrl,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _logoUrl = logoDownloadUrl;
          _coverUrl = coverDownloadUrl;
          _newLogoFile = null;
          _newCoverFile = null;
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Perfil salvo com sucesso!"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint("Erro ao salvar perfil: $e");
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erro ao salvar: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildServicesShowcase() {
    if (_shopId == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Destaques da Vitrine",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              // Indicador visual opcional
              Icon(Icons.stars, color: Colors.amber[700], size: 20),
            ],
          ),
        ),
        SizedBox(
          height: 160,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('services')
                .where('shopId', isEqualTo: _shopId)
                .where('ativo', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.storefront, color: Colors.grey[400], size: 40),
                        const SizedBox(height: 8),
                        Text(
                          "Nenhum serviço ativo.",
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final docsWithPhotos = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final fotos = data['fotos_urls'] ?? 
                              data['fotos'] ?? 
                              data['imageUrl'] ?? 
                              data['imagens'] ?? 
                              [];
                
                if (fotos is String && fotos.isNotEmpty) return true;
                if (fotos is List && fotos.isNotEmpty) return true;
                
                return false;
              }).toList();

              if (docsWithPhotos.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      "Adicione fotos aos seus serviços para exibi-los aqui.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                scrollDirection: Axis.horizontal,
                itemCount: docsWithPhotos.length,
                itemBuilder: (context, index) {
                  final data = docsWithPhotos[index].data() 
                      as Map<String, dynamic>;
                  
                  dynamic fotosData = data['fotos_urls'] ?? 
                                      data['fotos'] ?? 
                                      data['imageUrl'] ?? 
                                      data['imagens'];
                  
                  String? thumb;
                  
                  if (fotosData is String) {
                    thumb = fotosData;
                  } else if (fotosData is List && fotosData.isNotEmpty) {
                    thumb = fotosData.first.toString();
                  }

                  if (thumb == null) return const SizedBox.shrink();

                  return Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: thumb,
                            fit: BoxFit.cover,
                            placeholder: (c, u) => Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (c, u, e) => Container(
                              color: Colors.grey[300],
                              child: const Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          ),
                          
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.8),
                                    Colors.transparent
                                  ],
                                ),
                              ),
                              child: Text(
                                data['nome'] ?? "Serviço",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD), // Fundo levemente cinza (moderno)
      // Botão Salvar Fixo no Rodapé (Sticky Footer)
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
                BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -4),
              )
            ],
          ),
          child: SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                disabledBackgroundColor: AppColors.primaryPurple.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      "SALVAR ALTERAÇÕES",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryPurple))
          : CustomScrollView(
              slivers: [
                // 1. Header Imersivo com Capa
                SliverAppBar(
                  expandedHeight: 200.0,
                  pinned: true,
                  backgroundColor: AppColors.primaryPurple,
                  title: Text(
                    _isSaving ? "Salvando..." : "Editar Perfil",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  centerTitle: true,
                  iconTheme: const IconThemeData(color: Colors.white),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Imagem da Capa
                        GestureDetector(
                          onTap: () => _pickAndEditImage(isCover: true),
                          child: _newCoverFile != null
                              ? (kIsWeb
                                  ? Image.network(_newCoverFile!.path, fit: BoxFit.cover)
                                  : Image.file(File(_newCoverFile!.path), fit: BoxFit.cover))
                              : (_coverUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: _coverUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (c, u) => Container(color: AppColors.primaryPurple.withValues(alpha: 0.2)),
                                    )
                                  : Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [AppColors.primaryPurple, Color(0xFF4A148C)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: const Center(
                                        child: Icon(Icons.store, size: 60, color: Colors.white24),
                                      ),
                                    )),
                        ),
                        // Overlay Escuro para botão de editar ficar visível
                        Container(color: Colors.black12),
                        // Botão Editar Capa
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: InkWell(
                            onTap: () => _pickAndEditImage(isCover: true),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.camera_alt, color: Colors.white, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    "Alterar Capa",
                                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Logo sobreposta (posicionada para ficar acima da capa)
                        Positioned(
                          bottom: -55,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: GestureDetector(
                              onTap: () => _pickAndEditImage(isCover: false),
                              child: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  Container(
                                    width: 110,
                                    height: 110,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      border: Border.all(color: Colors.white, width: 4),
                                      boxShadow: [
                                          BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.15),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        )
                                      ],
                                    ),
                                    child: ClipOval(
                                      child: _newLogoFile != null
                                          ? (kIsWeb
                                              ? Image.network(_newLogoFile!.path, fit: BoxFit.cover)
                                              : Image.file(File(_newLogoFile!.path), fit: BoxFit.cover))
                                          : (_logoUrl != null
                                              ? CachedNetworkImage(
                                                  imageUrl: _logoUrl!,
                                                  fit: BoxFit.cover,
                                                  placeholder: (c, u) => const CircularProgressIndicator(),
                                                  errorWidget: (c, u, e) => const Icon(Icons.store, color: Colors.grey, size: 40),
                                                )
                                              : Icon(Icons.add_a_photo, color: Colors.grey[400], size: 40)),
                                    ),
                                  ),
                                  // Botão Editar Logo
                                  Container(
                                    margin: const EdgeInsets.only(right: 4, bottom: 4),
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: AppColors.primaryPurple,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.edit, color: Colors.white, size: 16),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Conteúdo do Corpo (Form)
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      // Espaço reservado para a logo sobreposta
                      const SizedBox(height: 60),
                      // Formulário
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTextField(
                                controller: _nameController,
                                label: "Nome da Loja",
                                icon: Icons.store_mall_directory,
                                validator: (v) => v!.isEmpty ? "Campo obrigatório" : null,
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: _descController,
                                label: "Descrição",
                                icon: Icons.description,
                                maxLines: 3,
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: _addressController,
                                label: "Endereço",
                                icon: Icons.location_on,
                              ),
                              const SizedBox(height: 16),
                              _buildTextField(
                                controller: _phoneController,
                                label: "Telefone / WhatsApp",
                                icon: Icons.phone,
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 20),
                              
                              // Seção Link Personalizado
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryPurple.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.primaryPurple.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.link, color: AppColors.primaryPurple, size: 20),
                                        const SizedBox(width: 8),
                                        const Text(
                                          "Link Personalizado da Sua Loja",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      "Crie um link único para seus clientes acessarem sua loja",
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _slugController,
                                      decoration: InputDecoration(
                                        labelText: "Seu Link (ex: afroED)",
                                        prefixIcon: const Icon(Icons.link, color: AppColors.primaryPurple),
                                        prefixText: "markaai.com.br/",
                                        prefixStyle: const TextStyle(
                                          color: AppColors.primaryPurple,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        filled: true,
                                        fillColor: Colors.white,
                                      ),
                                      validator: (v) {
                                        if (v == null || v.isEmpty) return null;
                                        if (v.length < 3) return "Mínimo 3 caracteres";
                                        if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(v)) {
                                          return "Apenas letras, números e hífen";
                                        }
                                        return null;
                                      },
                                      onChanged: (value) {
                                        setState(() {}); // Atualiza o preview
                                      },
                                    ),
                                    if (_slugController.text.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.check_circle, color: Colors.green, size: 18),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    "Seu link público:",
                                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  SelectableText(
                                                    "https://markaai.com.br/${_normalizeSlug(_slugController.text)}",
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppColors.primaryPurple,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(Icons.copy, size: 20),
                                              color: AppColors.primaryPurple,
                                              tooltip: "Copiar link",
                                              onPressed: () {
                                                final link = "https://markaai.com.br/${_normalizeSlug(_slugController.text)}";
                                                Clipboard.setData(ClipboardData(text: link));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text("Link copiado!"),
                                                    backgroundColor: Colors.green,
                                                    duration: Duration(seconds: 2),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 20),
                              
                              // Seção Redes Sociais
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.blue.shade100,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.share, color: Colors.blue.shade700, size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          "Redes Sociais",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.blue.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      "Conecte suas redes sociais para seus clientes encontrarem você",
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                    const SizedBox(height: 12),
                                    _buildTextField(
                                      controller: _instagramController,
                                      label: "Instagram (ex: @minha_loja)",
                                      icon: Icons.camera_alt,
                                      keyboardType: TextInputType.text,
                                    ),
                                    const SizedBox(height: 12),
                                    _buildTextField(
                                      controller: _whatsappController,
                                      label: "WhatsApp Público (ex: 11999999999)",
                                      icon: Icons.phone,
                                      keyboardType: TextInputType.phone,
                                    ),
                                  ],
                                ),
                              ),
                              
                              const SizedBox(height: 30),
                            ],
                          ),
                        ),
                      ),

                      // Vitrine de Serviços (Estilo Moderno)
                      Container(
                        color: Colors.white, // Fundo branco para destacar a seção
                        padding: const EdgeInsets.only(bottom: 30),
                        child: _buildServicesShowcase(),
                      ),
                      
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // Widget auxiliar para TextFields bonitos
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Container(
            decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: AppColors.primaryPurple.withValues(alpha: 0.7)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
      ),
    );
  }
}

// 🎨 WIDGET DE AJUSTE DE IMAGEM (Mantido 100% igual)
class _ImageAdjustmentPage extends StatefulWidget {
  final XFile imageFile;
  final double aspectRatio;

  const _ImageAdjustmentPage({
    required this.imageFile,
    this.aspectRatio = 1.0,
  });

  @override
  State<_ImageAdjustmentPage> createState() => _ImageAdjustmentPageState();
}

class _ImageAdjustmentPageState extends State<_ImageAdjustmentPage> {
  double _scale = 1.0;
  double _previousScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _previousOffset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text("Ajustar Imagem"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, widget.imageFile);
            },
            child: const Text(
              "PRONTO",
              style: TextStyle(
                color: AppColors.primaryPurple,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: GestureDetector(
          onScaleStart: (details) {
            _previousScale = _scale;
            _previousOffset = _offset;
          },
          onScaleUpdate: (details) {
            setState(() {
              _scale = (_previousScale * details.scale).clamp(1.0, 4.0);
              _offset = _previousOffset + details.focalPointDelta;
            });
          },
          child: ClipRect(
            child: Transform(
              transform: Matrix4.identity()
                ..translate(_offset.dx, _offset.dy)
                ..scale(_scale),
              child: kIsWeb
                  ? Image.network(widget.imageFile.path)
                  : Image.file(File(widget.imageFile.path)),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.black87,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: const Icon(Icons.zoom_out, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _scale = (_scale - 0.1).clamp(1.0, 4.0);
                    });
                  },
                ),
                Text(
                  "${(_scale * 100).toInt()}%",
                  style: const TextStyle(color: Colors.white),
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_in, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _scale = (_scale + 0.1).clamp(1.0, 4.0);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              "Arraste para reposicionar • Pinçar para zoom",
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}