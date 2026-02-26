import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
// 🚨 IMPORT CORRIGIDO: Apontando para a Home de Negócios real
import 'business_home_page.dart';

const List<String> _kOnboardingUFs = [
  'AC',
  'AL',
  'AP',
  'AM',
  'BA',
  'CE',
  'DF',
  'ES',
  'GO',
  'MA',
  'MT',
  'MS',
  'MG',
  'PA',
  'PB',
  'PR',
  'PE',
  'PI',
  'RJ',
  'RN',
  'RS',
  'RO',
  'RR',
  'SC',
  'SP',
  'SE',
  'TO',
];

class BusinessOnboardingPage extends StatefulWidget {
  const BusinessOnboardingPage({super.key});

  @override
  State<BusinessOnboardingPage> createState() => _BusinessOnboardingPageState();
}

class _BusinessOnboardingPageState extends State<BusinessOnboardingPage> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isSaving = false;
  File? _logoImage;

  final _nomeLojaController = TextEditingController();
  final _categoriaController = TextEditingController();
  final _donoNomeController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _cidadeController = TextEditingController(); // 🌍 NOVO
  String? _estadoSelecionado; // 🌍 NOVO
  final _phoneMask = MaskTextInputFormatter(
      mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});

  Future<void> _pickLogo() async {
    final ImagePicker picker = ImagePicker();
    final XFile? original = await picker.pickImage(source: ImageSource.gallery);

    if (original != null) {
      final dir = await getTemporaryDirectory();
      final targetPath =
          "${dir.absolute.path}/temp_logo_${DateTime.now().millisecondsSinceEpoch}.jpg";

      final XFile? compressed = await FlutterImageCompress.compressAndGetFile(
        original.path,
        targetPath,
        quality: 70,
        minWidth: 500,
        minHeight: 500,
      );

      if (compressed != null) {
        setState(() => _logoImage = File(compressed.path));
      }
    }
  }

  Future<String> _uploadLogo(String shopId) async {
    if (_logoImage == null) return "";
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('business_logos')
          .child('$shopId.jpg');
      await ref.putFile(_logoImage!);
      return await ref.getDownloadURL();
    } catch (e) {
      return "";
    }
  }

  void _nextPage() {
    _pageController.nextPage(
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    setState(() => _currentStep++);
  }

  Future<void> _finalizarCadastroEmpresa() async {
    if (_telefoneController.text.isEmpty) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    setState(() => _isSaving = true);

    try {
      // 🛡️ Usamos o ID do usuário logado para manter a integridade
      final String uid = currentUser.uid;
      final newShopRef = FirebaseFirestore.instance.collection('shops').doc();

      String logoUrl = await _uploadLogo(newShopRef.id);

      // 1. Salva a Loja (Shop)
      await newShopRef.set({
        'id': newShopRef.id,
        'nome': _nomeLojaController.text.trim(),
        'categoria': _categoriaController.text.trim(),
        'dono_id': uid,
        'telefone': _telefoneController.text.trim(),
        'imageUrl': logoUrl, // Sincronizado com o nome usado na ClientHomePage
        'cidade': _cidadeController.text.trim(), // 🌍 NOVO
        'estado': _estadoSelecionado ?? '', // 🌍 NOVO
        'sem_endereco_fixo': false,
        'criado_em': FieldValue.serverTimestamp(),
        // 🚀 Configuração de Assinatura (Trial de 90 dias)
        'subscription': {
          'plan_id': 'starter', // Plano base após o trial
          'status': 'trial',
          'trial_ends_at':
              Timestamp.fromDate(DateTime.now().add(const Duration(days: 90))),
          'updated_at': FieldValue.serverTimestamp(),
        },
      });

      // 2. Atualiza o perfil do Usuário como Dono (Business)
      // Atualiza tanto 'tipo' quanto 'role' para manter consistência com rotas existentes
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'nome': _donoNomeController.text.trim(),
        'role': 'business',
        'tipo': 'dono',
        'shopId': newShopRef.id,
        'telefone': _telefoneController.text.trim(),
      });

      // 3. Salva Sessão
      await SessionService.saveLogin(
          userType: 'pro', userId: uid, shopId: newShopRef.id);

      if (mounted) {
        // 🚨 NAVEGAÇÃO CORRIGIDA: Vai para o Painel de Negócios real
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const BusinessHomePage()),
            (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erro ao criar negócio: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text("Configurar Negócio (${_currentStep + 1}/3)",
            style: const TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primaryPurple),
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildStep(
            title: "Marca e Nome",
            child: Column(children: [
              GestureDetector(
                  onTap: _pickLogo,
                  child: CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey[100],
                      backgroundImage:
                          _logoImage != null ? FileImage(_logoImage!) : null,
                      child: _logoImage == null
                          ? const Icon(Icons.add_a_photo,
                              size: 40, color: AppColors.primaryPurple)
                          : null)),
              const SizedBox(height: 30),
              TextFormField(
                  controller: _nomeLojaController,
                  decoration: const InputDecoration(
                      labelText: "Nome do seu Estabelecimento",
                      border: OutlineInputBorder())),
            ]),
            onNext: () =>
                _nomeLojaController.text.isNotEmpty ? _nextPage() : null,
          ),
          _buildStep(
            title: "Informações",
            child: Column(children: [
              TextFormField(
                  controller: _donoNomeController,
                  decoration: const InputDecoration(
                      labelText: "Nome do Gestor Responsável",
                      border: OutlineInputBorder())),
              const SizedBox(height: 20),
              TextFormField(
                  controller: _categoriaController,
                  decoration: const InputDecoration(
                      labelText: "Categoria (Ex: Barbearia, Estética)",
                      border: OutlineInputBorder())),
            ]),
            onNext: () =>
                _donoNomeController.text.isNotEmpty ? _nextPage() : null,
          ),
          _buildStep(
            title: "Contato Direto",
            child: Column(children: [
              const Text(
                  "Este número será usado para os clientes entrarem em contato via WhatsApp.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              TextFormField(
                  controller: _telefoneController,
                  inputFormatters: [_phoneMask],
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: "WhatsApp da Empresa",
                      border: OutlineInputBorder())),
              const SizedBox(height: 20),
              // 🌍 CIDADE E ESTADO — obrigatórios desde o cadastro inicial
              TextFormField(
                controller: _cidadeController,
                decoration: const InputDecoration(
                  labelText: 'Cidade *',
                  hintText: 'Ex: São Paulo',
                  prefixIcon: Icon(Icons.location_city),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _estadoSelecionado,
                decoration: const InputDecoration(
                  labelText: 'Estado (UF) *',
                  prefixIcon: Icon(Icons.flag),
                  border: OutlineInputBorder(),
                ),
                hint: const Text('Selecione o estado'),
                items: _kOnboardingUFs
                    .map((uf) => DropdownMenuItem(value: uf, child: Text(uf)))
                    .toList(),
                onChanged: (v) => setState(() => _estadoSelecionado = v),
              ),
            ]),
            btnText: "FINALIZAR E ABRIR PAINEL",
            isLoading: _isSaving,
            onNext: () {
              if (_telefoneController.text.isEmpty) return;
              if (_cidadeController.text.trim().isEmpty ||
                  _estadoSelecionado == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text('⚠️ Informe a cidade e o estado para continuar.'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              _finalizarCadastroEmpresa();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStep(
      {required String title,
      required Widget child,
      required VoidCallback onNext,
      String btnText = "CONTINUAR",
      bool isLoading = false}) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryPurple)),
          const SizedBox(height: 40),
          child,
          const Spacer(),
          SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                  onPressed: isLoading ? null : onNext,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(btnText,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold))))
        ],
      ),
    );
  }
}
