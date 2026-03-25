import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../core/models/user_model.dart';
import '../../core/models/shop_model.dart';
import '../../core/services/image_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _nameController = TextEditingController();
  final _shopNameController = TextEditingController();
  bool _isLoading = false;
  double _uploadProgress = 0.0;
  XFile? _newProfileFile;
  String? shopId;
  UserModel? _userModel;
  ShopModel? _shopModel;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final userData = await Supabase.instance.client
        .from('users')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (userData != null) {
      _userModel = UserModel.fromMap(userData);
      shopId = _userModel!.shopId;
      setState(() {
        _nameController.text = _userModel!.name;
      });
    }

    if (shopId != null) {
      final shopData = await Supabase.instance.client
          .from('shops')
          .select()
          .eq('id', shopId!)
          .maybeSingle();

      if (shopData != null) {
        _shopModel = ShopModel.fromMap(shopData);
        setState(() {
          _shopNameController.text = _shopModel!.name;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1000);
    if (image != null) {
      setState(() => _newProfileFile = image);
    }
  }

  Future<void> _saveChanges() async {
    setState(() {
      _isLoading = true;
      _uploadProgress = 0.1;
    });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      String? photoUrl = _userModel?.photoUrl;

      // Upload da nova foto se selecionada
      if (_newProfileFile != null) {
        photoUrl = await ImageService.uploadProfilePhoto(
          _newProfileFile!, 
          user.id,
          onProgress: (p) => setState(() => _uploadProgress = p),
        );
      }

      // Atualiza nome do profissional
      if (_userModel != null) {
        final updatedUser = UserModel(
          id: _userModel!.id,
          name: _nameController.text.trim(),
          email: _userModel!.email,
          phone: _userModel!.phone,
          role: _userModel!.role,
          shopId: _userModel!.shopId,
          plan: _userModel!.plan,
          isActive: _userModel!.isActive,
          photoUrl: photoUrl ?? _userModel!.photoUrl,
          zipCode: _userModel!.zipCode,
          street: _userModel!.street,
          number: _userModel!.number,
          city: _userModel!.city,
          neighborhood: _userModel!.neighborhood,
          documentCpf: _userModel!.documentCpf,
          gender: _userModel!.gender,
          bio: _userModel!.bio,
        );

        await Supabase.instance.client
            .from('users')
            .update(updatedUser.toMap())
            .eq('id', user.id);
      }

      // Atualiza nome da empresa
      if (shopId != null && _shopModel != null) {
        final updatedShop = ShopModel(
          id: _shopModel!.id,
          name: _shopNameController.text.trim(),
          description: _shopModel!.description,
          address: _shopModel!.address,
          phone: _shopModel!.phone,
          slug: _shopModel!.slug,
          instagram: _shopModel!.instagram,
          whatsapp: _shopModel!.whatsapp,
          logoUrl: _shopModel!.logoUrl,
          imageUrl: _shopModel!.imageUrl,
          city: _shopModel!.city,
          state: _shopModel!.state,
          zipCode: _shopModel!.zipCode,
          category: _shopModel!.category,
          niche: _shopModel!.niche,
        );

        await Supabase.instance.client
            .from('shops')
            .update(updatedShop.toMap())
            .eq('id', shopId!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Alterações e foto salvas com sucesso!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(
              content: Text("❌ Erro ao salvar: $e"),
              backgroundColor: Colors.red,
            ));
      }
    } finally {
      if (mounted) setState(() {
        _isLoading = false;
        _uploadProgress = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Editar Perfil e Studio"),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 70,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: _newProfileFile != null
                        ? FileImage(File(_newProfileFile!.path))
                        : (_userModel?.photoUrl != null
                            ? CachedNetworkImageProvider(_userModel!.photoUrl!)
                            : null) as ImageProvider?,
                    child: (_newProfileFile == null && _userModel?.photoUrl == null)
                        ? const Icon(Icons.person, size: 70, color: Colors.grey)
                        : null,
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: AppColors.primaryPurple,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            if (_uploadProgress > 0 && _uploadProgress < 1.0) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _uploadProgress,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryPurple),
              ),
              const SizedBox(height: 8),
              Text("${(_uploadProgress * 100).toInt()}% enviando foto..."),
            ],
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                  labelText: "Seu Nome Profissional",
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _shopNameController,
              decoration: const InputDecoration(
                  labelText: "Nome do Studio/Negócio",
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("SALVAR ALTERAÇÕES",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}