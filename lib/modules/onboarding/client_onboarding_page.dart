import 'dart:io';
// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:pinput/pinput.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart'; // <--- O Mágico do SMS
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/viacep_service.dart';
import '../../core/services/session_service.dart';
import '../clients/client_home_page.dart';

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
  File? _selectedImage;

  // Variáveis do Firebase Auth
  String? _verificationId;
  final FirebaseAuth _auth = FirebaseAuth.instance;

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
    if (image != null) setState(() => _selectedImage = File(image.path));
  }

  Future<String> _uploadImage(String userId) async {
    if (_selectedImage == null) return "";
    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('user_photos')
          .child('$userId.jpg');
      await ref.putFile(_selectedImage!);
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
      // 2. VERIFICA SE O NÚMERO JÃ EXISTE NO BANCO (Anti-Duplicidade)
      // Nota: Estamos comparando o formato exato salvo: "(xx) xxxxx-xxxx"
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('telefone', isEqualTo: _phoneController.text)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        // JÃ EXISTE! PARA TUDO.
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

      // 3. SE NÃO EXISTE, MANDA O SMS
      // Formata para padrão internacional (+55319...)
      String rawPhone = _phoneController.text.replaceAll(RegExp(r'[^\d]'), '');
      String formattedPhone = "+55$rawPhone";

      await _auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Android pode verificar automático (raro em emulador, comum em físico)
          await _auth.signInWithCredential(credential);
          _nextPage();
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isSendingSMS = false);
          String msg = "Erro no envio do SMS.";
          if (e.code == 'invalid-phone-number') msg = "Número inválido.";
          // Se der erro de SHA-1, vai aparecer aqui como 'app-not-authorized' ou similar
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text("$msg (${e.code})"), backgroundColor: Colors.red));
        },
        codeSent: (String verificationId, int? resendToken) {
          // SUCESSO! O SMS FOI
          setState(() {
            _verificationId = verificationId;
            _isSendingSMS = false;
          });
          _nextPage(); // Vai para a tela de digitar o código
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() => _isSendingSMS = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Erro: $e")));
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
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
          verificationId: _verificationId!, smsCode: _pinController.text);

      // Tenta autenticar com o código
      await _auth.signInWithCredential(credential);

      // Se passou, deu certo!
      setState(() => _isSendingSMS = false);
      _nextPage();
    } catch (e) {
      setState(() => _isSendingSMS = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Código incorreto!"), backgroundColor: Colors.red));
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
      final docRef = FirebaseFirestore.instance.collection('users').doc();
      String photoUrl = await _uploadImage(docRef.id);

      // Pega o usuário logado no Auth para garantir segurança (opcional, mas bom)
      // final userAuth = FirebaseAuth.instance.currentUser;

      final dadosCliente = {
        'id': docRef.id,
        'auth_uid':
            _auth.currentUser?.uid, // Vincula com a autenticação do SMS
        'nome': _nameController.text,
        'telefone':
            _phoneController.text, // Salva formatado visualmente (31) 9...
        'endereco': _addressController.text,
        'numero': _numberController.text,
        'cep': _cepController.text,
        'foto_perfil': photoUrl,
        'tipo': 'cliente',
        'criado_em': FieldValue.serverTimestamp(),
      };

      await docRef.set(dadosCliente);

      // Salva Sessão
      await SessionService.saveLogin(
        userType: 'client',
        userId: docRef.id,
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
                      hintText: "(00) 00000-0000", border: InputBorder.none)),
              onNext: _submitPhone,
              btnText: "ENVIAR CÃ“DIGO",
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
                          ? FileImage(_selectedImage!)
                          : null,
                      child: _selectedImage == null
                          ? const Icon(Icons.camera_alt)
                          : null)),
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
                    decoration: const InputDecoration(labelText: "CEP")),
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
