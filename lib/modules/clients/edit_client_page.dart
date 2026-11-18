import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import 'package:markaai/core/services/viacep_service.dart';

class EditClientPage extends StatefulWidget {
  final Map<String, dynamic> clientData;
  final String clientId;

  const EditClientPage({
    super.key,
    required this.clientData,
    required this.clientId,
  });

  @override
  State<EditClientPage> createState() => _EditClientPageState();
}

class _EditClientPageState extends State<EditClientPage> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = false;
  bool _isLoadingData = true;
  bool _isSearchingCep = false;
  bool _isLoadingMap = false;

  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _cpfController;
  late TextEditingController _birthDateController;
  late TextEditingController _cepController;
  late TextEditingController _streetController;
  late TextEditingController _numberController;
  late TextEditingController _neighborhoodController;
  late TextEditingController _cityController;
  late TextEditingController _stateController;

  // Máscaras
  late MaskTextInputFormatter _phoneMask;
  final _cpfMask = MaskTextInputFormatter(
      mask: '###.###.###-##', filter: {"#": RegExp(r'[0-9]')});
  final _cepMask = MaskTextInputFormatter(
      mask: '#####-###', filter: {"#": RegExp(r'[0-9]')});
  final _dateMask = MaskTextInputFormatter(
      mask: '##/##/####', filter: {"#": RegExp(r'[0-9]')});

  // Mapa
  double? _latitude;
  double? _longitude;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();

    // Telefone inicial a partir do que foi passado
    String initialPhone =
        (widget.clientData['telefone'] ?? widget.clientData['phone'] ?? '')
            .toString();
    if (initialPhone == 'Não informado' || initialPhone == 'null') {
      initialPhone = '';
    }
    initialPhone = initialPhone.replaceAll(RegExp(r'\D'), '');

    _phoneMask = MaskTextInputFormatter(
      mask: initialPhone.length > 10 ? '(##) #####-####' : '(##) ####-####',
      filter: {"#": RegExp(r'[0-9]')},
      initialText: initialPhone,
    );

    // Inicializa todos os controllers (banco preencherá o resto)
    _nameController = TextEditingController(
        text: widget.clientData['nome'] ?? widget.clientData['name'] ?? '');
    _phoneController =
        TextEditingController(text: _phoneMask.maskText(initialPhone));
    _cpfController = TextEditingController();
    _birthDateController = TextEditingController();
    _cepController = TextEditingController();
    _streetController = TextEditingController();
    _numberController = TextEditingController();
    _neighborhoodController = TextEditingController();
    _cityController = TextEditingController();
    _stateController = TextEditingController();

    // Busca todos os dados do perfil no banco
    _loadClientFromDatabase();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _cpfController.dispose();
    _birthDateController.dispose();
    _cepController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    super.dispose();
  }

  /// Busca os dados completos do cliente diretamente no banco de dados.
  /// Usa o ID (UUID) como prioridade; se não existir, tenta pelo telefone.
  Future<void> _loadClientFromDatabase() async {
    try {
      Map<String, dynamic>? data;

      final uuidRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        caseSensitive: false,
      );

      final isUuid = uuidRegex.hasMatch(widget.clientId);

      // 1. Tenta por UUID
      if (isUuid) {
        data = await _supabase
            .from('users')
            .select()
            .eq('id', widget.clientId)
            .maybeSingle();
        debugPrint('[EditClient] Busca por UUID: ${data != null ? "encontrado" : "não encontrado"}');
      }

      // 2. Fallback por telefone
      // Para clientes manuais, o clientId É o telefone (ex: "11999998888")
      // Também tenta o campo telefone do clientData como garantia
      if (data == null) {
        // Coleta os possíveis telefones para busca
        final candidates = <String>{};

        // Se clientId não é UUID, pode ser o próprio telefone
        if (!isUuid) {
          final cleaned = widget.clientId.replaceAll(RegExp(r'\D'), '');
          if (cleaned.isNotEmpty) candidates.add(cleaned);
        }

        // Também tenta o campo telefone passado no clientData
        final phoneField = widget.clientData['telefone'] ?? widget.clientData['phone'];
        if (phoneField != null && phoneField.toString().isNotEmpty) {
          final cleaned = phoneField.toString().replaceAll(RegExp(r'\D'), '');
          if (cleaned.isNotEmpty) candidates.add(cleaned);
        }

        debugPrint('[EditClient] Buscando por telefones: $candidates');

        for (final phone in candidates) {
          data = await _supabase
              .from('users')
              .select()
              .eq('phone', phone)
              .maybeSingle();
          if (data != null) {
            debugPrint('[EditClient] Encontrado pelo telefone: $phone');
            break;
          }
        }
      }

      if (!mounted) return;

      if (data != null) {
        // Formata data de nascimento
        String birthStr = '';
        final birthRaw = data['birth_date'];
        if (birthRaw != null && birthRaw.toString().isNotEmpty) {
          try {
            final dt = DateTime.parse(birthRaw.toString());
            birthStr = DateFormat('dd/MM/yyyy').format(dt);
          } catch (_) {}
        }

        // CPF só os dígitos
        final cpfRaw =
            (data['cpf'] ?? '').toString().replaceAll(RegExp(r'\D'), '');

        debugPrint('[EditClient] Dados carregados: name=${data["name"]}, cpf=$cpfRaw, city=${data["city"]}');

        setState(() {
          // Prioriza always o nome do banco (pode ter sido atualizado pelo usuário)
          if ((data!['name']?.toString() ?? '').isNotEmpty) {
            _nameController.text = data['name'];
          }
          _cpfController.text = cpfRaw.isNotEmpty ? _cpfMask.maskText(cpfRaw) : '';
          _birthDateController.text = birthStr;
          _cepController.text = data['zip_code']?.toString() ?? '';
          _streetController.text = data['street']?.toString() ?? '';
          _numberController.text = data['number']?.toString() ?? '';
          _neighborhoodController.text =
              data['neighborhood']?.toString() ?? '';
          _cityController.text = data['city']?.toString() ?? '';
          _stateController.text = data['state']?.toString() ?? '';
          _isLoadingData = false;
        });

        if (_streetController.text.isNotEmpty &&
            _cityController.text.isNotEmpty) {
          _updateMap();
        }
      } else {
        debugPrint('[EditClient] Nenhum dado encontrado para clientId=${widget.clientId}');
        setState(() => _isLoadingData = false);
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados do cliente: $e');
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  void _onAddressChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), _updateMap);
  }

      Future<Map<String, double>?> _nominatimGeocode(String address) async {
        try {
          final url = Uri.parse(
            'https://nominatim.openstreetmap.org/search'
            '?q=${Uri.encodeComponent(address)}'
            '&format=json&limit=1',
          );
          final resp = await http.get(url, headers: {
            'User-Agent': 'MarkaAI/1.0 (suporte@markaai.com.br)',
          });
          if (resp.statusCode == 200) {
            final List results = jsonDecode(resp.body);
            if (results.isNotEmpty) {
              return {
                'lat': double.parse(results[0]['lat'].toString()),
                'lon': double.parse(results[0]['lon'].toString()),
              };
            }
          }
        } catch (_) {}
        return null;
      }

      Future<void> _updateMap() async {
        if (_streetController.text.isEmpty || _cityController.text.isEmpty) return;
        setState(() => _isLoadingMap = true);
        try {
          final address =
              '${_streetController.text}, ${_numberController.text}, ${_cityController.text} - ${_stateController.text}, Brasil';
          final loc = await _nominatimGeocode(address);
          if (loc != null && mounted) {
            setState(() {
              _latitude = loc['lat'];
              _longitude = loc['lon'];
            });
          } else {
            final fallback =
                '${_streetController.text}, ${_cityController.text} - ${_stateController.text}, Brasil';
            final loc2 = await _nominatimGeocode(fallback);
            if (loc2 != null && mounted) {
              setState(() {
                _latitude = loc2['lat'];
                _longitude = loc2['lon'];
              });
            }
          }
        } catch (_) {}
        finally {
          if (mounted) setState(() => _isLoadingMap = false);
        }
      }

  Future<void> _buscarCep(String cep) async {
    if (cep.length != 9) return;
    setState(() => _isSearchingCep = true);
    try {
      final res = await ViaCepService.buscarCep(cep);
      if (res != null && mounted) {
        setState(() {
          _streetController.text = res['logradouro'] ?? '';
          _neighborhoodController.text = res['bairro'] ?? '';
          _cityController.text = res['localidade'] ?? '';
          _stateController.text = res['uf'] ?? '';
        });
        _updateMap();
      }
    } catch (e) {
      debugPrint('Erro ao buscar CEP: $e');
    } finally {
      if (mounted) setState(() => _isSearchingCep = false);
    }
  }

  Future<void> _save() async {
    if (_phoneController.text.length < 14) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "O telefone deve ter no mínimo 14 caracteres (incluindo DDD)."),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      DateTime? parsedBirth;
      if (_birthDateController.text.length == 10) {
        try {
          final parts = _birthDateController.text.split('/');
          parsedBirth = DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          );
        } catch (_) {}
      }

      final updateData = {
        'name': _nameController.text.trim(),
        'phone': _phoneMask.getUnmaskedText(),
        'cpf': _cpfMask.getUnmaskedText(),
        'birth_date': parsedBirth?.toIso8601String(),
        'zip_code': _cepMask.getUnmaskedText(),
        'street': _streetController.text.trim(),
        'number': _numberController.text.trim(),
        'neighborhood': _neighborhoodController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim().toUpperCase(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _supabase
          .from('users')
          .update(updateData)
          .eq('id', widget.clientId);

      // Sincroniza o telefone atualizado nos agendamentos vinculados ao cliente
      try {
        await _supabase
            .from('appointments')
            .update({'client_phone': updateData['phone']})
            .eq('client_id', widget.clientId);
      } catch (e) {
        debugPrint('Erro ao sincronizar telefone nos agendamentos: $e');
      }

      final shopId = widget.clientData['shop_id'];
      if (shopId != null) {
        final existing = await _supabase
            .from('shop_clients')
            .select('id')
            .eq('shop_id', shopId)
            .eq('user_id', widget.clientId)
            .maybeSingle();

        final dataToSave = {
          'shop_id': shopId,
          'user_id': widget.clientId,
          'nome': updateData['name'],
          'telefone': updateData['phone'],
          'last_updated': DateTime.now().toIso8601String(),
        };

        if (existing != null) {
          await _supabase
              .from('shop_clients')
              .update(dataToSave)
              .eq('id', existing['id']);
        } else {
          await _supabase.from('shop_clients').insert(dataToSave);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cadastro atualizado com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, updateData);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        title: const Text('Editar Cadastro',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isLoadingData)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
              ),
            )
          else if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('SALVAR',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: _isLoadingData
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Carregando dados do cliente...',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _buildSection(
                    title: 'Dados Pessoais',
                    icon: Icons.person_outline,
                    children: [
                      _buildTextField(
                        _nameController,
                        'Nome Completo',
                        Icons.person_outline,
                        capitalize: true,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        _phoneController,
                        'WhatsApp',
                        Icons.phone_iphone_rounded,
                        keyboard: TextInputType.phone,
                        formatters: [_phoneMask],
                        onChanged: (v) {
                          final unmasked = _phoneMask.getUnmaskedText();
                          if (unmasked.length <= 10 &&
                              _phoneMask.getMask() != '(##) ####-####') {
                            setState(() => _phoneMask.updateMask(
                                mask: '(##) ####-####'));
                          } else if (unmasked.length > 10 &&
                              _phoneMask.getMask() != '(##) #####-####') {
                            setState(() => _phoneMask.updateMask(
                                mask: '(##) #####-####'));
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              _cpfController,
                              'CPF',
                              Icons.assignment_ind_outlined,
                              keyboard: TextInputType.number,
                              formatters: [_cpfMask],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              _birthDateController,
                              'Nascimento',
                              Icons.cake_outlined,
                              keyboard: TextInputType.datetime,
                              formatters: [_dateMask],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSection(
                    title: 'Endereço',
                    icon: Icons.location_on_outlined,
                    children: [
                      _buildTextField(
                        _cepController,
                        'CEP',
                        Icons.map_outlined,
                        keyboard: TextInputType.number,
                        formatters: [_cepMask],
                        onChanged: _buscarCep,
                        suffix: _isSearchingCep
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : null,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        _streetController,
                        'Rua/Logradouro',
                        Icons.home_outlined,
                        onChanged: (_) => _onAddressChanged(),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              _numberController,
                              'Número',
                              Icons.tag_rounded,
                              onChanged: (_) => _onAddressChanged(),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: _buildTextField(
                              _neighborhoodController,
                              'Bairro',
                              Icons.location_city_outlined,
                              onChanged: (_) => _onAddressChanged(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildTextField(
                              _cityController,
                              'Cidade',
                              Icons.apartment_rounded,
                              onChanged: (_) => _onAddressChanged(),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              _stateController,
                              'UF',
                              Icons.flag_outlined,
                              capitalize: true,
                              onChanged: (_) => _onAddressChanged(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildMapSection(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primaryPurple),
              const SizedBox(width: 12),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? formatters,
    void Function(String)? onChanged,
    Widget? suffix,
    bool capitalize = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      inputFormatters: formatters,
      onChanged: onChanged,
      textCapitalization:
          capitalize ? TextCapitalization.words : TextCapitalization.none,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF5F7FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildMapSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              children: [
                Icon(Icons.map_outlined,
                    size: 20, color: AppColors.primaryPurple),
                SizedBox(width: 12),
                Text('Localização',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          if (_latitude != null && _longitude != null) ...[
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(20)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  children: [
                    CachedNetworkImage(
                      imageUrl:
                          'https://static-maps.yandex.ru/1.x/?ll=$_longitude,$_latitude&z=17&l=map&size=600,350',
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Colors.grey[100],
                        child: const Center(
                            child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) => Container(
                        color: Colors.grey[100],
                        child: const Center(
                          child: Icon(Icons.error_outline,
                              color: Colors.orange),
                        ),
                      ),
                    ),
                    const Center(
                      child: Icon(Icons.location_on,
                          color: Colors.red, size: 40),
                    ),
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'open_gps',
                        onPressed: _openInGps,
                        backgroundColor: AppColors.primaryPurple,
                        child: const Icon(Icons.navigation_outlined,
                            color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else if (_isLoadingMap)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.location_off_outlined,
                        size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('Preencha o endereço para ver o mapa',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openInGps() async {
    if (_latitude == null || _longitude == null) return;
    final url =
        'https://www.google.com/maps/search/?api=1&query=$_latitude,$_longitude';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }
}
