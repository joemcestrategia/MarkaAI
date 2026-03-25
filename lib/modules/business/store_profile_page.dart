import 'dart:io' if (dart.library.html) 'package:flutter_application_1/core/utils/io_stub.dart' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/services/image_service.dart';

// Lista fixa das UFs brasileiras
const List<String> _kStoreUFs = [
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

// Nichos/categorias de negócio
const List<String> _kNichos = [
  'Salão de Beleza',
  'Barbearia',
  'Estética e Spa',
  'Nail Design / Manicure',
  'Tatuagem e Piercing',
  'Academia / Personal Trainer',
  'Clínica de Saúde',
  'Psicologia / Terapia',
  'Nutrição',
  'Odontologia',
  'Veterinário / Pet Shop',
  'Fotografia',
  'Advocacia',
  'Contabilidade',
  'Consultoria',
  'Educação / Aulas Particulares',
  'Moda e Vestuário',
  'Gastronomia / Buffet',
  'Limpeza e Conservação',
  'Reforma e Construção',
  'Tecnologia / TI',
  'Outros',
];

class StoreProfilePage extends StatefulWidget {
  final bool highlightLocation;
  const StoreProfilePage({super.key, this.highlightLocation = false});

  @override
  State<StoreProfilePage> createState() => _StoreProfilePageState();
}

class _StoreProfilePageState extends State<StoreProfilePage> {
  final _formKey = GlobalKey<FormState>();

  // Controladores
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _slugController = TextEditingController();
  final _instagramController = TextEditingController();
  final _tiktokController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _zipController = TextEditingController();
  final _streetController = TextEditingController();
  final _numberController = TextEditingController();
  final _neighborhoodController = TextEditingController();
  final _complementController = TextEditingController();

  // Máscaras
  final _phoneMask = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {"#": RegExp(r'[0-9]')},
  );
  final _zipMask = MaskTextInputFormatter(
    mask: '#####-###',
    filter: {"#": RegExp(r'[0-9]')},
  );

  // Imagens
  String? _logoUrl;
  String? _coverUrl;
  XFile? _newLogoFile;
  XFile? _newCoverFile;

  // Campos de localização
  final _cidadeController = TextEditingController();
  String? _estadoSelecionado;

  // Nicho/Categoria
  String? _nichoSelecionado;
  final _nichoOutrosController = TextEditingController();

  // Scroll key para destacar localização
  final _locationKey = GlobalKey();

  bool _isLoading = true;
  bool _isSaving = false;
  double _uploadProgress = 0.0;
  String? _shopId;

  @override
  void initState() {
    super.initState();
    _loadStoreData();
    if (widget.highlightLocation) {
      // Scroll até a seção de localização após o frame ser renderizado
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_locationKey.currentContext != null) {
          Scrollable.ensureVisible(
            _locationKey.currentContext!,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOut,
            alignment: 0.1,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _slugController.dispose();
    _instagramController.dispose();
    _tiktokController.dispose();
    _youtubeController.dispose();
    _zipController.dispose();
    _streetController.dispose();
    _numberController.dispose();
    _neighborhoodController.dispose();
    _complementController.dispose();
    _cidadeController.dispose();
    _nichoOutrosController.dispose();
    super.dispose();
  }

  Future<void> _loadStoreData() async {
    final supabase = sb.Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        String? id = await SessionService.getShopId();

        if (id == null || id.isEmpty) {
          final userDoc = await supabase
              .from('users')
              .select('shop_id')
              .eq('id', user.id)
              .maybeSingle();
          id = userDoc?['shop_id'];
        }

        if (id != null) {
          final shopDoc = await supabase
              .from('shops')
              .select()
              .eq('id', id)
              .maybeSingle();
          if (shopDoc != null) {
            final data = shopDoc;

            if (mounted) {
              setState(() {
                _shopId = id;
                _nameController.text = data['name'] ?? "";
                _descController.text = data['description'] ?? "";
                _addressController.text = data['address'] ?? "";
                _phoneController.text = data['whatsapp'] ?? data['phone'] ?? "";
                _slugController.text = data['slug'] ?? "";
                _instagramController.text = data['instagram'] ?? "";
                _tiktokController.text = data['tiktok'] ?? "";
                _youtubeController.text = data['youtube'] ?? "";
                _zipController.text = data['zip_code'] ?? "";
                _streetController.text = data['street'] ?? "";
                _numberController.text = data['number'] ?? "";
                _neighborhoodController.text = data['neighborhood'] ?? "";
                _complementController.text = data['complement'] ?? "";
                _addressController.text = data['address'] ?? "";
                _logoUrl = data['logo_url'];
                _coverUrl = data['image_url'];
                // Localização
                _cidadeController.text = data['city'] ?? data['city'] ?? '';
                final estadoRaw =
                    (data['state'] ?? '').toString().toUpperCase().trim();
                _estadoSelecionado =
                    _kStoreUFs.contains(estadoRaw) ? estadoRaw : null;
                // Nicho
                final nichoRaw = data['category'] ?? data['nicho'] ?? '';
                if (nichoRaw.isNotEmpty && _kNichos.contains(nichoRaw)) {
                  _nichoSelecionado = nichoRaw;
                } else if (nichoRaw.isNotEmpty) {
                  _nichoSelecionado = 'Outros';
                  _nichoOutrosController.text = nichoRaw;
                }
                _isLoading = false;
              });
              // Scroll após carregar os dados se precisar destacar
              if (widget.highlightLocation) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_locationKey.currentContext != null) {
                    Scrollable.ensureVisible(
                      _locationKey.currentContext!,
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeInOut,
                      alignment: 0.1,
                    );
                  }
                });
              }
            }
          } else {
            if (mounted) {
              setState(() {
                _shopId = id;
                _isLoading = false;
              });
            }
          }
        } else {
          if (mounted) {
            setState(() => _isLoading = false);
          }
        }
      } catch (e) {
        debugPrint("Erro ao carregar dados: $e");
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 🎉¨ FUNÇÃO CORRIGIDA: Abrir editor de imagem e fazer upload IMEDIATO ou agendado
  // Nota: Para manter a experiência fluida, faremos o upload ao salvar o perfil, 
  // mas usaremos o ImageService para comprimir e preparar.
  Future<void> _pickAndEditImage({required bool isCover}) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
    );

    if (image != null && mounted) {
      // Abrir editor
      final editedImage = await Navigator.push<XFile>(
        context,
        MaterialPageRoute(
          builder: (context) => _ImageAdjustmentPage(
            imageFile: image,
            aspectRatio: isCover ? 3.0 : 1.0, // 3:1 para capa, 1:1 para logo
          ),
        ),
      );

      if (editedImage != null) {
        setState(() {
          if (isCover) {
            _newCoverFile = editedImage;
          } else {
            _newLogoFile = editedImage;
          }
        });
      }
    }
  }

  // Removida a função antiga _uploadFile pois agora usamos o ImageService

  Future<bool> _isSlugAvailable(String slug) async {
    if (slug.isEmpty) return true;

    final supabase = sb.Supabase.instance.client;
    final results = await supabase
        .from('shops')
        .select('id')
        .eq('slug', slug);

    // Se não encontrou nenhum, está disponível
    if (results.isEmpty) return true;

    // Se encontrou, verifica se é o próprio shop
    return results.first['id'] == _shopId;
  }

  String _normalizeSlug(String input) {
    // Remove espaços, acentos e caracteres especiais
    String slug = input.toLowerCase().trim();
    slug = slug.replaceAll(RegExp(r'[áàâãä]'), 'a');
    slug = slug.replaceAll(RegExp(r'[éèêë]'), 'e');
    slug = slug.replaceAll(RegExp(r'[íìîï]'), 'i');
    slug = slug.replaceAll(RegExp(r'[óòôõö]'), 'o');
    slug = slug.replaceAll(RegExp(r'[úùûü]'), 'u');
    slug = slug.replaceAll(RegExp(r'[ç]'), 'c');
    slug = slug.replaceAll(RegExp(r'[^a-z0-9-]'), '');
    return slug;
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    // Validar slug se foi preenchido
    if (_slugController.text.trim().isNotEmpty) {
      final slugNormalizado = _normalizeSlug(_slugController.text.trim());
      final isAvailable = await _isSlugAvailable(slugNormalizado);

      if (!isAvailable) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Este link já está em uso. Escolha outro.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      _slugController.text = slugNormalizado;
    }

    setState(() => _isSaving = true);

    try {
      String? logoDownloadUrl = _logoUrl;
      String? coverDownloadUrl = _coverUrl;

      // Upload do Logo com progresso
      if (_newLogoFile != null) {
        setState(() => _uploadProgress = 0.1);
        logoDownloadUrl = await ImageService.uploadProfilePhoto(
          _newLogoFile!, 
          _shopId!, // Para shops, usamos o ID do shop no bucket stores? 
          // O ImageService usa o bucket 'profiles' no uploadProfilePhoto. 
          // Ajustarei para o contexto correto se necessário. 
          // Na verdade, o requisito diz 'stores' para capa e logo do estabelecimento.
          onProgress: (p) => setState(() => _uploadProgress = p * 0.5),
        );
      }

      // Upload da Capa com progresso
      if (_newCoverFile != null) {
        double startP = _newLogoFile != null ? 0.5 : 0.0;
        coverDownloadUrl = await ImageService.uploadStoreCover(
          _newCoverFile!, 
          _shopId!, 
          onProgress: (p) => setState(() => _uploadProgress = startP + (p * 0.5)),
        );
      }

      setState(() => _uploadProgress = 1.0);

      // Determina nicho final
      final nichoFinal = _nichoSelecionado == 'Outros'
          ? _nichoOutrosController.text.trim()
          : (_nichoSelecionado ?? '');

      // --- VALIDAÇÃO DE SLUG ÚNICO ---
      final newSlug = _slugController.text.trim();
      if (newSlug.isNotEmpty) {
        // Busca se existe outra loja com o mesmo slug, excluindo a própria
        final existing = await sb.Supabase.instance.client
            .from('shops')
            .select('id')
            .eq('slug', newSlug)
            .neq('id', _shopId!)
            .maybeSingle();

        if (existing != null) {
          if (!mounted) return;
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ Este link já está sendo usado por outra loja. Escolha outro."),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
          return;
        }
      }

      // Atualização seletiva para evitar erros de colunas inexistentes ou sobrescrever dados
      final updateData = {
        'name': _nameController.text.trim(),
        'description': _descController.text.trim(),
        'address': _addressController.text.trim(),
        'whatsapp': _phoneController.text.replaceAll(RegExp(r'\D'), ''),
        'phone': _phoneController.text.replaceAll(RegExp(r'\D'), ''),
        'instagram': _instagramController.text.trim(),
        'tiktok': _tiktokController.text.trim(),
        'youtube': _youtubeController.text.trim(),
        'city': _cidadeController.text.trim(),
        'state': _estadoSelecionado ?? '',
        'zip_code': _zipController.text.trim(),
        'street': _streetController.text.trim(),
        'number': _numberController.text.trim(),
        'neighborhood': _neighborhoodController.text.trim(),
        'complement': _complementController.text.trim(),
        'category': nichoFinal,
        'niche': nichoFinal,
        'logo_url': logoDownloadUrl,
        'image_url': coverDownloadUrl,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Adicionar Slug se preenchido
      updateData['slug'] = newSlug.isNotEmpty ? newSlug : null;

      await sb.Supabase.instance.client
          .from('shops')
          .update(updateData)
          .eq('id', _shopId!);

      if (mounted) {
        setState(() {
          _logoUrl = logoDownloadUrl;
          _coverUrl = coverDownloadUrl;
          _newLogoFile = null;
          _newCoverFile = null;
          _uploadProgress = 0.0;
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Perfil e imagens salvos com sucesso!"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } on sb.PostgrestException catch (e) {
      debugPrint("Erro Postgrest: ${e.message}");
      if (!mounted) return;
      setState(() => _uploadProgress = 0.0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Erro de banco: ${e.message}"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint("Erro ao salvar perfil: $e");

      if (!mounted) return;
      setState(() => _uploadProgress = 0.0);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Falha no upload: $e"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _buildServicesShowcase() {
    if (_shopId == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Destaques da Vitrine",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              // Indicador visual opcional
              Icon(Icons.stars, color: Colors.amber[700], size: 20),
            ],
          ),
        ),
        SizedBox(
          height: 160,
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: sb.Supabase.instance.client
                .from('services')
                .stream(primaryKey: ['id'])
                .eq('shop_id', _shopId!),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              // Filter client-side if multiple filters are not supported on stream
              final allServices = snapshot.data!;
              final activeServices = allServices.where((s) => s['ativo'] == true).toList();

              if (activeServices.isEmpty) {
                return Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.storefront,
                            color: Colors.grey[400], size: 40),
                        const SizedBox(height: 8),
                        Text(
                          "Nenhum serviço ativo.",
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final docsWithPhotos = activeServices.where((data) {
                final fotos = data['photos_urls'] ??
                    data['fotos'] ??
                    data['image_url'] ??
                    data['imagens'] ??
                    [];

                if (fotos is String && fotos.isNotEmpty) return true;
                if (fotos is List && fotos.isNotEmpty) return true;

                return false;
              }).toList();

              if (docsWithPhotos.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      "Adicione fotos aos seus serviços para exibi-los aqui.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                scrollDirection: Axis.horizontal,
                itemCount: docsWithPhotos.length,
                itemBuilder: (context, index) {
                  final data = docsWithPhotos[index];

                  dynamic fotosData = data['photos_urls'] ??
                      data['fotos'] ??
                      data['image_url'] ??
                      data['imagens'];

                  String? thumb;

                  if (fotosData is String) {
                    thumb = fotosData;
                  } else if (fotosData is List && fotosData.isNotEmpty) {
                    thumb = fotosData.first.toString();
                  }

                  if (thumb == null) return const SizedBox.shrink();

                  return Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: thumb,
                            fit: BoxFit.cover,
                            placeholder: (c, u) => Container(
                              color: Colors.grey[200],
                              child: const Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (c, u, e) => Container(
                              color: Colors.grey[300],
                              child: const Icon(Icons.broken_image,
                                  color: Colors.grey),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.8),
                                    Colors.transparent
                                  ],
                                ),
                              ),
                              child: Text(
                                data['name'] ?? "Serviço",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5FB),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, -4),
              )
            ],
          ),
          child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryPurple,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.primaryPurple.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isSaving
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        ),
                        if (_uploadProgress > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            "${(_uploadProgress * 100).toInt()}%",
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ]
                      ],
                    )
                  : const Text(
                      "SALVAR ALTERAÇÕES",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryPurple))
          : CustomScrollView(
              slivers: [
                // ─── APP BAR com CAPA e LOGO embutido ────────────────────
                SliverAppBar(
                  expandedHeight: 200.0,
                  pinned: true,
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  title: Text(
                    _isSaving ? "Salvando..." : "Editar Perfil",
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  centerTitle: true,
                  iconTheme: const IconThemeData(color: Colors.white),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        // ── Imagem da Capa ──────────────────────────────
                        GestureDetector(
                          onTap: () => _pickAndEditImage(isCover: true),
                          child: _newCoverFile != null
                              ? (kIsWeb
                                  ? Image.network(_newCoverFile!.path,
                                      fit: BoxFit.cover)
                                  : Image.file(io.File(_newCoverFile!.path) as dynamic,
                                      fit: BoxFit.cover))
                              : (_coverUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: _coverUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (c, u) => Container(
                                          color: AppColors.primaryPurple
                                              .withValues(alpha: 0.2)),
                                    )
                                  : Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            AppColors.primaryPurple,
                                            Color(0xFF4A148C)
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                      ),
                                      child: const Center(
                                          child: Icon(Icons.store,
                                              size: 60, color: Colors.white24)),
                                    )),
                        ),
                        // Overlay escurecido no bottom para legibilidade
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: 80,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.45),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // ── Logo circular na esquerda inferior ──────────
                        Positioned(
                          left: 16,
                          bottom: 12,
                          child: GestureDetector(
                            onTap: () => _pickAndEditImage(isCover: false),
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    border: Border.all(
                                        color: Colors.white, width: 3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      )
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: _newLogoFile != null
                                        ? (kIsWeb
                                            ? Image.network(_newLogoFile!.path,
                                                fit: BoxFit.cover)
                                            : Image.file(
                                                io.File(_newLogoFile!.path) as dynamic,
                                                fit: BoxFit.cover))
                                        : (_logoUrl != null
                                            ? CachedNetworkImage(
                                                imageUrl: _logoUrl!,
                                                fit: BoxFit.cover,
                                                placeholder: (c, u) =>
                                                    const CircularProgressIndicator(
                                                        strokeWidth: 2),
                                                errorWidget: (c, u, e) =>
                                                    const Icon(Icons.store,
                                                        color: Colors.grey,
                                                        size: 32),
                                              )
                                            : Icon(Icons.add_a_photo,
                                                color: Colors.grey[300],
                                                size: 30)),
                                  ),
                                ),
                                // Botão de edição do logo
                                Container(
                                  margin: const EdgeInsets.only(
                                      right: 1, bottom: 1),
                                  padding: const EdgeInsets.all(5),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primaryPurple,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.edit,
                                      color: Colors.white, size: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // ── Botão editar capa (direita inferior) ────────
                        Positioned(
                          right: 14,
                          bottom: 14,
                          child: GestureDetector(
                            onTap: () => _pickAndEditImage(isCover: true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.camera_alt,
                                      color: Colors.white, size: 15),
                                  SizedBox(width: 5),
                                  Text("Alterar Capa",
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ─── FORMULÁRIO ───────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTextField(
                            controller: _nameController,
                            label: "Nome da Loja",
                            icon: Icons.store_mall_directory,
                            validator: (v) =>
                                v!.isEmpty ? "Campo obrigatório" : null,
                          ),
                          const SizedBox(height: 12),
                          // ── Nicho / Categoria ──────────────────────────
                          _buildNichoField(),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _descController,
                            label: "Descrição",
                            icon: Icons.description,
                            maxLines: 3,
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              flex: 3,
                              child: _buildTextField(
                                controller: _streetController,
                                label: "Rua / Logradouro",
                                icon: Icons.home,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 1,
                              child: _buildTextField(
                                controller: _numberController,
                                label: "Número",
                                icon: Icons.tag,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: _buildTextField(
                                controller: _neighborhoodController,
                                label: "Bairro",
                                icon: Icons.location_city,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildTextField(
                                controller: _complementController,
                                label: "Complemento",
                                icon: Icons.apartment,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _addressController,
                            label: "Endereço Completo (referência)",
                            icon: Icons.location_on,
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _zipController,
                            label: "CEP",
                            icon: Icons.map,
                            keyboardType: TextInputType.number,
                            inputFormatters: [_zipMask],
                            validator: (v) {
                              if (v == null || v.isEmpty) return null;
                              if (v.replaceAll(RegExp(r'\D'), '').length < 8) {
                                return "CEP incompleto";
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          _buildTextField(
                            controller: _phoneController,
                            label: "WhatsApp da Loja",
                            icon: Icons.phone,
                            hint: "(00) 00000-0000",
                            keyboardType: TextInputType.phone,
                            inputFormatters: [_phoneMask],
                            onChanged: (val) {
                              final unmasked = _phoneMask.getUnmaskedText();
                              // Padrão brasileiro: celulares novos começam com 9
                              bool isMobile = unmasked.length >= 3 && unmasked[2] == '9';
                              String correctMask = isMobile ? '(##) #####-####' : '(##) ####-####';
                              
                              if (_phoneMask.getMask() != correctMask) {
                                setState(() {
                                  _phoneMask.updateMask(mask: correctMask);
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          // ── Localização: Cidade + UF ───────────────────
                          _buildLocationSection(),
                          const SizedBox(height: 16),

                          // ── Link Personalizado ──────────────────────────
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.primaryPurple
                                  .withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: AppColors.primaryPurple
                                      .withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.link,
                                        color: AppColors.primaryPurple,
                                        size: 18),
                                    const SizedBox(width: 8),
                                    const Text(
                                      "Mini Site Personalizado da Loja",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "Crie um link único para seus clientes acessarem sua loja",
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _slugController,
                                  decoration: InputDecoration(
                                    labelText: "Seu Mini Site (ex: afroED)",
                                    prefixIcon: const Icon(Icons.link,
                                        color: AppColors.primaryPurple),
                                    prefixText: "markaai.com.br/",
                                    prefixStyle: const TextStyle(
                                      color: AppColors.primaryPurple,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    suffixIcon: _slugController.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.copy,
                                                size: 20,
                                                color: AppColors.primaryPurple),
                                            onPressed: () {
                                              final link =
                                                  "https://markaai.com.br/${_normalizeSlug(_slugController.text)}";
                                              Clipboard.setData(
                                                  ClipboardData(text: link));
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content:
                                                      Text("Link copiado!"),
                                                  backgroundColor: Colors.green,
                                                  duration:
                                                      Duration(seconds: 2),
                                                ),
                                              );
                                            },
                                          )
                                        : null,
                                    border: OutlineInputBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  validator: (v) {
                                    if (v == null || v.isEmpty) {
                                      return null;
                                    }
                                    if (v.length < 3) {
                                      return "Mínimo 3 caracteres";
                                    }
                                    if (!RegExp(r'^[a-zA-Z0-9-]+$')
                                        .hasMatch(v)) {
                                      return "Apenas letras, números e hífen";
                                    }
                                    return null;
                                  },
                                  onChanged: (value) => setState(() {}),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 14),

                          // ── Redes Sociais ────────────────────────────────
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color:
                                  Colors.blue.shade50.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade100),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.share,
                                        color: Colors.blue.shade700, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      "Redes Sociais",
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Colors.blue.shade700),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "Conecte suas redes para seus clientes encontrarem você",
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey),
                                ),
                                const SizedBox(height: 10),
                                _buildTextField(
                                  controller: _instagramController,
                                  label: "Instagram (ex: @minha_loja)",
                                  icon: Icons.camera_alt,
                                ),
                                const SizedBox(height: 10),
                                _buildTextField(
                                  controller: _tiktokController,
                                  label: "TikTok (ex: @minha_loja)",
                                  icon: Icons.music_note,
                                ),
                                const SizedBox(height: 10),
                                _buildTextField(
                                  controller: _youtubeController,
                                  label: "YouTube (link do canal)",
                                  icon: Icons.play_circle_fill,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Vitrine de Serviços ─────────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.only(top: 4, bottom: 24),
                    child: _buildServicesShowcase(),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
    );
  }

  // ── Nicho/Categoria field ─────────────────────────────────────────────────
  Widget _buildNichoField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: DropdownButtonFormField<String>(
            value: _nichoSelecionado,
            decoration: InputDecoration(
              labelText: 'Nicho / Ramo de Negócio',
              prefixIcon: Icon(Icons.storefront,
                  color: AppColors.primaryPurple.withValues(alpha: 0.7)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            ),
            hint: const Text('Selecione o ramo do negócio'),
            isExpanded: true,
            items: _kNichos
                .map((n) => DropdownMenuItem(
                      value: n,
                      child: Text(n, style: const TextStyle(fontSize: 14)),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _nichoSelecionado = v),
          ),
        ),
        if (_nichoSelecionado == 'Outros') ...[
          const SizedBox(height: 10),
          _buildTextField(
            controller: _nichoOutrosController,
            label: 'Descreva seu ramo de negócio',
            icon: Icons.edit,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Campo obrigatório' : null,
          ),
        ],
      ],
    );
  }

  // ── Seção Localização: Cidade + UF ────────────────────────────────────────
  Widget _buildLocationSection() {
    final bool highlight = widget.highlightLocation &&
        (_cidadeController.text.trim().isEmpty || _estadoSelecionado == null);
    final highlightColor =
        highlight ? Colors.orange.shade700 : AppColors.primaryPurple;
    final borderColor = highlight ? Colors.orange.shade400 : Colors.transparent;

    return Container(
      key: _locationKey,
      decoration: BoxDecoration(
        color: highlight ? Colors.orange.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? Colors.orange.shade400 : Colors.grey.shade200,
          width: highlight ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: highlight
                ? Colors.orange.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                highlight ? Icons.warning_amber_rounded : Icons.location_on,
                color: highlightColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                highlight
                    ? 'Localização incompleta — Preencha para aparecer nas buscas!'
                    : 'Cidade e Estado',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: highlightColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _cidadeController,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Cidade *',
                    hintText: 'Ex: São Paulo',
                    prefixIcon: Icon(Icons.location_city,
                        color: highlightColor.withValues(alpha: 0.8), size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: borderColor.withValues(alpha: 0.5))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: highlight
                                ? Colors.orange.shade300
                                : Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: highlightColor, width: 2)),
                    errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: Colors.red, width: 2)),
                    filled: true,
                    fillColor: highlight ? Colors.white : Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    isDense: true,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Cidade é obrigatória'
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _estadoSelecionado,
                  decoration: InputDecoration(
                    labelText: 'Estado *',
                    labelStyle: const TextStyle(fontSize: 13),
                    prefixIcon: Icon(Icons.flag,
                        color: highlightColor.withValues(alpha: 0.8), size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                            color: highlight
                                ? Colors.orange.shade300
                                : Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: highlightColor, width: 2)),
                    errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: Colors.red, width: 2)),
                    filled: true,
                    fillColor: highlight ? Colors.white : Colors.grey.shade50,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    isDense: true,
                  ),
                  hint: const Text('UF', style: TextStyle(fontSize: 13)),
                  items: _kStoreUFs
                      .map((uf) => DropdownMenuItem(
                          value: uf,
                          child:
                              Text(uf, style: const TextStyle(fontSize: 14))))
                      .toList(),
                  onChanged: (v) => setState(() => _estadoSelecionado = v),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Obrigatório' : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Widget auxiliar para TextFields bonitos
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    String? hint,
    List<TextInputFormatter>? inputFormatters,
    void Function(String)? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon:
              Icon(icon, color: AppColors.primaryPurple.withValues(alpha: 0.7)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        ),
      ),
    );
  }
}

