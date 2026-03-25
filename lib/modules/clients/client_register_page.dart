// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' if (dart.library.html) 'package:flutter_application_1/core/utils/io_stub.dart' as io;
import '../../core/theme/app_colors.dart';
import '../../core/services/viacep_service.dart';
import '../../core/services/session_service.dart';
import 'client_home_page.dart';
import '../../core/services/image_service.dart';

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
  XFile? _imageFile;
  bool _isLoadingCep = false;
  bool _isSaving = false;
  double _uploadProgress = 0.0;

  var phoneMask = MaskTextInputFormatter(
      mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});
  final cepMask = MaskTextInputFormatter(
      mask: '#####-###', filter: {"#": RegExp(r'[0-9]')});
  final FocusNode _numberFocus = FocusNode();

  bool _isBirthdayLocked = false;

  @override
  void initState() {
    super.initState();
    if (widget.user != null) {
      _preencherDadosGoogle();
      _verificarTelefoneExistente();
      _loadExistingUserData();
      _checkBirthdayLock();
    } else {
      _checkCurrentSession();
    }
  }

  Future<void> _checkCurrentSession() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      _loadExistingUserData();
      _checkBirthdayLock();
    }
  }

  Future<void> _checkBirthdayLock() async {
    final uid = widget.user?.id ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final userDoc = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (userDoc != null) {
        if (userDoc['birthday_locked'] == true) {
          setState(() => _isBirthdayLocked = true);
          return;
        }
      }

      final appointments = await Supabase.instance.client
          .from('appointments')
          .select()
          .eq('client_id', uid)
          .eq('birthday_discount_applied', true)
          .limit(1);

      if (appointments.isNotEmpty) {
        setState(() => _isBirthdayLocked = true);
      }
    } catch (e) {
      debugPrint('Erro ao verificar trava de aniversário: $e');
    }
  }

  Future<void> _loadExistingUserData() async {
    final uid = widget.user?.id ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final doc = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (doc != null) {
        if (mounted) {
          setState(() {
            _nameController.text = doc['name'] ?? '';
            _phoneController.text = doc['phone'] ?? '';
            _cepController.text = doc['zip_code'] ?? '';
            _addressController.text = doc['street'] ?? doc['address'] ?? '';
            _numberController.text = doc['number'] ?? '';
            _districtController.text = doc['neighborhood'] ?? '';
            _cityController.text = doc['city'] ?? '';
            if (doc['birth_date'] != null) {
              _birthDate = DateTime.tryParse(doc['birth_date']);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados existentes: $e');
    }
  }

  void _preencherDadosGoogle() {
    if (widget.user != null) {
      _nameController.text = widget.user!.userMetadata?['full_name'] ?? '';
    }
  }

  Future<void> _verificarTelefoneExistente() async {
    final uid = widget.user?.id ?? Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final res = await Supabase.instance.client
          .from('users')
          .select('phone')
          .eq('id', uid)
          .maybeSingle();
      if (res != null && res['phone'] != null) {
        if (mounted) {
          setState(() {
            _phoneController.text = res['phone'];
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao verificar telefone: $e');
    }
  }

  Future<void> _pickImage() async {
    final pickedFile =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = pickedFile;
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
    if (_isBirthdayLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("A data de nascimento não pode mais ser alterada após o uso do desconto de aniversário."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(1995),
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
      final uid = widget.user?.id ?? Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) throw Exception("Usuário não autenticado");

      String? imageUrl;
      if (_imageFile != null) {
        setState(() => _uploadProgress = 0.1);
        imageUrl = await ImageService.uploadProfilePhoto(
          _imageFile!, 
          uid,
          onProgress: (p) => setState(() => _uploadProgress = p),
        );
      }

      String cidade = _cityController.text.trim();
      String estado = '';
      if (cidade.contains(" - ")) {
        final parts = cidade.split(" - ");
        cidade = parts[0].trim();
        if (parts.length > 1) estado = parts[1].trim();
      }

      final userData = {
        'id': uid,
        'name': _nameController.text.trim(),
        'email': widget.user?.email ?? Supabase.instance.client.auth.currentUser?.email,
        'phone': rawPhone,
        'zip_code': _cepController.text.trim(),
        'street': _addressController.text.trim(),
        'number': _numberController.text.trim(),
        'neighborhood': _districtController.text.trim(),
        'city': cidade,
        'state': estado,
        'birth_date': _birthDate?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'role': 'cliente',
      };

      if (imageUrl != null) {
        userData['photo_url'] = imageUrl;
      } else if (widget.user?.userMetadata?['avatar_url'] != null) {
        userData['photo_url'] = widget.user!.userMetadata!['avatar_url'];
      }

      await Supabase.instance.client.from('users').upsert(userData);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cadastro atualizado com sucesso!"),
            backgroundColor: Colors.green,
          ),
        );
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
    String? existingPhoto = widget.user?.userMetadata?['avatar_url'];

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
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: _imageFile != null
                              ? (kIsWeb
                                  ? NetworkImage(_imageFile!.path) as ImageProvider
                                  : FileImage(io.File(_imageFile!.path) as dynamic) as ImageProvider)
                              : (existingPhoto != null
                                  ? NetworkImage(existingPhoto) as ImageProvider
                                  : null),
                          child: (_imageFile == null && existingPhoto == null)
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
                if (_uploadProgress > 0 && _uploadProgress < 1.0) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: _uploadProgress,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryPurple),
                  ),
                  const SizedBox(height: 8),
                  Center(child: Text("${(_uploadProgress * 100).toInt()}% enviando foto...")),
                ],
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
                      // Padrão brasileiro: celulares novos começam com 9
                      // Se tem pelo menos 3 dígitos e o terceiro é 9, é celular
                      bool isMobile = unmasked.length >= 3 && unmasked[2] == '9';
                      String correctMask = isMobile ? '(##) #####-####' : '(##) ####-####';
                      
                      if (phoneMask.getMask() != correctMask) {
                        setState(() {
                          phoneMask.updateMask(mask: correctMask);
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
