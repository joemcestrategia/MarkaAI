// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' if (dart.library.html) 'package:markaai/core/utils/io_stub.dart' as io;
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/theme/app_colors.dart';
import 'package:markaai/core/services/viacep_service.dart';
import 'package:markaai/core/utils/string_utils.dart';
import 'client_home_page.dart';
import '../../core/services/image_service.dart';

class ClientRegisterPage extends StatefulWidget {
  final User? user;
  final bool isBusinessAdding;
  final bool returnOnSuccess;
  final VoidCallback? onSuccess;

  /// ID (shop_clients.id) de um cliente cadastrado MANUALMENTE pelo lojista.
  /// Quando informado, a tela entra em modo de EDIÇÃO desse cadastro manual.
  /// Clientes que criaram a própria conta nunca devem ser editados por aqui.
  final String? manualClientId;

  const ClientRegisterPage(
      {super.key,
      this.user,
      this.isBusinessAdding = false,
      this.returnOnSuccess = false,
      this.onSuccess,
      this.manualClientId});

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
  final _cpfController = TextEditingController();

  DateTime? _birthDate;
  XFile? _imageFile;
  bool _isLoadingCep = false;
  bool _isSaving = false;
  double _uploadProgress = 0.0;
  String? _existingRole;

  var phoneMask = MaskTextInputFormatter(
      mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});
  final cepMask = MaskTextInputFormatter(
      mask: '#####-###', filter: {"#": RegExp(r'[0-9]')});
  final cpfMask = MaskTextInputFormatter(
      mask: '###.###.###-##', filter: {"#": RegExp(r'[0-9]')});
  final FocusNode _numberFocus = FocusNode();

  bool _isBirthdayLocked = false;

  // ── Modo edição de cliente manual ───────────────────────────────────────
  bool get _isEditingManual => widget.manualClientId != null;
  bool _loadingManual = false;
  String? _existingPhotoUrl;
  String? _manualOriginalName;
  String _manualOriginalPhone = '';
  String _manualOriginalCpf = '';

  @override
  void initState() {
    super.initState();
    if (_isEditingManual) {
      _loadManualClient();
    } else if (widget.user != null) {
      _preencherDadosGoogle();
      _verificarTelefoneExistente();
      _loadExistingUserData();
      _checkBirthdayLock();
    } else if (!widget.isBusinessAdding) {
      // Não carrega dados do usuário logado quando a loja está adicionando um cliente
      _checkCurrentSession();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _cepController.dispose();
    _addressController.dispose();
    _numberController.dispose();
    _districtController.dispose();
    _cityController.dispose();
    _cpfController.dispose();
    super.dispose();
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
            _existingRole = doc['role'];
            _nameController.text = doc['name'] ?? '';
            final rawPhone = (doc['phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
            if (rawPhone.length > 10) {
              phoneMask.updateMask(mask: '(##) #####-####');
            } else {
              phoneMask.updateMask(mask: '(##) ####-####');
            }
            _phoneController.text = phoneMask.maskText(rawPhone);
            _cepController.text = doc['zip_code'] ?? '';
            _addressController.text = doc['street'] ?? doc['address'] ?? '';
            _numberController.text = doc['number'] ?? '';
            _districtController.text = doc['neighborhood'] ?? '';
            _cityController.text = doc['city'] ?? '';
            final rawCpf = (doc['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
            _cpfController.text = rawCpf.isNotEmpty ? cpfMask.maskText(rawCpf) : '';
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

  /// Carrega o cadastro manual (shop_clients) para edição.
  /// A consulta exige is_manual_client = true e user_id nulo: se o cliente
  /// tiver criado a própria conta, o cadastro NÃO é carregado nem editável.
  Future<void> _loadManualClient() async {
    setState(() => _loadingManual = true);
    try {
      final doc = await Supabase.instance.client
          .from('shop_clients')
          .select()
          .eq('id', widget.manualClientId!)
          .eq('is_manual_client', true)
          .isFilter('user_id', null)
          .maybeSingle();

      if (!mounted) return;

      if (doc == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este cadastro não pode ser editado pelo lojista.'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context, false);
        return;
      }

      final rawPhone = (doc['telefone'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      final rawCpf = (doc['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      final city = (doc['city'] ?? '').toString();
      final state = (doc['state'] ?? '').toString();

      setState(() {
        _manualOriginalName = (doc['nome'] ?? '').toString();
        _manualOriginalPhone = rawPhone;
        _manualOriginalCpf = rawCpf;
        _nameController.text = _manualOriginalName!;
        phoneMask.updateMask(
            mask: rawPhone.length > 10 ? '(##) #####-####' : '(##) ####-####');
        _phoneController.text = phoneMask.maskText(rawPhone);
        // Não exibe o CPF completo na tela para o lojista (exibe mascarado no hint)
        _cpfController.clear();
        _birthDate = DateTime.tryParse((doc['birth_date'] ?? '').toString());
        _cepController.text = (doc['zip_code'] ?? '').toString();
        _addressController.text = (doc['street'] ?? '').toString();
        _numberController.text = (doc['number'] ?? '').toString();
        _districtController.text = (doc['neighborhood'] ?? '').toString();
        _cityController.text =
            state.isNotEmpty && city.isNotEmpty ? '$city - $state' : city;
        final photo = (doc['photo_url'] ?? '').toString();
        _existingPhotoUrl = photo.isNotEmpty ? photo : null;
      });
    } catch (e) {
      debugPrint('Erro ao carregar cliente manual para edição: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar cliente: $e'), backgroundColor: Colors.red),
        );
        Navigator.pop(context, false);
      }
    } finally {
      if (mounted) setState(() => _loadingManual = false);
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

  Future<Map<String, double>?> _geocodeAddress(String query) async {
    if (query.isEmpty) return null;
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json&limit=1&accept-language=pt-BR',
      );
      final resp = await http.get(uri, headers: {'User-Agent': 'MarkaAI/1.0'});
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as List;
        if (json.isNotEmpty) {
          final r = json[0] as Map<String, dynamic>;
          final lat = double.tryParse(r['lat']?.toString() ?? '');
          final lon = double.tryParse(r['lon']?.toString() ?? '');
          if (lat != null && lon != null) {
            return {'lat': lat, 'lng': lon};
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _salvarCliente() async {
    if (!_formKey.currentState!.validate()) return;

    String rawPhone = phoneMask.getUnmaskedText();
    if (rawPhone.isEmpty) {
      rawPhone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    }
    if (_phoneController.text.length < 14) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "O telefone deve ter no mínimo 14 caracteres (incluindo DDD)."),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isSaving = true);

    // ── BIFURCAÇÃO: cliente manual (dona da loja) vs. auto-cadastro ──────────
    if (_isEditingManual) {
      await _atualizarClienteManual(rawPhone);
    } else if (widget.isBusinessAdding && widget.user == null) {
      await _salvarClienteManual(rawPhone);
    } else {
      await _salvarClienteAuth(rawPhone);
    }
  }

  // ── FLUXO 1: Dona do salão cadastrando cliente SEM conta Auth ────────────
  // Salva em `shop_clients` com is_manual_client = true.
  // Nunca toca a tabela `users` — evita violação de RLS (code 42501).
  Future<void> _salvarClienteManual(String rawPhone) async {
    try {
      final supabase = Supabase.instance.client;
      final ownerUid = supabase.auth.currentUser?.id;
      if (ownerUid == null) throw Exception("Sessão expirada. Faça login novamente.");

      // 1. Buscar shop_id da dona logada
      final ownerData = await supabase
          .from('users')
          .select('shop_id')
          .eq('id', ownerUid)
          .single();
      final shopId = ownerData['shop_id'] as String?;
      if (shopId == null || shopId.isEmpty) {
        throw Exception("Loja não encontrada para este usuário.");
      }

      // 2. Verificar se o telefone já existe em `users` (cliente tem conta Auth)
      final authUserByPhone = await supabase
          .from('users')
          .select('id, name')
          .eq('phone', rawPhone)
          .limit(1)
          .maybeSingle();

      if (authUserByPhone != null && mounted) {
        final clientName = authUserByPhone['name'] ?? 'Este cliente';
        final bool? proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cliente já cadastrado no app'),
            content: Text(
              '$clientName já possui uma conta no MarkaAI com este número de telefone.\n\n'
              'Você pode aguardar ele fazer um agendamento pelo app, ou cadastrá-lo manualmente agora.\n\nDeseja cadastrar manualmente mesmo assim?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple),
                child: const Text('Adicionar assim mesmo', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if (proceed != true) {
          if (mounted) setState(() => _isSaving = false);
          return;
        }
      }

      // 3. Verificar duplicata na própria shop_clients (mesmo telefone, mesma loja)
      final existingManualList = await supabase
          .from('shop_clients')
          .select('id, nome, notes')
          .eq('shop_id', shopId)
          .eq('telefone', rawPhone)
          .eq('is_manual_client', true)
          .limit(10);
      final Map<String, dynamic>? existingManual = existingManualList
          .cast<Map<String, dynamic>>()
          .where((r) => (r['notes'] ?? '').toString() != '[DELETED_MANUAL]')
          .firstOrNull;

      if (existingManual != null && mounted) {
        final manualName = existingManual['nome'] ?? 'Um cliente';
        final bool? proceedManual = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Telefone já cadastrado por você'),
            content: Text(
              'Você já cadastrou $manualName manualmente com este mesmo número de telefone na sua loja.\n\nDeseja adicionar outro cliente com este mesmo telefone?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple),
                child: const Text('Adicionar assim mesmo', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if (proceedManual != true) {
          if (mounted) setState(() => _isSaving = false);
          return;
        }
      }

      String cidade = _cityController.text.trim();
      String estado = '';
      if (cidade.contains(' - ')) {
        final parts = cidade.split(' - ');
        cidade = parts[0].trim();
        if (parts.length > 1) estado = parts[1].trim();
      }

      // 4. Geocodificar endereço (opcional, não bloqueia o fluxo)
      double? lat, lng;
      try {
        final parts = <String>[];
        final street = _addressController.text.trim();
        final number = _numberController.text.trim();
        final neighborhood = _districtController.text.trim();
        final zipCode = _cepController.text.trim();
        if (street.isNotEmpty && number.isNotEmpty) {
          parts.add('$street, $number');
        } else if (street.isNotEmpty) {
          parts.add(street);
        }
        if (neighborhood.isNotEmpty) parts.add(neighborhood);
        if (cidade.isNotEmpty) parts.add(cidade);
        if (estado.isNotEmpty) parts.add(estado);
        if (parts.isEmpty && zipCode.isNotEmpty) parts.add(zipCode);
        parts.add('Brasil');
        final geo = await _geocodeAddress(parts.join(', '));
        if (geo != null) {
          lat = geo['lat'];
          lng = geo['lng'];
        }
      } catch (e) {
        debugPrint('Geocode falhou no cadastro manual: $e');
      }

      // 5. Montar payload para shop_clients
      final manualData = <String, dynamic>{
        'shop_id': shopId,
        'user_id': null,            // sem conta Auth — nunca confundir com users
        'is_manual_client': true,
        'has_auth_account': authUserByPhone != null,
        'nome': _nameController.text.trim(),
        'telefone': rawPhone,
        'email': null,              // formulário não tem campo de email manual
        'cpf': _cpfController.text.replaceAll(RegExp(r'\D'), '').isNotEmpty
            ? _cpfController.text.replaceAll(RegExp(r'\D'), '')
            : null,
        'birth_date': _birthDate != null
            ? '${_birthDate!.year.toString().padLeft(4, '0')}-'
              '${_birthDate!.month.toString().padLeft(2, '0')}-'
              '${_birthDate!.day.toString().padLeft(2, '0')}'
            : null,
        'zip_code': _cepController.text.trim().isNotEmpty ? _cepController.text.trim() : null,
        'street': _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
        'number': _numberController.text.trim().isNotEmpty ? _numberController.text.trim() : null,
        'neighborhood': _districtController.text.trim().isNotEmpty ? _districtController.text.trim() : null,
        'city': cidade.isNotEmpty ? cidade : null,
        'state': estado.isNotEmpty ? estado : null,
        'lat': lat,
        'lng': lng,
        'last_updated': DateTime.now().toIso8601String(),
      };

      // 6. Upload de foto (se escolhida) — usa chave única de storage
      if (_imageFile != null) {
        setState(() => _uploadProgress = 0.1);
        final photoKey = 'manual_${shopId}_${DateTime.now().millisecondsSinceEpoch}';
        try {
          final imageUrl = await ImageService.uploadProfilePhoto(
            _imageFile!,
            photoKey,
            onProgress: (p) => setState(() => _uploadProgress = p),
          );
          manualData['photo_url'] = imageUrl;
        } catch (e) {
          debugPrint('Erro ao fazer upload da foto do cliente manual: $e');
        }
      }

      // 7. Upsert em shop_clients
      //    - Se já existe registro (mesma loja + telefone): atualiza
      //    - Se não existe: insere
      if (existingManual != null) {
        await supabase
            .from('shop_clients')
            .update(manualData)
            .eq('id', existingManual['id']);
      } else {
        await supabase.from('shop_clients').insert(manualData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cliente cadastrado com sucesso!"),
            backgroundColor: Colors.green,
          ),
        );
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        } else {
          Navigator.pop(context);
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

  // ── FLUXO 1b: Dona do salão EDITANDO um cliente que ela mesma cadastrou ──
  // Só atualiza linhas de `shop_clients` com is_manual_client = true e
  // user_id nulo. Clientes que criaram a própria conta nunca passam por aqui.
  Future<void> _atualizarClienteManual(String rawPhone) async {
    try {
      final supabase = Supabase.instance.client;
      final manualId = widget.manualClientId!;

      String cidade = _cityController.text.trim();
      String estado = '';
      if (cidade.contains(' - ')) {
        final parts = cidade.split(' - ');
        cidade = parts[0].trim();
        if (parts.length > 1) estado = parts[1].trim();
      }

      final newName = _nameController.text.trim();
      final cpfDigits = _cpfController.text.replaceAll(RegExp(r'\D'), '');
      final effectiveCpf =
          cpfDigits.isNotEmpty ? cpfDigits : (_manualOriginalCpf.isNotEmpty ? _manualOriginalCpf : null);

      final payload = <String, dynamic>{
        'nome': newName,
        'telefone': rawPhone,
        'cpf': effectiveCpf,
        'birth_date': _birthDate != null
            ? '${_birthDate!.year.toString().padLeft(4, '0')}-'
              '${_birthDate!.month.toString().padLeft(2, '0')}-'
              '${_birthDate!.day.toString().padLeft(2, '0')}'
            : null,
        'zip_code': _cepController.text.trim().isNotEmpty ? _cepController.text.trim() : null,
        'street': _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
        'number': _numberController.text.trim().isNotEmpty ? _numberController.text.trim() : null,
        'neighborhood': _districtController.text.trim().isNotEmpty ? _districtController.text.trim() : null,
        'city': cidade.isNotEmpty ? cidade : null,
        'state': estado.isNotEmpty ? estado : null,
        'last_updated': DateTime.now().toIso8601String(),
      };

      // Geocodificar endereço (opcional, não bloqueia o fluxo)
      try {
        final parts = <String>[];
        final street = _addressController.text.trim();
        final number = _numberController.text.trim();
        final neighborhood = _districtController.text.trim();
        final zipCode = _cepController.text.trim();
        if (street.isNotEmpty && number.isNotEmpty) {
          parts.add('$street, $number');
        } else if (street.isNotEmpty) {
          parts.add(street);
        }
        if (neighborhood.isNotEmpty) parts.add(neighborhood);
        if (cidade.isNotEmpty) parts.add(cidade);
        if (estado.isNotEmpty) parts.add(estado);
        if (parts.isEmpty && zipCode.isNotEmpty) parts.add(zipCode);
        if (parts.isNotEmpty) {
          parts.add('Brasil');
          final geo = await _geocodeAddress(parts.join(', '));
          if (geo != null) {
            payload['lat'] = geo['lat'];
            payload['lng'] = geo['lng'];
          }
        }
      } catch (e) {
        debugPrint('Geocode falhou na edição de cliente manual: $e');
      }

      // Foto nova (se escolhida)
      if (_imageFile != null) {
        setState(() => _uploadProgress = 0.1);
        final photoKey = 'manual_${manualId}_${DateTime.now().millisecondsSinceEpoch}';
        try {
          final imageUrl = await ImageService.uploadProfilePhoto(
            _imageFile!,
            photoKey,
            onProgress: (p) => setState(() => _uploadProgress = p),
          );
          payload['photo_url'] = imageUrl;
        } catch (e) {
          debugPrint('Erro ao fazer upload da foto do cliente manual: $e');
        }
      }

      // Update protegido: só atinge cadastro manual sem conta Auth.
      final updated = await supabase
          .from('shop_clients')
          .update(payload)
          .eq('id', manualId)
          .eq('is_manual_client', true)
          .isFilter('user_id', null)
          .select('id, shop_id');

      if (updated.isEmpty) {
        throw Exception(
            'Este cliente não pode ser editado (cadastro feito pelo próprio cliente).');
      }

      // Mantém o nome/telefone dos agendamentos antigos deste cliente manual
      // coerentes com o cadastro, para que o histórico continue unificado.
      final shopId = updated.first['shop_id']?.toString();
      final oldName = _manualOriginalName;
      if (shopId != null &&
          oldName != null &&
          oldName.isNotEmpty &&
          (oldName != newName || _manualOriginalPhone != rawPhone)) {
        try {
          final rows = await supabase
              .from('appointments')
              .select('id, client_phone')
              .eq('shop_id', shopId)
              .eq('client_name', oldName)
              .isFilter('client_id', null);
          final ids = rows
              .where((r) =>
                  (r['client_phone'] ?? '').toString().replaceAll(RegExp(r'\D'), '') ==
                  _manualOriginalPhone)
              .map((r) => r['id'])
              .toList();
          if (ids.isNotEmpty) {
            await supabase
                .from('appointments')
                .update({'client_name': newName, 'client_phone': rawPhone})
                .inFilter('id', ids);
          }
        } catch (e) {
          debugPrint('Erro ao sincronizar agendamentos do cliente manual: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cliente atualizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── FLUXO 2: Cliente completando próprio cadastro (ou dona editando cliente com conta) ──
  // Fluxo original — upsert em `users` com o UID do próprio cliente.
  static String _normalizePhoneDigits(String phone) {
    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 12 && digits.startsWith('55')) {
      digits = digits.substring(2);
    }
    while (digits.length > 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  static bool _isCompatibleClientName(String nameA, String nameB) {
    List<String> tokenize(String s) {
      final clean = StringUtils.removeDiacritics(s)
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
          .trim();
      if (clean.isEmpty) return [];
      const stopWords = {'de', 'da', 'do', 'das', 'dos', 'e'};
      return clean
          .split(RegExp(r'\s+'))
          .where((t) => t.isNotEmpty && !stopWords.contains(t))
          .toList();
    }

    final tokensA = tokenize(nameA);
    final tokensB = tokenize(nameB);
    if (tokensA.isEmpty || tokensB.isEmpty) return false;
    if (tokensA.first != tokensB.first) return false;
    if (tokensA.length >= 2 && tokensB.length >= 2) {
      final lastA = tokensA.sublist(1).toSet();
      final lastB = tokensB.sublist(1).toSet();
      return lastA.intersection(lastB).isNotEmpty;
    }
    return true;
  }

  Future<void> _salvarClienteAuth(String rawPhone) async {
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

      final userData = <String, dynamic>{
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
        'cpf': _cpfController.text.replaceAll(RegExp(r'\D'), ''),
        'birth_date': _birthDate?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'role': _existingRole ?? 'cliente',
      };

      try {
        final parts = <String>[];
        final street = _addressController.text.trim();
        final number = _numberController.text.trim();
        final neighborhood = _districtController.text.trim();
        final zipCode = _cepController.text.trim();

        if (street.isNotEmpty && number.isNotEmpty) {
          parts.add('$street, $number');
        } else if (street.isNotEmpty) {
          parts.add(street);
        }
        if (neighborhood.isNotEmpty) parts.add(neighborhood);
        if (cidade.isNotEmpty) parts.add(cidade);
        if (estado.isNotEmpty) parts.add(estado);
        if (parts.isEmpty && zipCode.isNotEmpty) parts.add(zipCode);
        parts.add('Brasil');

        final geo = await _geocodeAddress(parts.join(', '));
        if (geo != null) {
          userData['lat'] = geo['lat'];
          userData['lng'] = geo['lng'];
        }
      } catch (e) {
        debugPrint('Geocode failed during registration: $e');
      }

      if (imageUrl != null) {
        userData['photo_url'] = imageUrl;
      } else if (widget.user?.userMetadata?['avatar_url'] != null) {
        userData['photo_url'] = widget.user!.userMetadata!['avatar_url'];
      }

      await Supabase.instance.client.from('users').upsert(userData);

      // Sincroniza o telefone atualizado nos agendamentos vinculados ao cliente
      try {
        await Supabase.instance.client
            .from('appointments')
            .update({'client_phone': rawPhone})
            .eq('client_id', uid);
      } catch (e) {
        debugPrint('Erro ao sincronizar telefone nos agendamentos: $e');
      }

      // Complementa a trigger do banco: vincula agendamentos órfãos (client_id nulo)
      // com telefone normalizado + nome compatível e sinaliza duplicidade em shop_clients.
      if (!widget.isBusinessAdding) {
        try {
          final normPhone = _normalizePhoneDigits(rawPhone);
          final ownName = _nameController.text.trim();
          if (normPhone.length >= 8 && ownName.isNotEmpty) {
            final phoneCandidates = {rawPhone, normPhone}.toList();
            final orphanApps = await Supabase.instance.client
                .from('appointments')
                .select('id, client_name, client_phone')
                .isFilter('client_id', null)
                .inFilter('client_phone', phoneCandidates)
                .limit(200);
            final idsToLink = orphanApps
                .where((a) =>
                    _normalizePhoneDigits((a['client_phone'] ?? '').toString()) == normPhone &&
                    _isCompatibleClientName(ownName, (a['client_name'] ?? '').toString()))
                .map((a) => a['id'])
                .where((id) => id != null)
                .toList();
            if (idsToLink.isNotEmpty) {
              await Supabase.instance.client
                  .from('appointments')
                  .update({'client_id': uid})
                  .inFilter('id', idsToLink);
            }

            await Supabase.instance.client
                .from('shop_clients')
                .update({
                  'has_auth_account': true,
                  'last_updated': DateTime.now().toIso8601String(),
                })
                .eq('is_manual_client', true)
                .isFilter('user_id', null)
                .inFilter('telefone', phoneCandidates);
          }
        } catch (e) {
          debugPrint('Vínculo complementar pós-cadastro falhou: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cadastro atualizado com sucesso!"),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (mounted) {
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        } else if (widget.isBusinessAdding) {
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
    String? existingPhoto = widget.user?.userMetadata?['avatar_url'] ?? _existingPhotoUrl;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: Text(
            _isEditingManual
                ? "Editar Cliente"
                : (widget.isBusinessAdding ? "Novo Cliente" : "Complete seu Cadastro")),
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
                    validator: (v) {
                      if (v == null || v.isEmpty) return "Obrigatório";
                      if (v.length > 150) return "Máximo 150 caracteres";
                      return null;
                    }),
                const SizedBox(height: 16),

                TextFormField(
                    controller: _phoneController,
                    // Retirado o inputFormatters para não bloquear o 11º dígito
                    keyboardType: TextInputType.phone,
                    decoration: _deco("WhatsApp ou Fixo", Icons.phone),
                    onChanged: (val) {
                      String unmasked = val.replaceAll(RegExp(r'\D'), '');
                      if (unmasked.length > 11) unmasked = unmasked.substring(0, 11);
                      String correctMask = unmasked.length > 10 ? '(##) #####-####' : '(##) ####-####';
                      if (phoneMask.getMask() != correctMask) {
                        phoneMask.updateMask(mask: correctMask);
                        // Atualiza o texto com a nova máscara mantendo o cursor no final
                        _phoneController.value = TextEditingValue(
                          text: phoneMask.maskText(unmasked),
                          selection: TextSelection.collapsed(offset: phoneMask.maskText(unmasked).length),
                        );
                      }
                    },
                    validator: (v) {
                      return v!.length < 14
                          ? "Telefone incompleto. Insira o DDD e o número."
                          : null;
                    }),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _cpfController,
                  inputFormatters: [cpfMask],
                  keyboardType: TextInputType.number,
                  decoration: _deco("CPF", Icons.badge_outlined).copyWith(
                    hintText: (_isEditingManual && _manualOriginalCpf.length == 11)
                        ? '***.${_manualOriginalCpf.substring(3, 6)}.${_manualOriginalCpf.substring(6, 9)}-** (já cadastrado)'
                        : null,
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return null; // Opcional no cadastro, mas valida se preencher
                    final cleanId = v.replaceAll(RegExp(r'\D'), '');
                    if (cleanId.length != 11) return "CPF incompleto";
                    return null;
                  },
                ),
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
                    decoration: _deco("Rua", Icons.home),
                    validator: (v) => v != null && v.length > 200 ? "Máximo 200 caracteres" : null),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextFormField(
                          controller: _numberController,
                          focusNode: _numberFocus,
                          decoration: _deco("Número", Icons.tag),
                          validator: (v) => v != null && v.length > 20 ? "Máximo 20 caracteres" : null)),
                  const SizedBox(width: 10),
                  Expanded(
                      flex: 2,
                      child: TextFormField(
                          controller: _districtController,
                          decoration: _deco("Bairro", Icons.location_city),
                          validator: (v) => v != null && v.length > 150 ? "Máximo 150 caracteres" : null)),
                ]),

                const SizedBox(height: 30),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_isSaving || _loadingManual) ? null : _salvarCliente,
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