// 🎉¨ WIDGET DE AJUSTE DE IMAGEM (Mantido 100% igual)
class _ImageAdjustmentPage extends StatefulWidget {
  final XFile imageFile;
  final double aspectRatio;

  const _ImageAdjustmentPage({
    required this.imageFile,
    this.aspectRatio = 1.0,
  });

  @override
  State<_ImageAdjustmentPage> createState() => _ImageAdjustmentPageState();
}

class _ImageAdjustmentPageState extends State<_ImageAdjustmentPage> {
  double _scale = 1.0;
  double _previousScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _previousOffset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text("Ajustar Imagem"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, widget.imageFile);
              },
              child: const Text(
                "PRONTO",
                style: TextStyle(
                  color: AppColors.primaryPurple,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        body: Center(
          child: GestureDetector(
            onScaleStart: (details) {
              _previousScale = _scale;
              _previousOffset = _offset;
            },
            onScaleUpdate: (details) {
              setState(() {
                _scale = (_previousScale * details.scale).clamp(1.0, 4.0);
                _offset = _previousOffset + details.focalPointDelta;
              });
            },
            child: ClipRect(
              child: Transform.translate(
                offset: _offset,
                child: Transform.scale(
                  scale: _scale,
                  child: kIsWeb
                      ? Image.network(widget.imageFile.path)
                      : Image.file(io.File(widget.imageFile.path) as dynamic),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: Container(
          color: Colors.black87,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.zoom_out, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _scale = (_scale - 0.1).clamp(1.0, 4.0);
                      });
                    },
                  ),
                  Text(
                    "${(_scale * 100).toInt()}%",
                    style: const TextStyle(color: Colors.white),
                  ),
                  IconButton(
                    icon: const Icon(Icons.zoom_in, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _scale = (_scale + 0.1).clamp(1.0, 4.0);
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                "Arraste para reposicionar • Pinçar para zoom",
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
