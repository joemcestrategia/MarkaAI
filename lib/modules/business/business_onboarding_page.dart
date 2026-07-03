import 'dart:io' if (dart.library.html) 'package:markaai/core/utils/io_stub.dart' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:image_picker/image_picker.dart';
import '../../core/services/image_service.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/models/user_model.dart';
import '../../core/models/shop_model.dart';
// ?? IMPORT CORRIGIDO: Apontando para a Home de Negócios real
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
  double _uploadProgress = 0.0;
  io.File? _logoImage;
  UserModel? _userModel;

  final _nomeLojaController = TextEditingController();
  final _categoriaController = TextEditingController();
  final _donoNomeController = TextEditingController();
  final _telefoneController = TextEditingController();
  final _cidadeController = TextEditingController(); // ?? NOVO
  String? _estadoSelecionado; // ?? NOVO
  final _phoneMask = MaskTextInputFormatter(
      mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});


  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final supabase = sb.Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        final data = await supabase
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (data != null) {
          _userModel = UserModel.fromMap(data);
          if (mounted) {
            setState(() {
              _donoNomeController.text = _userModel!.name;
              _telefoneController.text = _userModel!.phone;
              _nomeLojaController.text = data['business_name'] ?? supabase.auth.currentUser?.userMetadata?['business_name'] ?? '';

              if (_userModel!.city != null) {
                // Tenta extrair a Cidade e UF se vier no formato "Cidade - UF" (do login_page)
                String cidadeRaw = _userModel!.city!;
                if (cidadeRaw.contains(' - ')) {
                  final parts = cidadeRaw.split(' - ');
                  _cidadeController.text = parts[0];
                  final ufRaw = parts[1].toUpperCase();
                  if (_kOnboardingUFs.contains(ufRaw)) {
                    _estadoSelecionado = ufRaw;
                  }
                } else {
                  _cidadeController.text = cidadeRaw;
                }
              }

            });
          }
        }
      } catch (e) {
        debugPrint("Erro ao carregar dados do usuário: $e");
      }
    }
  }

  Future<void> _pickLogo() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800);
    if (image != null) {
      setState(() => _logoImage = io.File(image.path));
    }
  }

  // Removida a função antiga _uploadLogo e substituída pelo uso direto do ImageService no _finalizarCadastroEmpresa

  void _nextPage() {
    _pageController.nextPage(
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    setState(() => _currentStep++);
  }

  Future<void> _finalizarCadastroEmpresa() async {
    if (_telefoneController.text.isEmpty) return;

    final supabase = sb.Supabase.instance.client;
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return;

    setState(() => _isSaving = true);

    try {
      final String uid = currentUser.id;
      
      // Criar um ID para a loja usando timestamp ou UUID
      final String generatedShopId = DateTime.now().millisecondsSinceEpoch.toString(); 

      String logoUrl = "";
      // Invertida a ordem: primeiro inserimos no banco para o RLS do storage funcionar

      String enderecoSalvo = '';
      String cepSalvo = '';
      String bairroSalvo = '';

      if (_userModel != null) {
        cepSalvo = _userModel!.zipCode ?? '';
        bairroSalvo = _userModel!.neighborhood ?? '';
        final rua = _userModel!.street ?? '';
        final numero = _userModel!.number ?? '';

        if (rua.isNotEmpty) {
          enderecoSalvo = numero.isNotEmpty ? "$rua, $numero" : rua;
        }
      }

      // 1. Salva a Loja (Shop)
      final shop = ShopModel(
        id: generatedShopId,
        name: _nomeLojaController.text.trim(),
        category: _categoriaController.text.trim(),
        niche: _categoriaController.text.trim(),
        phone: _telefoneController.text.trim(),
        whatsapp: _telefoneController.text.trim(),
        imageUrl: logoUrl,
        city: _cidadeController.text.trim(),
        state: _estadoSelecionado ?? '',
        address: enderecoSalvo,
        zipCode: cepSalvo,
        neighborhood: bairroSalvo,
        ownerId: uid,
        planId: 'free',
      );

      await supabase.from('shops').insert(shop.toMap());

      // Agora que a loja existe no banco, o RLS permitirá o upload
      if (_logoImage != null) {
        setState(() => _uploadProgress = 0.1);
        logoUrl = await ImageService.uploadStoreLogo(
          _logoImage!, 
          generatedShopId,
          updateDatabase: true, // Já atualiza o campo logo_url no banco
          onProgress: (p) => setState(() => _uploadProgress = p),
        );
      }

      // 2. Atualiza o perfil do Usuário como Dono (Business)
      if (_userModel != null) {
        final updatedUser = UserModel(
          id: _userModel!.id,
          name: _donoNomeController.text.trim(),
          email: _userModel!.email,
          phone: _telefoneController.text.trim(),
          role: 'business',
          shopId: generatedShopId,
          plan: _userModel!.plan,
          isActive: _userModel!.isActive,
          photoUrl: _userModel!.photoUrl,
          zipCode: _userModel!.zipCode,
          street: _userModel!.street,
          number: _userModel!.number,
          city: _cidadeController.text.trim(), // Atualizado com o que a pessoa digitou na Onboarding
          state: _estadoSelecionado ?? '',    // Usar estado e cidade atualizados da Onboarding para a Loja
          neighborhood: _userModel!.neighborhood,
          address: _userModel!.address,
          documentCpf: _userModel!.documentCpf,
          gender: _userModel!.gender,
          bio: _userModel!.bio,
        );
        await supabase.from('users').update(updatedUser.toMap()).eq('id', uid);
      }

      // 3. Salva Sessão
      await SessionService.saveLogin(
          userType: 'pro', userId: uid, shopId: generatedShopId);

      if (mounted) {
        // ?? NAVEGAÇÃO CORRIGIDA: Vai para o Painel de Negócios real
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const BusinessHomePage()),
            (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("❌ Erro ao criar negócio: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() {
        _isSaving = false;
        _uploadProgress = 0.0;
      });
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
                          _logoImage != null ? (kIsWeb ? NetworkImage(_logoImage!.path) as ImageProvider : FileImage(io.File(_logoImage!.path) as dynamic) as ImageProvider) : null,
                      child: _logoImage == null
                          ? const Icon(Icons.add_a_photo,
                              size: 40, color: AppColors.primaryPurple)
                          : null)),
              if (_uploadProgress > 0 && _uploadProgress < 1.0) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(
                    value: _uploadProgress,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryPurple),
                  ),
                ),
                const SizedBox(height: 8),
                Text("${(_uploadProgress * 100).toInt()}% enviando logo..."),
              ],
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
              // ?? CIDADE E ESTADO — obrigatórios desde o cadastro inicial
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
                initialValue: _estadoSelecionado,
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
                        Text('?? Informe a cidade e o estado para continuar.'),
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
                      foregroundColor: Colors.white,
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
