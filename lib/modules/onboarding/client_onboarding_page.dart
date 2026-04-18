import 'package:flutter/foundation.dart';
import 'dart:io' if (dart.library.html) 'package:markaai/core/utils/io_stub.dart' as io;
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:pinput/pinput.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:markaai/core/theme/app_colors.dart';
import 'package:markaai/core/services/viacep_service.dart';
import 'package:markaai/core/services/session_service.dart';
import 'package:markaai/core/models/user_model.dart';
import 'package:markaai/modules/clients/client_home_page.dart';
import 'package:markaai/core/services/image_service.dart';

class ClientOnboardingPage extends StatefulWidget {
  const ClientOnboardingPage({super.key});

  @override
  State<ClientOnboardingPage> createState() => _ClientOnboardingPageState();
}

class _ClientOnboardingPageState extends State<ClientOnboardingPage> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  bool _isSaving = false;
  bool _isSendingSMS = false; // Loading do SMS
  double _uploadProgress = 0.0;
  io.File? _selectedImage;

  // Supabase Auth
  final _supabase = Supabase.instance.client;

  final _phoneController = TextEditingController();
  final _phoneMask = MaskTextInputFormatter(
      mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});
  final _pinController = TextEditingController();
  final _nameController = TextEditingController();
  final _cepController = TextEditingController();
  final _addressController = TextEditingController();
  final _numberController = TextEditingController();
  final _cepMask = MaskTextInputFormatter(
      mask: '#####-###', filter: {"#": RegExp(r'[0-9]')});
  bool _isLoadingCep = false;

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) setState(() => _selectedImage = io.File(image.path));
  }

  // Removida a função antiga _uploadImage e substituída pelo uso direto do ImageService no _finishRegistration

  void _nextPage() {
    _pageController.nextPage(
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    setState(() => _currentStep++);
  }

  // --- PASSO CRUCIAL: VERIFICAÇÃO + SMS ---
  Future<void> _submitPhone() async {
    // 1. Valida tamanho do número
    if (_phoneController.text.length < 15) {
      // (31) 99999-9999 tem 15 caracteres
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Número incompleto")));
      return;
    }

    setState(() => _isSendingSMS = true);

    try {
      // 2. VERIFICA SE O NÚMERO JÁ EXISTE NO BANCO (Anti-Duplicidade)
      final existingUser = await _supabase
          .from('users')
          .select()
          .eq('phone', _phoneController.text)
          .maybeSingle();

      if (existingUser != null) {
        // JÁ EXISTE! PARA TUDO.
        setState(() => _isSendingSMS = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Este número já possui conta! Faça Login."),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ));
        }
        return;
      }

      // 3. SE NÃO EXISTE, MANDA O SMS via Supabase
      // Formata para padrão internacional (+55319...)
      String rawPhone = _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');
      String formattedPhone = "+55$rawPhone";

      await _supabase.auth.signInWithOtp(
        phone: formattedPhone,
        shouldCreateUser: true,
      );

      // SUCESSO! O SMS FOI
      setState(() => _isSendingSMS = false);
      _nextPage(); // Vai para a tela de digitar o código
    } catch (e) {
      setState(() => _isSendingSMS = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Erro ao enviar SMS: $e")));
    }
  }

  // --- CONFIRMAÇÃO DO CÃ“DIGO ---
  Future<void> _submitCode() async {
    if (_pinController.text.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("O código tem 6 dígitos")));
      return;
    }

    setState(() => _isSendingSMS = true);

    try {
      String rawPhone = _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');
      String formattedPhone = "+55$rawPhone";

      final response = await _supabase.auth.verifyOTP(
        phone: formattedPhone,
        token: _pinController.text,
        type: OtpType.sms,
      );

      if (response.session == null) {
        throw Exception("Sessão não iniciada após verificação");
      }

      // Se passou, deu certo!
      setState(() => _isSendingSMS = false);
      _nextPage();
    } catch (e) {
      setState(() => _isSendingSMS = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Código incorreto ou expirado! $e"),
          backgroundColor: Colors.red));
    }
  }

  void _buscarCep(String cep) async {
    if (cep.length < 9) return;
    setState(() => _isLoadingCep = true);
    final res = await ViaCepService.buscarCep(cep);
    setState(() => _isLoadingCep = false);
    if (res != null) {
      _addressController.text = "${res['logradouro']}, ${res['bairro']}";
    }
  }

  Future<void> _finishRegistration() async {
    if (_numberController.text.isEmpty) return;
    setState(() => _isSaving = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      String photoUrl = "";
      if (_selectedImage != null) {
        setState(() => _uploadProgress = 0.1);
        photoUrl = await ImageService.uploadProfilePhoto(
          _selectedImage!, 
          user.id,
          onProgress: (p) => setState(() => _uploadProgress = p),
        );
      }

      final userModel = UserModel(
        id: user.id,
        name: _nameController.text.trim(),
        email: user.email ?? "",
        phone: _phoneController.text.trim(),
        role: 'cliente',
        photoUrl: photoUrl,
        street: _addressController.text.trim(),
        number: _numberController.text.trim(),
        zipCode: _cepController.text.trim(),
      );

      await _supabase.from('users').upsert(userModel.toMap());

      await SessionService.saveLogin(
        userType: 'client',
        userId: user.id,
      );

      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const ClientHomePage()),
            (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erro: $e")));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: LinearProgressIndicator(
              value: (_currentStep + 1) / 4, color: AppColors.primaryPurple)),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // Passo 1: Telefone
          _baseStep(
              title: "Qual seu WhatsApp?",
              subtitle: "Enviaremos um SMS de verdade.",
              child: TextFormField(
                  controller: _phoneController,
                  inputFormatters: [_phoneMask],
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                      hintText: "(00) 00000-0000", border: InputBorder.none),
                  validator: (v) {
                    if (v == null || v.isEmpty) return "Obrigatório";
                    if (v.replaceAll(RegExp(r'\D'), '').length < 10) {
                      return "Número inválido";
                    }
                    return null;
                  }),
              onNext: _submitPhone,
              btnText: "ENVIAR CÓDIGO",
              isLoading: _isSendingSMS),

          // Passo 2: Código
          _baseStep(
              title: "Código SMS",
              subtitle: "Digite os 6 números.",
              child: Pinput(
                  controller: _pinController,
                  length: 6,
                  autofocus: true,
                  onCompleted: (_) => _submitCode()),
              onNext: _submitCode,
              btnText: "VALIDAR",
              isLoading: _isSendingSMS),

          // Passo 3: Dados
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: _selectedImage != null
                          ? (kIsWeb
                              ? NetworkImage(_selectedImage!.path) as ImageProvider
                              : FileImage(io.File(_selectedImage!.path) as dynamic) as ImageProvider)
                          : null,
                      child: _selectedImage == null
                          ? const Icon(Icons.camera_alt)
                          : null)),
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
              const SizedBox(height: 20),
              TextFormField(
                  controller: _nameController,
                  decoration:
                      const InputDecoration(labelText: "Nome Completo")),
              const Spacer(),
              ElevatedButton(
                  onPressed: () =>
                      _nameController.text.isNotEmpty ? _nextPage() : null,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50)),
                  child: const Text("CONTINUAR",
                      style: TextStyle(color: Colors.white)))
            ]),
          ),

          // Passo 4: Endereço
          _baseStep(
              title: "Endereço",
              child: Column(children: [
                TextFormField(
                    controller: _cepController,
                    inputFormatters: [_cepMask],
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      if (v.length == 9) _buscarCep(v);
                    },
                    decoration: const InputDecoration(labelText: "CEP"),
                    validator: (v) {
                      if (v == null || v.isEmpty) return "Obrigatório";
                      if (v.replaceAll(RegExp(r'\D'), '').length < 8) {
                        return "CEP incompleto";
                      }
                      return null;
                    }),
                if (_isLoadingCep) const LinearProgressIndicator(),
                TextFormField(controller: _addressController),
                TextFormField(
                    controller: _numberController,
                    decoration: const InputDecoration(labelText: "Número"))
              ]),
              onNext: _finishRegistration,
              isLoading: _isSaving,
              btnText: "FINALIZAR"),
        ],
      ),
    );
  }

  Widget _baseStep(
      {required String title,
      String? subtitle,
      required Widget child,
      required VoidCallback onNext,
      bool isLoading = false,
      String btnText = "CONTINUAR"}) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryPurple)),
          if (subtitle != null)
            Text(subtitle,
                style: const TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 40),
          child,
          const Spacer(),
          ElevatedButton(
              onPressed: isLoading ? null : onNext,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50)),
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(btnText,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)))
        ],
      ),
    );
  }
}
