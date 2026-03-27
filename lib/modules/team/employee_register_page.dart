import 'package:flutter/foundation.dart';
import 'dart:io' if (dart.library.html) 'package:flutter_application_1/core/utils/io_stub.dart' as io;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';
import '../../core/services/image_service.dart';
import '../../core/services/plan_features_service.dart';
import 'package:flutter/services.dart';
import '../../core/services/shop_data_cache_service.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:cached_network_image/cached_network_image.dart';


class EmployeeRegisterPage extends StatefulWidget {
  final Map<String, dynamic>? employeeToEdit;
  final VoidCallback onClose;

  const EmployeeRegisterPage(
      {super.key, this.employeeToEdit, required this.onClose});

  @override
  State<EmployeeRegisterPage> createState() => _EmployeeRegisterPageState();
}

class _EmployeeRegisterPageState extends State<EmployeeRegisterPage> {
  final _formKey = GlobalKey<FormState>();

  // Controladores (HORÁRIO CORRIGIDO PARA 08:00)
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _backupEmailController =
      TextEditingController(); // 🆕 Email para backup Google Calendar
  final _phoneController = TextEditingController();
  final _startWorkController = TextEditingController(text: "08:00");
  final _endWorkController = TextEditingController(text: "18:00");
  final _comissaoController = TextEditingController(text: "0");
  final _cargoController = TextEditingController(); // Cargo ou Especialidade

