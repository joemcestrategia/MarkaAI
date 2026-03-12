// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart'; // NECESSÁRIO PARA FOTO
import 'dart:io'; // NECESSÁRIO PARA FOTO
import '../../core/theme/app_colors.dart';
import '../../core/services/viacep_service.dart';
import '../../core/services/session_service.dart'; // NECESSÁRIO PARA PEGAR ID DA LOJA
import 'client_home_page.dart';

class ClientRegisterPage extends StatefulWidget {
  final User? user;
  final bool isBusinessAdding;
  final bool returnOnSuccess;

  const ClientRegisterPage(
      {super.key,
      this.user,
      this.isBusinessAdding = false,
      this.returnOnSuccess = false});

  @override
  State<ClientRegisterPage> createState() => _ClientRegisterPageState();
}

class _ClientRegisterPageState extends State<ClientRegisterPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _cepController = TextEditingController();
  final _addressController = TextEditingController();
  final _numberController = TextEditingController();
  final _districtController = TextEditingController();
  final _cityController = TextEditingController();

  DateTime? _birthDate;
  File? _imageFile; // ARMAZENA A FOTO SELECIONADA
  bool _isLoadingCep = false;
  bool _isSaving = false;

  var phoneMask = MaskTextInputFormatter(
      mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});
  final cepMask = MaskTextInputFormatter(
      mask: '#####-###', filter: {"#": RegExp(r'[0-9]')});
  final FocusNode _numberFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.user != null) {
      _preencherDadosGoogle();
      _verificarTelefoneExistente();
      _loadExistingUserData();
    }
  }

  Future<void> _loadExistingUserData() async {
    if (widget.user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user!.uid)
          .get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      if (mounted) {
        setState(() {
          _nameController.text = data['nome'] ?? _nameController.text;
          _phoneController.text = data['telefone'] ?? _phoneController.text;
          // aniversario may be stored as string 'dd/MM/yyyy'
          final an = data['aniversario'];
          if (an is String && an.isNotEmpty) {
            try {
              final parts = an.split('/');
              if (parts.length == 3) {
                final d = int.parse(parts[0]);
                final m = int.parse(parts[1]);
                final y = int.parse(parts[2]);
                _birthDate = DateTime(y, m, d);
              }
            } catch (_) {}
          }
          final endereco = data['endereco'] as Map<String, dynamic>?;
          if (endereco != null) {
            _cepController.text = endereco['cep'] ?? '';
            _addressController.text = endereco['rua'] ?? '';
            _numberController.text = endereco['numero']?.toString() ?? '';
            _districtController.text = endereco['bairro'] ?? '';
            _cityController.text = endereco['cidade'] ?? '';
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados do usuário: $e');
    }
  }

  void _preencherDadosGoogle() {
    _nameController.text = widget.user?.displayName ?? "";
  }

  Future<void> _verificarTelefoneExistente() async {
    if (widget.user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user!.uid)
        .get();
    if (doc.exists && doc.data()?['telefone'] != null) {
      setState(() {
        _phoneController.text = doc.data()!['telefone'];
      });
    }
  }

  // --- NOVA FUNÇÃO: SELECIONAR FOTO ---
  Future<void> _pickImage() async {
    final pickedFile =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
    }
  }

  Future<void> _buscarCep(String cep) async {
    if (cep.length < 9) return;
    setState(() => _isLoadingCep = true);
    final resultado = await ViaCepService.buscarCep(cep);
    setState(() => _isLoadingCep = false);

    if (resultado != null) {
      _addressController.text = resultado['logradouro'];
      _districtController.text = resultado['bairro'];
      _cityController.text = "${resultado['localidade']} - ${resultado['uf']}";
      FocusScope.of(context).requestFocus(_numberFocus);
    }
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1995),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
          data: Theme.of(context).copyWith(
              colorScheme:
                  const ColorScheme.light(primary: AppColors.primaryPurple)),
          child: child!),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _salvarCliente() async {
    if (!_formKey.currentState!.validate()) return;

    // Validar e Extrair Telefone Clean
    String rawPhone = phoneMask.getUnmaskedText();
    if (rawPhone.isEmpty) {
      rawPhone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    }
    if (rawPhone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "O telefone deve ter formato de celular (11) ou fixo (10) dígitos."),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      String? docId = widget.user?.uid;

      // --- LÃ“GICA DO VÍNCULO (LOJAS VINCULADAS) ---
      String? currentShopId;
      if (widget.isBusinessAdding) {
        currentShopId = await SessionService.getShopId();
      }

      // --- LÃ“GICA DE UPLOAD DE FOTO ---
      String? uploadedFotoUrl;
      if (_imageFile != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('profile_photos')
            .child('${docId ?? DateTime.now().millisecondsSinceEpoch}.jpg');

        final uploadTask = await storageRef.putFile(_imageFile!);
        uploadedFotoUrl = await uploadTask.ref.getDownloadURL();
      }

      Map<String, dynamic> clientData = {
        'nome': _nameController.text.trim(),
        'nome_normalizado': _nameController.text
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[áàãâä]'), 'a')
            .replaceAll(RegExp(r'[éèêë]'), 'e')
            .replaceAll(RegExp(r'[íìîï]'), 'i')
            .replaceAll(RegExp(r'[óòõôö]'), 'o')
            .replaceAll(RegExp(r'[úùûü]'), 'u')
            .replaceAll(RegExp(r'[ç]'), 'c'),
        'telefone': rawPhone,
        'tipo': 'cliente',
        'aniversario': _birthDate != null
            ? DateFormat('dd/MM/yyyy').format(_birthDate!)
            : null,
        'endereco': {
          'cep': _cepController.text,
          'rua': _addressController.text,
          'numero': _numberController.text,
          'bairro': _districtController.text,
          'cidade': _cityController.text,
        },
        'criado_em': FieldValue.serverTimestamp(),
      };

      if (uploadedFotoUrl != null) {
        clientData['foto'] = uploadedFotoUrl;
      }

      // VINCULA O CLIENTE Ã€ LOJA ATUAL
      if (currentShopId != null) {
        clientData['lojasVinculadas'] = FieldValue.arrayUnion([currentShopId]);
      } else {
        clientData['lojasVinculadas'] = []; // Cliente novo sem vínculo
      }

      if (widget.user != null) {
        // Auto-cadastro / Edição de perfil
        clientData['uid'] = widget.user!.uid;
        clientData['email'] = widget.user!.email;
        // Se já tinha foto do Google e não subiu uma nova, mantém a do Google se 'foto' estiver vazio
        if (clientData['foto'] == null && uploadedFotoUrl == null) {
          clientData['foto'] = widget.user!.photoURL;
        }
        clientData['ultimo_login'] = FieldValue.serverTimestamp();

        await FirebaseFirestore.instance
            .collection('users')
            .doc(docId)
            .set(clientData, SetOptions(merge: true));
      } else {
        // Dono cadastrando cliente manualmente
        await FirebaseFirestore.instance.collection('users').add(clientData);
      }

      if (mounted) {
        if (widget.isBusinessAdding) {
          Navigator.pop(context);
        } else if (widget.returnOnSuccess) {
          Navigator.pop(context, true);
        } else {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const ClientHomePage()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text(
            widget.isBusinessAdding ? "Novo Cliente" : "Complete seu Cadastro"),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: widget.isBusinessAdding,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              24, 24, 24, 100), // Substantial bottom padding
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- SEÇÃO DE FOTO ATUALIZADA ---
                Center(
                  child: GestureDetector(
                    onTap: _pickImage, // Permitido para todos
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[200],
                          // Prioridade: 1. Foto selecionada (File) | 2. Foto existente no Doc / Google | 3. Nulo
                          backgroundImage: _imageFile != null
                              ? FileImage(_imageFile!)
                              : (widget.user?.photoURL != null
                                  ? NetworkImage(widget.user!.photoURL!)
                                  : null) as ImageProvider?,
                          child: (_imageFile == null &&
                                  widget.user?.photoURL == null)
                              ? const Icon(Icons.person,
                                  size: 50, color: Colors.grey)
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                                color: AppColors.primaryPurple,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                TextFormField(
                    controller: _nameController,
                    decoration: _deco("Nome Completo", Icons.person),
                    validator: (v) => v!.isEmpty ? "Obrigatório" : null),
                const SizedBox(height: 16),

                TextFormField(
                    controller: _phoneController,
                    inputFormatters: [phoneMask],
                    keyboardType: TextInputType.phone,
                    decoration: _deco("WhatsApp ou Fixo", Icons.phone),
                    onChanged: (val) {
                      String unmasked = phoneMask.getUnmaskedText();
                      if (unmasked.length <= 10 &&
                          phoneMask.getMask() != '(##) ####-####') {
                        setState(() {
                          phoneMask.updateMask(mask: '(##) ####-####');
                        });
                      } else if (unmasked.length > 10 &&
                          phoneMask.getMask() != '(##) #####-####') {
                        setState(() {
                          phoneMask.updateMask(mask: '(##) #####-####');
                        });
                      }
                    },
                    validator: (v) {
                      String unmasked = phoneMask.getUnmaskedText();
                      if (unmasked.isEmpty) {
                        unmasked = v!.replaceAll(RegExp(r'\D'), '');
                      }
                      return unmasked.length < 10
                          ? "Telefone incompleto"
                          : null;
                    }),
                const SizedBox(height: 16),

                InkWell(
                  onTap: _pickDate,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.cake, color: Colors.grey),
                        const SizedBox(width: 12),
                        Text(_birthDate == null
                            ? "Data de Nascimento"
                            : DateFormat('dd/MM/yyyy').format(_birthDate!)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),
                const Divider(),
                const Text("Endereço (Opcional)",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                TextFormField(
                    controller: _cepController,
                    inputFormatters: [cepMask],
                    keyboardType: TextInputType.number,
                    decoration: _deco("CEP", Icons.map,
                        suffix: _isLoadingCep
                            ? const CircularProgressIndicator()
                            : null),
                    onChanged: (v) {
                      if (v.length == 9) _buscarCep(v);
                    }),
                const SizedBox(height: 10),
                TextFormField(
                    controller: _addressController,
                    decoration: _deco("Rua", Icons.home)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextFormField(
                          controller: _numberController,
                          focusNode: _numberFocus,
                          decoration: _deco("Número", Icons.tag))),
                  const SizedBox(width: 10),
                  Expanded(
                      flex: 2,
                      child: TextFormField(
                          controller: _districtController,
                          decoration: _deco("Bairro", Icons.location_city))),
                ]),

                const SizedBox(height: 30),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _salvarCliente,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryPurple,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("SALVAR",
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _deco(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: Colors.grey),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      suffixIcon: suffix,
    );
  }
}
