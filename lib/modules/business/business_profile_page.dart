import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../../core/theme/app_colors.dart';

class BusinessProfilePage extends StatefulWidget {
  final String shopId;
  const BusinessProfilePage({super.key, required this.shopId});

  @override
  State<BusinessProfilePage> createState() => _BusinessProfilePageState();
}

class _BusinessProfilePageState extends State<BusinessProfilePage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isUploading = false;

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController(); // ✅ NOVO: Instagram
  
  String? _imageUrl; // Capa
  String? _logoUrl;  // Logo

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _categoryCtrl.dispose();
    _instagramCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (widget.shopId.isEmpty) return;
    setState(() => _isLoading = true);
    
    try {
      final doc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .get();
          
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        
        _nameCtrl.text = data['nome'] ?? "";
        _descCtrl.text = data['descricao'] ?? data['bio'] ?? "";
        _addressCtrl.text = data['endereco'] ?? "";
        _phoneCtrl.text = data['telefone'] ?? data['whatsapp'] ?? "";
        _categoryCtrl.text = data['categoria'] ?? "";
        _instagramCtrl.text = data['instagram'] ?? ""; // ✅ CARREGA Instagram
        
        if (mounted) {
          setState(() {
            _imageUrl = (data['imageUrl'] != null && data['imageUrl'].toString().isNotEmpty) 
                ? data['imageUrl'] 
                : null;
            
            _logoUrl = (data['logoUrl'] != null && data['logoUrl'].toString().isNotEmpty) 
                ? data['logoUrl'] 
                : data['foto'];
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao carregar: $e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .update({
        'nome': _nameCtrl.text.trim(),
        'descricao': _descCtrl.text.trim(),
        'endereco': _addressCtrl.text.trim(),
        'telefone': _phoneCtrl.text.trim(),
        'categoria': _categoryCtrl.text.trim(),
        'instagram': _instagramCtrl.text.trim(), // ✅ SALVA Instagram
        'imageUrl': _imageUrl,
        'logoUrl': _logoUrl,
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Perfil atualizado com sucesso!"),
            backgroundColor: Colors.green,
          )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadImage(bool isCover) async {
    final ImagePicker picker = ImagePicker();
    
    try {
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: isCover ? 1920 : 800,
        maxHeight: isCover ? 1080 : 800,
        imageQuality: 85,
      );
      
      if (image == null) return;

      setState(() => _isUploading = true);

      Uint8List bytes = await image.readAsBytes();
      
      String fileName = isCover 
          ? 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg' 
          : 'logo_${DateTime.now().millisecondsSinceEpoch}.jpg';
          
      Reference ref = FirebaseStorage.instance
          .ref()
          .child('shops/${widget.shopId}/$fileName');

      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      String downloadUrl = await ref.getDownloadURL();

      if (mounted) {
        setState(() {
          if (isCover) {
            _imageUrl = downloadUrl;
          } else {
            _logoUrl = downloadUrl;
          }
          _isUploading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCover 
                  ? "📸 Capa carregada! Clique em SALVAR." 
                  : "📸 Logo carregada! Clique em SALVAR."
            ),
            backgroundColor: Colors.blue,
          )
        );
      }

    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _nameCtrl.text.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      color: const Color(0xFFF8F9FD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ INDICADOR DE UPLOAD (se estiver enviando)
          if (_isUploading)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text(
                          "Enviando...",
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          // ✅ CONTEÚDO COM EXPANDED PARA PREENCHER ESPAÇO DISPONÍVEL
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

              // ✅ CARD COMPACTO COM IMAGENS
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Column(
                  children: [
                    // Banner + Logo
                    SizedBox(
                      height: 130, // ✅ Reduzido ainda mais (era 160)
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // CAPA
                          GestureDetector(
                            onTap: _isUploading ? null : () => _pickAndUploadImage(true),
                            child: Container(
                              key: ValueKey('cover_$_imageUrl'),
                              height: 100, // ✅ Reduzido (era 120)
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
                                image: _imageUrl != null && _imageUrl!.isNotEmpty
                                    ? DecorationImage(
                                        image: NetworkImage(_imageUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: _imageUrl == null || _imageUrl!.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: const [
                                          Icon(Icons.add_photo_alternate, 
                                               color: Colors.grey, size: 32),
                                          SizedBox(height: 4),
                                          Text("Adicionar Capa",
                                               style: TextStyle(color: Colors.grey, fontSize: 12)),
                                        ],
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          
                          // Botão editar capa
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 8,
                                  )
                                ],
                              ),
                              child: IconButton(
                                iconSize: 20,
                                icon: const Icon(Icons.edit, color: AppColors.primaryPurple),
                                onPressed: _isUploading ? null : () => _pickAndUploadImage(true),
                              ),
                            ),
                          ),
                          
                          // ✅ LOGO DA LOJA (editável pelo usuário)
                          Positioned(
                            bottom: 0,
                            left: 20,
                            child: GestureDetector(
                              onTap: _isUploading ? null : () => _pickAndUploadImage(false),
                              child: Container(
                                key: ValueKey('logo_$_logoUrl'),
                                height: 70, // ✅ Reduzido (era 80)
                                width: 70,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 12,
                                    ),
                                  ],
                                  image: _logoUrl != null && _logoUrl!.isNotEmpty
                                      ? DecorationImage(
                                          image: NetworkImage(_logoUrl!),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: _logoUrl == null || _logoUrl!.isEmpty
                                    ? const Center(
                                        child: Icon(
                                          Icons.add_a_photo,
                                          color: Colors.grey,
                                          size: 24, // ✅ Reduzido
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          
                          // Botão de editar logo
                          Positioned(
                            bottom: 2,
                            left: 68, // ✅ Ajustado
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.primaryPurple,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: IconButton(
                                iconSize: 14, // ✅ Reduzido
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28, // ✅ Reduzido
                                  minHeight: 28,
                                ),
                                icon: const Icon(Icons.camera_alt, color: Colors.white),
                                onPressed: _isUploading ? null : () => _pickAndUploadImage(false),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // ✅ FORMULÁRIO COMPACTO (2 colunas lado a lado)
                    Padding(
                      padding: const EdgeInsets.all(16), // ✅ Reduzido de 20 para 16
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildCompactInput(
                                  "Nome do Negócio",
                                  _nameCtrl,
                                  Icons.store,
                                ),
                              ),
                              const SizedBox(width: 10), // ✅ Reduzido
                              Expanded(
                                flex: 2,
                                child: _buildCompactInput(
                                  "Categoria",
                                  _categoryCtrl,
                                  Icons.category,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10), // ✅ Reduzido
                          _buildCompactInput(
                            "Descrição / Bio",
                            _descCtrl,
                            Icons.description,
                            maxLines: 2,
                          ),
                          const SizedBox(height: 10), // ✅ Reduzido
                          Row(
                            children: [
                              Expanded(
                                child: _buildCompactInput(
                                  "Endereço",
                                  _addressCtrl,
                                  Icons.location_on,
                                ),
                              ),
                              const SizedBox(width: 10), // ✅ Reduzido
                              Expanded(
                                child: _buildCompactInput(
                                  "Telefone / WhatsApp",
                                  _phoneCtrl,
                                  Icons.phone,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10), // ✅ Reduzido
                          // ✅ CAMPO INSTAGRAM
                          _buildCompactInput(
                            "Instagram",
                            _instagramCtrl,
                            Icons.camera_alt,
                            hint: "@seu_usuario",
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
                    const SizedBox(height: 16), // ✅ Reduzido de 20 para 16
                    
                    // ✅ BOTÃO SALVAR
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: (_isLoading || _isUploading) ? null : _saveData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPurple,
                          disabledBackgroundColor: Colors.grey[400],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        icon: _isLoading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_circle, color: Colors.white),
                        label: Text(
                          _isLoading ? "Salvando..." : "SALVAR ALTERAÇÕES",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ CAMPO MAIS COMPACTO
  Widget _buildCompactInput(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    int maxLines = 1,
    String? hint,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(fontSize: 13),
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.primaryPurple, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primaryPurple, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
      ),
      validator: (v) => v == null || v.trim().isEmpty ? "Obrigatório" : null,
    );
  }
}