  // Máscara de telefone
  final phoneMask = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {"#": RegExp(r'[0-9]')},
  );

  // Estado
  io.File? _imageFile;
  String? _existingPhotoUrl;
  String? _shopId;

  List<String> _selectedServices = [];
  List<int> _workDays = [1, 2, 3, 4, 5, 6];
  List<Map<String, dynamic>> _folgas = [];

  bool _isSaving = false;
  bool _isDeleting = false;
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    String? sId = await SessionService.getShopId();

    if (sId == null || sId.isEmpty) {
      final user = AuthService().currentUser;
      if (user != null) {
        final doc = await sb.Supabase.instance.client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();
        if (doc != null) {
          sId = doc['shop_id'];
        }
      }
    }

    if (mounted) {
      setState(() {
        _shopId = sId;

        if (widget.employeeToEdit != null) {
          final data = widget.employeeToEdit!;

          _nameController.text = data['name'] ?? "";
          _emailController.text = data['email'] ?? "";
          _backupEmailController.text =
              data['backup_email'] ?? ""; // 🆕 Carrega email de backup
          _phoneController.text = data['phone'] ?? "";
          _startWorkController.text = data['start_time'] ?? "08:00";
          _endWorkController.text = data['end_time'] ?? "18:00";
          _existingPhotoUrl = data['photo_url'];
          _comissaoController.text = (data['commission_percent'] != null)
              ? data['commission_percent'].toString()
              : '0';
          _cargoController.text = data['role'] ?? data['position'] ?? "";
          if (data['services_ids'] != null) {
            _selectedServices = List<String>.from(data['services_ids']);
          }

          if (data['work_days'] != null) {
            _workDays = List<int>.from(data['work_days']);
          }

          if (data['breaks'] != null) {
            _folgas = List<Map<String, dynamic>>.from(data['breaks']);
          }
        }
      });
    }
  }

  /// Prepara o SystemUI antes de abrir o ImageCropper no Android.
  void _prepareSystemUIForCrop() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }

  /// Restaura o SystemUI ao estado padrão do app após o crop fechar.
  void _restoreSystemUI() {
    if (!mounted) return;
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
  }

  Future<XFile?> _cropImage(XFile imageFile) async {
    try {
      if (kIsWeb) {
        try {
          final width = MediaQuery.of(context).size.width;
          if (width < 900) {
            return imageFile;
          }
        } catch (_) {}
      }

      if (!kIsWeb) {
        _prepareSystemUIForCrop();
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (!mounted) return imageFile;

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: imageFile.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Ajustar Foto',
            toolbarColor: AppColors.primaryPurple,
            toolbarWidgetColor: Colors.white,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: AppColors.primaryPurple,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: false,
            showCropGrid: true,
            hideBottomControls: false,
            dimmedLayerColor: Colors.black54,
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
          ),
          IOSUiSettings(
            title: 'Ajustar Foto',
            aspectRatioPresets: [
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
          ),
          WebUiSettings(context: context),
        ],
      );

      if (!kIsWeb) {
        _restoreSystemUI();
      }

      if (croppedFile != null) {
        return XFile(croppedFile.path);
      }
      return null;
    } catch (e) {
      if (!kIsWeb) {
        _restoreSystemUI();
      }
      return imageFile;
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final cropped = await _cropImage(picked);
      if (cropped != null) {
        setState(() => _imageFile = io.File(cropped.path));
      }
    }
  }

  Future<void> _editCurrentImage() async {
    if (_imageFile == null) return;
    final cropped = await _cropImage(XFile(_imageFile!.path));
    if (cropped != null) {
      setState(() => _imageFile = io.File(cropped.path));
    }
  }

  Future<void> _showAddFolgaDialog() async {
    DateTimeRange? pickedRange = await showDateRangePicker(
      context: context,
      locale: const Locale('pt', 'BR'),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.light().copyWith(
          primaryColor: AppColors.primaryPurple,
          colorScheme:
              const ColorScheme.light(primary: AppColors.primaryPurple),
        ),
        child: child!,
      ),
    );

    if (pickedRange != null) {
      if (!mounted) return;
      String obs = "";
      final obsController = TextEditingController();

      await showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title:
                  const Text("Motivo da Folga", style: TextStyle(fontSize: 16)),
              content: TextField(
                  controller: obsController,
                  decoration:
                      const InputDecoration(hintText: "Ex: Férias, Médico...")),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancelar")),
                ElevatedButton(
                  onPressed: () {
                    obs = obsController.text;
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Adicionar",
                      style: TextStyle(color: Colors.white)),
                )
              ],
            );
          });

      if (obs.isNotEmpty) {
        setState(() {
          _folgas.add({
            'start': pickedRange.start.toIso8601String(),
            'end': pickedRange.end
                .add(const Duration(hours: 23, minutes: 59))
                .toIso8601String(),
            'notes': obs,
          });
          _folgas.sort((a, b) =>
              (a['start'] as String).compareTo(b['start'] as String));
        });
      }
    }
  }

  Future<void> _deleteEmployee() async {
    bool confirm = await showDialog(
            context: context,
            builder: (context) => AlertDialog(
                  title: const Text("Excluir Membro?"),
                  content:
                      const Text("O funcionário será removido da lista ativa."),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Cancelar")),
                    ElevatedButton(
                      style:
                          ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text("Excluir",
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                )) ??
        false;

    if (confirm && widget.employeeToEdit != null) {
      setState(() => _isDeleting = true);
      try {
        await sb.Supabase.instance.client
            .from('employees')
            .delete()
            .eq('id', widget.employeeToEdit!['id'])
            .eq('shop_id', _shopId!); 

        // Invalida o cache
        ShopDataCacheService().invalidate(_shopId!, 'employees');

        widget.onClose();
      } catch (e) {
        if (mounted) setState(() => _isDeleting = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_workDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Selecione os dias de trabalho.")));
      return;
    }

    setState(() => _isSaving = true);

    try {
      // 🆕 Check Plan Limit
      if (widget.employeeToEdit == null) {
        final features = await PlanFeaturesService.loadFeaturesByShopId(_shopId!);
        
        // Forma correta de pegar o count no Supabase Flutter 2.0+
        final countRes = await sb.Supabase.instance.client
            .from('employees')
            .select('id')
            .eq('shop_id', _shopId!)
            .count(sb.CountOption.exact);
        
        final currentCount = countRes.count;
        
        if (currentCount >= features.maxProfessionals) {
           if (mounted) {
             setState(() => _isSaving = false);
             showDialog(
               context: context,
               builder: (ctx) => AlertDialog(
                 title: const Text("Limite de Plano"),
                 content: Text("Seu plano atual permite até ${features.maxProfessionals} profissionais. "
                     "Faça um upgrade para adicionar mais."),
                 actions: [
                   TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Entendi")),
                 ],
               ),
             );
           }
           return;
        }
      }
      String? photoUrl = _existingPhotoUrl;

      if (_imageFile != null) {
        setState(() => _uploadProgress = 0.1);
        photoUrl = await ImageService.uploadProfilePhoto(
          _imageFile!, 
          const Uuid().v4(), // Usamos um UUID para o funcionário no bucket profiles
          onProgress: (p) => setState(() => _uploadProgress = p),
        );
      }

      final employeeData = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'backup_email':
            _backupEmailController.text.trim(), // 🆕 Salva email de backup
        'phone': _phoneController.text.trim(),
        'start_time': _startWorkController.text,
        'end_time': _endWorkController.text,
        'photo_url': photoUrl,
        'services_ids': _selectedServices,
        'work_days': _workDays,
        'breaks': _folgas,
        'shop_id': _shopId,
        'commission_percent':
            double.tryParse(_comissaoController.text.replaceAll(',', '.')) ??
                0.0,
        'role': _cargoController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (widget.employeeToEdit == null) {
        employeeData['id'] = const Uuid().v4(); // 🆕 Gera ID para evitar erro de null value
        await sb.Supabase.instance.client
            .from('employees')
            .insert(employeeData);
      } else {
        await sb.Supabase.instance.client
            .from('employees')
            .update(employeeData)
            .eq('id', widget.employeeToEdit!['id']);
      }

      // Invalida o cache
      ShopDataCacheService().invalidate(_shopId!, 'employees');

      widget.onClose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("✅ Membro e foto salvos com sucesso!"),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ Erro ao salvar: $e"), backgroundColor: Colors.red));
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
    if (_isDeleting) {
      return const Center(child: CircularProgressIndicator(color: Colors.red));
    }

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // HEADER
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey[200]!))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                    widget.employeeToEdit != null
                        ? "Editar Perfil"
                        : "Novo Profissional",
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: widget.onClose),
              ],
            ),
          ),

          // CONTEÚDO
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // FOTO
                    Center(
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _pickImage,
                            child: Stack(
                              alignment: Alignment.bottomRight,
                              children: [
                                CircleAvatar(
                                  radius: 45,
                                  backgroundColor: Colors.grey[100],
                                  backgroundImage: _imageFile != null
                                      ? (kIsWeb 
                                          ? NetworkImage(_imageFile!.path) as ImageProvider
                                          : FileImage(io.File(_imageFile!.path) as dynamic) as ImageProvider)
                                      : (_existingPhotoUrl != null
                                          ? CachedNetworkImageProvider(_existingPhotoUrl!)
                                          : null) as ImageProvider?,
                                  child:
                                      (_imageFile == null && _existingPhotoUrl == null)
                                          ? const Icon(Icons.camera_alt,
                                              size: 24, color: Colors.grey)
                                          : null,
                                ),
                                if (_imageFile != null)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: GestureDetector(
                                      onTap: _editCurrentImage,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryPurple,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 2),
                                        ),
                                        child: const Icon(Icons.crop, size: 14, color: Colors.white),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (_uploadProgress > 0 && _uploadProgress < 1.0) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: 100,
                              child: LinearProgressIndicator(
                                value: _uploadProgress,
                                backgroundColor: Colors.grey[200],
                                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryPurple),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text("${(_uploadProgress * 100).toInt()}%", style: const TextStyle(fontSize: 10)),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),

                    _sectionTitle("Dados Pessoais"),
                    _buildField("Nome Completo", _nameController,
                        icon: Icons.person_outline),
                    _buildField(
                        "Cargo / Especialidade (Ex: Barbeiro, Esteticista)",
                        _cargoController,
                        icon: Icons.work_outline),
                    _buildField(
                      "Email para Backup (Google Calendar)",
                      _backupEmailController,
                      icon: Icons.cloud_upload_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v != null && v.isNotEmpty && !v.contains('@')) {
                          return "Email inválido";
                        }
                        return null;
                      },
                    ),
                    _buildField(
                      "Telefone / WhatsApp",
                      _phoneController,
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [phoneMask],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null; // Campo opcional
                        return v.length < 14 ? "Telefone inválido" : null;
                      },
                    ),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 20),

                    _sectionTitle("Jornada de Trabalho"),
                    Row(
                      children: [
                        Expanded(
                            child: _buildField("Início", _startWorkController,
                                icon: Icons.access_time)),
                        const SizedBox(width: 15),
                        Expanded(
                            child: _buildField("Fim", _endWorkController,
                                icon: Icons.access_time_filled)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildField("Comissão (%)", _comissaoController,
                        icon: Icons.percent,
                        keyboardType: TextInputType.number,
                        validator: (v) => null),
                    const Text("Dias de Atendimento",
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _buildDaysSelector(),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 20),

                    _sectionTitle("Especialidades & Serviços"),
                    const Text(
                        "Marque os serviços que este profissional realiza:",
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 10),
                    _buildServicesSelector(),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _sectionTitle("Ausências"),
                        TextButton.icon(
                            onPressed: _showAddFolgaDialog,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text("Add Folga",
                                style: TextStyle(fontSize: 12))),
                      ],
                    ),
                    _buildFolgasList(),

                    if (widget.employeeToEdit != null) ...[
                      const SizedBox(height: 40),
                      Center(
                        child: TextButton.icon(
                          onPressed: _deleteEmployee,
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          label: const Text("Remover da Equipe",
                              style: TextStyle(color: Colors.red)),
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            ),
          ),

          // RODAPÉ
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey[100]!))),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("SALVAR DADOS",
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.black87)),
    );
  }

  Widget _buildField(String label, TextEditingController controller,
      {IconData? icon,
      TextInputType? keyboardType,
      String? Function(String?)? validator,
      List<MaskTextInputFormatter>? inputFormatters}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(fontSize: 14),
        validator: validator ?? (v) => v!.isEmpty ? "Campo obrigatório" : null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon:
              icon != null ? Icon(icon, size: 18, color: Colors.grey) : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildDaysSelector() {
    final days = [
      {'v': 1, 'l': 'Seg'},
      {'v': 2, 'l': 'Ter'},
      {'v': 3, 'l': 'Qua'},
      {'v': 4, 'l': 'Qui'},
      {'v': 5, 'l': 'Sex'},
      {'v': 6, 'l': 'Sáb'},
      {'v': 7, 'l': 'Dom'}
    ];
    return Wrap(
      spacing: 8,
      children: days.map((d) {
        bool isS = _workDays.contains(d['v']);
        return FilterChip(
          label: Text(d['l'] as String),
          selected: isS,
          onSelected: (val) => setState(() => val
              ? _workDays.add(d['v'] as int)
              : _workDays.remove(d['v'] as int)),
          selectedColor: AppColors.primaryPurple.withValues(alpha: 0.2),
          labelStyle: TextStyle(
              color: isS ? AppColors.primaryPurple : Colors.black,
              fontWeight: isS ? FontWeight.bold : FontWeight.normal),
          checkmarkColor: AppColors.primaryPurple,
        );
      }).toList(),
    );
  }

  Widget _buildServicesSelector() {
    if (_shopId == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.orange[50], borderRadius: BorderRadius.circular(8)),
        child: Row(children: const [
          SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.orange)),
          SizedBox(width: 10),
          Text("Carregando catálogo de serviços...",
              style: TextStyle(color: Colors.orange, fontSize: 12))
        ]),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: sb.Supabase.instance.client
          .from('services')
          .stream(primaryKey: ['id'])
          .eq('shop_id', _shopId!)
          .order('name'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();

        if (snapshot.data!.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: Colors.red),
                SizedBox(width: 10),
                Expanded(
                    child: Text("Nenhum serviço cadastrado na loja ainda.",
                        style: TextStyle(fontSize: 12, color: Colors.red))),
              ],
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: snapshot.data!.map((data) {
              String sId = data['id'];
              String nome = data['name'] ?? "Serviço";
              bool isSelected = _selectedServices.contains(sId);

              return FilterChip(
                label: Text(nome),
                selected: isSelected,
                selectedColor: AppColors.primaryPurple.withValues(alpha: 0.2),
                checkmarkColor: AppColors.primaryPurple,
                labelStyle: TextStyle(
                    color:
                        isSelected ? AppColors.primaryPurple : Colors.black87,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal),
                onSelected: (bool selected) {
                  setState(() {
                    if (selected) {
                      _selectedServices.add(sId);
                    } else {
                      _selectedServices.remove(sId);
                    }
                  });
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildFolgasList() {
    if (_folgas.isEmpty) return const SizedBox();
    return Column(
      children: _folgas.asMap().entries.map((e) {
        final start = e.value['start'] is String 
            ? DateTime.parse(e.value['start'])
            : (e.value['start'] as DateTime);
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_busy, color: Colors.red, size: 20),
          title: Text(e.value['notes'],
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          subtitle: Text(DateFormat('dd/MM/yyyy').format(start),
              style: const TextStyle(fontSize: 11)),
          trailing: IconButton(
              icon: const Icon(Icons.close, size: 16, color: Colors.red),
              onPressed: () => setState(() => _folgas.removeAt(e.key))),
        );
      }).toList(),
    );
  }
}
