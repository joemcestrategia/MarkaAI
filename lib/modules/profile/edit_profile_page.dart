import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_colors.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _nameController = TextEditingController();
  final _shopNameController = TextEditingController();
  bool _isLoading = false;
  String? shopId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    shopId = userDoc.data()?['shopId'];
    
    if (shopId != null) {
      final shopDoc = await FirebaseFirestore.instance.collection('shops').doc(shopId).get();
      setState(() {
        _nameController.text = userDoc.data()?['nome'] ?? "";
        _shopNameController.text = shopDoc.data()?['nome'] ?? "";
      });
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      // Atualiza nome do profissional
      await FirebaseFirestore.instance.collection('users').doc(user?.uid).update({
        'nome': _nameController.text,
      });
      // Atualiza nome da empresa
      if (shopId != null) {
        await FirebaseFirestore.instance.collection('shops').doc(shopId).update({
          'nome': _shopNameController.text,
        });
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Editar Perfil e Studio"), backgroundColor: AppColors.primaryPurple),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 60,
              backgroundColor: Colors.grey,
              child: Icon(Icons.camera_enhance, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Seu Nome Profissional", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _shopNameController,
              decoration: const InputDecoration(labelText: "Nome do Studio/Negócio", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveChanges,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple),
                child: _isLoading 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : const Text("SALVAR ALTERAÇÕES", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}