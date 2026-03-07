// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../../core/theme/app_colors.dart';
import '../../core/services/location_service.dart';
import '../clients/address_selector_page.dart';

// Lista fixa das UFs brasileiras
const List<String> _kUFs = [
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

class BusinessProfilePage extends StatefulWidget {
  final String shopId;
  const BusinessProfilePage({super.key, required this.shopId});

  @override
  State<BusinessProfilePage> createState() => _BusinessProfilePageState();
}

class _BusinessProfilePageState extends State<BusinessProfilePage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isUploading = false;
  bool _isLoadingCep = false;

  // Campos básicos
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController();

  // Campos de endereço
  bool _semEnderecoFixo = false;
  final _cepCtrl = TextEditingController();
  final _logradouroCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();
  final _complementoCtrl = TextEditingController();
  final _bairroCtrl = TextEditingController();
  final _cidadeCtrl = TextEditingController();
  String? _estadoSelecionado;

  // Localização geográfica (lat/lng, mantidos para buscas por raio)
  double? _lat;
  double? _lng;

  // Imagens
  String? _imageUrl;
  String? _logoUrl;

  // Foco no campo cidade (para o banner de aviso)
  final _cidadeFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _phoneCtrl.dispose();
    _categoryCtrl.dispose();
    _instagramCtrl.dispose();
    _cepCtrl.dispose();
    _logradouroCtrl.dispose();
    _numeroCtrl.dispose();
    _complementoCtrl.dispose();
    _bairroCtrl.dispose();
    _cidadeCtrl.dispose();
    _cidadeFocus.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (widget.shopId.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final doc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;

        _nameCtrl.text = data['nome'] ?? '';
        _descCtrl.text = data['descricao'] ?? data['bio'] ?? '';
        _phoneCtrl.text = data['telefone'] ?? data['whatsapp'] ?? '';
        _categoryCtrl.text = data['categoria'] ?? '';
        _instagramCtrl.text = data['instagram'] ?? '';
        _cidadeCtrl.text = data['cidade'] ?? data['city'] ?? '';

        // Estado salvo como UF (2 letras)
        final estadoRaw =
            (data['estado'] ?? '').toString().toUpperCase().trim();
        _estadoSelecionado = _kUFs.contains(estadoRaw) ? estadoRaw : null;

        // Campos de endereço detalhados
        _semEnderecoFixo = data['sem_endereco_fixo'] ?? false;
        _cepCtrl.text = data['cep'] ?? '';
        _logradouroCtrl.text = data['logradouro'] ?? '';
        _numeroCtrl.text = data['numero'] ?? '';
        _complementoCtrl.text = data['complemento'] ?? '';
        _bairroCtrl.text = data['bairro'] ?? '';

        _lat = data['lat'] != null ? (data['lat'] as num).toDouble() : null;
        _lng = data['lng'] != null ? (data['lng'] as num).toDouble() : null;

        if (mounted) {
          setState(() {
            _imageUrl = (data['imageUrl'] != null &&
                    data['imageUrl'].toString().isNotEmpty)
                ? data['imageUrl']
                : null;
            _logoUrl = (data['logoUrl'] != null &&
                    data['logoUrl'].toString().isNotEmpty)
                ? data['logoUrl']
                : data['foto'];
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Erro ao carregar: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Preenche automaticamente os campos de endereço via fetchCep.
  Future<void> _buscarCep() async {
    final cep = _cepCtrl.text;
    if (cep.replaceAll(RegExp(r'\D'), '').length != 8) return;

    setState(() => _isLoadingCep = true);
    final result = await LocationService.buscarCep(cep);
    if (mounted) {
      setState(() => _isLoadingCep = false);
      if (result != null) {
        _logradouroCtrl.text = result.logradouro;
        _bairroCtrl.text = result.bairro;
        _cidadeCtrl.text = result.cidade;
        final uf = result.estado.toUpperCase();
        _estadoSelecionado = _kUFs.contains(uf) ? uf : null;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('?? CEP encontrado: ${result.cidade}/${result.estado}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('CEP não encontrado. Preencha cidade e estado manualmente.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ));
      }
    }
  }

  Future<void> _saveData() async {
    if (!_formKey.currentState!.validate()) return;

    // Validação extra para cidade e estado (campos obrigatórios)
    final cidade = _cidadeCtrl.text.trim();
    final estado = _estadoSelecionado;
    if (cidade.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            '?? Cidade é obrigatória para que sua loja seja encontrada pelos clientes.'),
        backgroundColor: Colors.red,
      ));
      _cidadeFocus.requestFocus();
      return;
    }
    if (estado == null || estado.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('?? Estado (UF) é obrigatório.'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('shops')
          .doc(widget.shopId)
          .update({
        'nome': _nameCtrl.text.trim(),
        'descricao': _descCtrl.text.trim(),
        'telefone': _phoneCtrl.text.trim(),
        'categoria': _categoryCtrl.text.trim(),
        'instagram': _instagramCtrl.text.trim(),
        'imageUrl': _imageUrl,
        'logoUrl': _logoUrl,
        'lat': _lat,
        'lng': _lng,
        // Campos de localização
        'cidade': cidade,
        'estado': estado,
        'cep': _cepCtrl.text.trim(),
        'logradouro': _logradouroCtrl.text.trim(),
        'numero': _numeroCtrl.text.trim(),
        'complemento': _complementoCtrl.text.trim(),
        'bairro': _bairroCtrl.text.trim(),
        'sem_endereco_fixo': _semEnderecoFixo,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '? Endereço salvo! Sua loja agora pode ser encontrada pelos clientes em $cidade.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectLocation() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const AddressSelectorPage()),
    );
    if (result != null && mounted) {
      setState(() {
        // Endereço selecionado no mapa: preenche os campos disponíveis
        final city = result['city'] ?? '';
        if (city.isNotEmpty) _cidadeCtrl.text = city;
        _lat = result['lat'] != null ? (result['lat'] as num).toDouble() : null;
        _lng = result['lng'] != null ? (result['lng'] as num).toDouble() : null;
      });
    }
  }

  Future<void> _pickAndUploadImage(bool isCover) async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: isCover ? 1920 : 800,
        maxHeight: isCover ? 1080 : 800,
        imageQuality: 85,
      );
      if (image == null) return;

      setState(() => _isUploading = true);
      final Uint8List bytes = await image.readAsBytes();
      final String fileName = isCover
          ? 'cover_${DateTime.now().millisecondsSinceEpoch}.jpg'
          : 'logo_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final Reference ref = FirebaseStorage.instance
          .ref()
          .child('shops/${widget.shopId}/$fileName');

      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final String downloadUrl = await ref.getDownloadURL();

      if (mounted) {
        setState(() {
          if (isCover) {
            _imageUrl = downloadUrl;
          } else {
            _logoUrl = downloadUrl;
          }
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isCover
              ? '?? Capa carregada! Clique em SALVAR.'
              : '?? Logo carregada! Clique em SALVAR.'),
          backgroundColor: Colors.blue,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _nameCtrl.text.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      color: const Color(0xFFF8F9FD),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Indicador de upload
          if (_isUploading)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Enviando...',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.blue,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // -------------------------------------------------------
                    // Card de Imagens (capa + logo)
                    // -------------------------------------------------------
                    _buildImageCard(),

                    const SizedBox(height: 16),

                    // -------------------------------------------------------
                    // Card de Informações Básicas
                    // -------------------------------------------------------
                    _buildSectionCard(
                      title: 'Informações do Negócio',
                      icon: Icons.store,
                      children: [
                        Row(children: [
                          Expanded(
                            flex: 3,
                            child: _buildInput(
                                'Nome do Negócio', _nameCtrl, Icons.store),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: _buildInput(
                                'Categoria', _categoryCtrl, Icons.category),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        _buildInput(
                            'Descrição / Bio', _descCtrl, Icons.description,
                            maxLines: 2),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                              child: _buildInput('Telefone / WhatsApp',
                                  _phoneCtrl, Icons.phone)),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _buildInput(
                                  'Instagram', _instagramCtrl, Icons.camera_alt,
                                  hint: '@seu_usuario')),
                        ]),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // -------------------------------------------------------
                    // Card de Endereço
                    // -------------------------------------------------------
                    _buildSectionCard(
                      title: 'Localização *',
                      icon: Icons.location_on,
                      children: [
                        // Checkbox "sem endereço fixo"
                        Row(children: [
                          Checkbox(
                            value: _semEnderecoFixo,
                            activeColor: AppColors.primaryPurple,
                            onChanged: (v) =>
                                setState(() => _semEnderecoFixo = v ?? false),
                          ),
                          const Expanded(
                            child: Text(
                              'Minha loja não possui endereço fixo (ambulante / atendimento a domicílio)',
                              style: TextStyle(
                                  fontSize: 13, color: Colors.black87),
                            ),
                          ),
                        ]),

                        const SizedBox(height: 10),

                        // CEP (sempre visível, opcional se sem endereço fixo)
                        Row(children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _cepCtrl,
                              keyboardType: TextInputType.number,
                              maxLength: 9,
                              style: const TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                labelText:
                                    _semEnderecoFixo ? 'CEP (opcional)' : 'CEP',
                                hintText: '00000-000',
                                counterText: '',
                                prefixIcon: const Icon(Icons.map,
                                    color: AppColors.primaryPurple, size: 20),
                                suffixIcon: _isLoadingCep
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2)),
                                      )
                                    : null,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        BorderSide(color: Colors.grey[300]!)),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        BorderSide(color: Colors.grey[300]!)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: AppColors.primaryPurple,
                                        width: 2)),
                                filled: true,
                                fillColor: Colors.grey[50],
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                isDense: true,
                              ),
                              onChanged: (v) {
                                // Formatar como 00000-000
                                final digits = v.replaceAll(RegExp(r'\D'), '');
                                if (digits.length == 8) {
                                  _cepCtrl.value = TextEditingValue(
                                    text:
                                        '${digits.substring(0, 5)}-${digits.substring(5)}',
                                    selection:
                                        TextSelection.collapsed(offset: 9),
                                  );
                                }
                              },
                              onFieldSubmitted: (_) => _buscarCep(),
                              onEditingComplete: _buscarCep,
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 44,
                            child: OutlinedButton.icon(
                              onPressed: _isLoadingCep ? null : _buscarCep,
                              icon: const Icon(Icons.search, size: 18),
                              label: const Text('Buscar'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primaryPurple,
                                side: const BorderSide(
                                    color: AppColors.primaryPurple),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ]),

                        const SizedBox(height: 10),

                        // Campos que ficam ocultos se sem_endereço_fixo
                        if (!_semEnderecoFixo) ...[
                          Row(children: [
                            Expanded(
                              flex: 3,
                              child: _buildInput(
                                  'Logradouro', _logradouroCtrl, Icons.home,
                                  hint: 'Rua, Av., etc.'),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 1,
                              child:
                                  _buildInput('Número', _numeroCtrl, Icons.tag),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                                child: _buildInput('Complemento',
                                    _complementoCtrl, Icons.apartment,
                                    hint: 'Apto, Sala...', required: false)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _buildInput(
                                    'Bairro', _bairroCtrl, Icons.location_city,
                                    hint: 'Bairro')),
                          ]),
                          const SizedBox(height: 10),
                        ],

                        // Cidade e Estado — SEMPRE obrigatórios
                        Row(children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _cidadeCtrl,
                              focusNode: _cidadeFocus,
                              style: const TextStyle(fontSize: 14),
                              decoration: InputDecoration(
                                labelText: 'Cidade *',
                                hintText: 'Ex: São Paulo',
                                prefixIcon: const Icon(Icons.location_city,
                                    color: AppColors.primaryPurple, size: 20),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        BorderSide(color: Colors.grey[300]!)),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        BorderSide(color: Colors.grey[300]!)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: AppColors.primaryPurple,
                                        width: 2)),
                                errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Colors.red, width: 2)),
                                focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Colors.red, width: 2)),
                                filled: true,
                                fillColor: Colors.grey[50],
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                isDense: true,
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Cidade é obrigatória.'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: _estadoSelecionado,
                              decoration: InputDecoration(
                                labelText: 'Estado *',
                                labelStyle: const TextStyle(fontSize: 13),
                                prefixIcon: const Icon(Icons.flag,
                                    color: AppColors.primaryPurple, size: 20),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        BorderSide(color: Colors.grey[300]!)),
                                enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        BorderSide(color: Colors.grey[300]!)),
                                focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: AppColors.primaryPurple,
                                        width: 2)),
                                errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: const BorderSide(
                                        color: Colors.red, width: 2)),
                                filled: true,
                                fillColor: Colors.grey[50],
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                                isDense: true,
                              ),
                              hint: const Text('UF',
                                  style: TextStyle(fontSize: 13)),
                              items: _kUFs
                                  .map((uf) => DropdownMenuItem(
                                      value: uf,
                                      child: Text(uf,
                                          style:
                                              const TextStyle(fontSize: 14))))
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _estadoSelecionado = v),
                              validator: (v) => (v == null || v.isEmpty)
                                  ? 'Obrigatório'
                                  : null,
                            ),
                          ),
                        ]),

                        const SizedBox(height: 10),

                        // Botão: selecionar no mapa
                        OutlinedButton.icon(
                          onPressed: _selectLocation,
                          icon: const Icon(Icons.map_outlined, size: 18),
                          label: const Text('Selecionar localização no mapa'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryPurple,
                            side: BorderSide(color: Colors.grey[300]!),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Botão Salvar
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed:
                            (_isLoading || _isUploading) ? null : _saveData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryPurple,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[400],
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        icon: _isLoading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.check_circle,
                                color: Colors.white),
                        label: Text(
                          _isLoading ? 'Salvando...' : 'SALVAR ALTERAÇÕES',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              letterSpacing: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // IMAGENS: capa + logo
  // ---------------------------------------------------------------------------
  Widget _buildImageCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: [
        SizedBox(
          height: 130,
          child: Stack(clipBehavior: Clip.none, children: [
            // Capa
            GestureDetector(
              onTap: _isUploading ? null : () => _pickAndUploadImage(true),
              child: Container(
                key: ValueKey('cover_$_imageUrl'),
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  image: _imageUrl != null && _imageUrl!.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(_imageUrl!), fit: BoxFit.cover)
                      : null,
                ),
                child: _imageUrl == null || _imageUrl!.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.add_photo_alternate,
                                  color: Colors.grey, size: 32),
                              SizedBox(height: 4),
                              Text('Adicionar Capa',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 12)),
                            ]),
                      )
                    : null,
              ),
            ),
            // Botão editar capa
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8)
                    ]),
                child: IconButton(
                  iconSize: 20,
                  icon: const Icon(Icons.edit, color: AppColors.primaryPurple),
                  onPressed:
                      _isUploading ? null : () => _pickAndUploadImage(true),
                ),
              ),
            ),
            // Logo
            Positioned(
              bottom: 0,
              left: 20,
              child: GestureDetector(
                onTap: _isUploading ? null : () => _pickAndUploadImage(false),
                child: Container(
                  key: ValueKey('logo_$_logoUrl'),
                  height: 70,
                  width: 70,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 12)
                    ],
                    image: _logoUrl != null && _logoUrl!.isNotEmpty
                        ? DecorationImage(
                            image: NetworkImage(_logoUrl!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: _logoUrl == null || _logoUrl!.isEmpty
                      ? const Center(
                          child: Icon(Icons.add_a_photo,
                              color: Colors.grey, size: 24))
                      : null,
                ),
              ),
            ),
            // Botão editar logo
            Positioned(
              bottom: 2,
              left: 68,
              child: Container(
                decoration: BoxDecoration(
                    color: AppColors.primaryPurple,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2)),
                child: IconButton(
                  iconSize: 14,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  onPressed:
                      _isUploading ? null : () => _pickAndUploadImage(false),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  // Card de Seção
  // ---------------------------------------------------------------------------
  Widget _buildSectionCard(
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: AppColors.primaryPurple, size: 18),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87)),
        ]),
        const SizedBox(height: 14),
        ...children,
      ]),
    );
  }

  // ---------------------------------------------------------------------------
  // Campo de Texto Compacto
  // ---------------------------------------------------------------------------
  Widget _buildInput(
    String label,
    TextEditingController ctrl,
    IconData icon, {
    int maxLines = 1,
    String? hint,
    bool required = true,
  }) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(fontSize: 13),
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.primaryPurple, size: 20),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey[300]!)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey[300]!)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: AppColors.primaryPurple, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.red, width: 2)),
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Obrigatório' : null
          : null,
    );
  }
}
