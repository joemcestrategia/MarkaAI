import 'package:flutter/foundation.dart';
import 'dart:io' if (dart.library.html) 'package:markaai/core/utils/io_stub.dart' as io;
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
import '../../core/utils/work_schedule.dart';
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
  final _comissaoController = TextEditingController(text: "0");
  final _cargoController = TextEditingController(); // Cargo ou Especialidade

  // Jornada por dia da semana (1=Seg ... 7=Dom).
  // Cada dia: enabled + start + end + (opcional) pausa única (start/end).
  final Map<int, _DaySched> _daySchedule = {
    for (var d = 1; d <= 7; d++)
      d: _DaySched(
        enabled: d <= 6,
        start: '08:00',
        end: '18:00',
        breakStart: null,
        breakEnd: null,
      ),
  };

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

    Map<String, dynamic>? data = widget.employeeToEdit;

    // Ao editar, sempre busca a linha fresca do DB para garantir que campos
    // como `work_schedule` estejam atualizados (a referência cacheada pode
    // ser anterior à última gravação ou vir de um stream sem o JSONB).
    if (data != null && data['id'] != null) {
      try {
        final fresh = await sb.Supabase.instance.client
            .from('employees')
            .select()
            .eq('id', data['id'])
            .maybeSingle();
        if (fresh != null) {
          data = fresh;
          debugPrint(
              '[employee_register] loaded fresh row id=${data['id']} '
              'work_schedule=${data['work_schedule']}');
        }
      } catch (e) {
        debugPrint('[employee_register] failed to refetch employee: $e');
      }
    }

    if (mounted) {
      setState(() {
        _shopId = sId;

        if (data != null) {
          _nameController.text = data['name'] ?? "";
          _emailController.text = data['email'] ?? "";
          _backupEmailController.text =
              data['backup_email'] ?? ""; // 🆕 Carrega email de backup
          _phoneController.text = data['phone'] ?? "";
          _existingPhotoUrl = data['photo_url'];
          _loadScheduleFromEmployee(data);
          _comissaoController.text = (data['commission_percent'] != null)
              ? data['commission_percent'].toString()
              : '0';
          _cargoController.text = data['role'] ?? data['position'] ?? "";
          if (data['services_ids'] != null) {
            _selectedServices = List<String>.from(data['services_ids']);
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

    final scheduleErr = _validateSchedule();
    if (scheduleErr != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(scheduleErr)));
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

      // work_schedule é a fonte de verdade. O trigger SQL
      // (`employees_sync_legacy_schedule_fn`) recalcula work_days,
      // work_start/work_end e start_time/end_time automaticamente.
      final wsJson = _buildWorkScheduleJson();
      final employeeData = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'backup_email':
            _backupEmailController.text.trim(), // 🆕 Salva email de backup
        'phone': _phoneController.text.trim(),
        'photo_url': photoUrl,
        'services_ids': _selectedServices,
        'work_schedule': wsJson,
        'breaks': _folgas,
        'shop_id': _shopId,
        'commission_percent':
            double.tryParse(_comissaoController.text.replaceAll(',', '.')) ??
                0.0,
        'role': _cargoController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      debugPrint(
          '[employee_register] saving work_schedule=${employeeData['work_schedule']}');

      Map<String, dynamic>? saved;
      if (widget.employeeToEdit == null) {
        employeeData['id'] = const Uuid().v4(); // 🆕 Gera ID para evitar erro de null value
        final res = await sb.Supabase.instance.client
            .from('employees')
            .insert(employeeData)
            .select()
            .maybeSingle();
        saved = res;
      } else {
        final res = await sb.Supabase.instance.client
            .from('employees')
            .update(employeeData)
            .eq('id', widget.employeeToEdit!['id'])
            .select()
            .maybeSingle();
        saved = res;
      }
      debugPrint(
          '[employee_register] saved row work_schedule=${saved?['work_schedule']}');

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

    return DefaultTabController(
      length: 3,
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            // HEADER
            Container(
              height: 60,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: Colors.grey[200]!))),
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

            // ABAS
            Material(
              color: Colors.white,
              child: TabBar(
                labelColor: AppColors.primaryPurple,
                unselectedLabelColor: Colors.grey,
                indicatorColor: AppColors.primaryPurple,
                labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: const [
                  Tab(icon: Icon(Icons.person_outline, size: 18), text: 'Perfil'),
                  Tab(
                      icon: Icon(Icons.calendar_today_outlined, size: 18),
                      text: 'Jornada'),
                  Tab(icon: Icon(Icons.spa_outlined, size: 18), text: 'Serviços'),
                ],
              ),
            ),

            // CONTEÚDO DAS ABAS
            Expanded(
              child: Form(
                key: _formKey,
                child: TabBarView(
                  children: [
                    _buildProfileTab(),
                    _buildScheduleTab(),
                    _buildServicesTab(),
                  ],
                ),
              ),
            ),

            // RODAPÉ
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border:
                      Border(top: BorderSide(color: Colors.grey[100]!))),
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
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Aba: Perfil ───────────────────────────────────────────────────────────

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
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
                                    ? NetworkImage(_imageFile!.path)
                                        as ImageProvider
                                    : FileImage(io.File(_imageFile!.path)
                                            as dynamic)
                                        as ImageProvider)
                            : (_existingPhotoUrl != null
                                    ? CachedNetworkImageProvider(
                                        _existingPhotoUrl!)
                                    : null)
                                as ImageProvider?,
                        child: (_imageFile == null &&
                                _existingPhotoUrl == null)
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
                                border: Border.all(
                                    color: Colors.white, width: 2),
                              ),
                              child: const Icon(Icons.crop,
                                  size: 14, color: Colors.white),
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
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primaryPurple),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text("${(_uploadProgress * 100).toInt()}%",
                      style: const TextStyle(fontSize: 10)),
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
              if (v == null || v.trim().isEmpty) return null;
              return v.length < 14 ? "Telefone inválido" : null;
            },
          ),
          _buildField("Comissão (%)", _comissaoController,
              icon: Icons.percent,
              keyboardType: TextInputType.number,
              validator: (v) => null),

          if (widget.employeeToEdit != null) ...[
            const SizedBox(height: 30),
            const Divider(),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: _deleteEmployee,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: const Text("Remover da Equipe",
                    style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Aba: Jornada ──────────────────────────────────────────────────────────

  Widget _buildScheduleTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle("Dias de Trabalho"),
          const Text(
            "Habilite os dias em que o profissional atende e configure o horário de cada um. Você pode adicionar uma pausa (ex: almoço) opcional.",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          for (var d = 1; d <= 7; d++) _buildDayScheduleCard(d),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle("Ausências (folgas, férias)"),
              TextButton.icon(
                  onPressed: _showAddFolgaDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text("Add Folga",
                      style: TextStyle(fontSize: 12))),
            ],
          ),
          const Text(
            "Bloqueia dias específicos sem precisar mexer na configuração semanal.",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          _buildFolgasList(),
        ],
      ),
    );
  }

  // ─── Aba: Serviços ─────────────────────────────────────────────────────────

  Widget _buildServicesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle("Especialidades & Serviços"),
          const Text(
              "Marque os serviços que este profissional realiza. Apenas estes serão oferecidos quando o cliente escolher este profissional.",
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          _buildServicesSelector(),
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

  // ─── Helpers de Jornada por dia ────────────────────────────────────────────

  void _loadScheduleFromEmployee(Map<String, dynamic> data) {
    final ws = WorkSchedule.fromEmployeeRow(data);
    for (var d = 1; d <= 7; d++) {
      final ds = ws.forWeekday(d);
      if (ds != null) {
        _daySchedule[d] = _DaySched(
          enabled: true,
          start: ds.start,
          end: ds.end,
          breakStart: ds.breakInterval?.start,
          breakEnd: ds.breakInterval?.end,
        );
      } else {
        _daySchedule[d] = _DaySched(
          enabled: false,
          start: '08:00',
          end: '18:00',
          breakStart: null,
          breakEnd: null,
        );
      }
    }
  }

  Map<String, dynamic> _buildWorkScheduleJson() {
    final out = <String, dynamic>{};
    for (var d = 1; d <= 7; d++) {
      final s = _daySchedule[d]!;
      if (!s.enabled) {
        out['$d'] = {'enabled': false};
      } else {
        out['$d'] = {
          'enabled': true,
          'start': s.start,
          'end': s.end,
          'break': (s.breakStart != null && s.breakEnd != null)
              ? {'start': s.breakStart, 'end': s.breakEnd}
              : null,
        };
      }
    }
    return out;
  }

  /// Validações de jornada antes do save. Retorna mensagem de erro ou null.
  String? _validateSchedule() {
    bool anyEnabled = false;
    for (var d = 1; d <= 7; d++) {
      final s = _daySchedule[d]!;
      if (!s.enabled) continue;
      anyEnabled = true;
      final sm = _hhmmMin(s.start);
      final em = _hhmmMin(s.end);
      if (sm == null || em == null) {
        return 'Horário inválido em ${_dayLabel(d)}.';
      }
      if (sm >= em) {
        return 'Em ${_dayLabel(d)}, o início deve ser antes do fim.';
      }
      if (s.breakStart != null && s.breakEnd != null) {
        final bs = _hhmmMin(s.breakStart!);
        final be = _hhmmMin(s.breakEnd!);
        if (bs == null || be == null) {
          return 'Pausa inválida em ${_dayLabel(d)}.';
        }
        if (bs >= be) {
          return 'Pausa de ${_dayLabel(d)}: início deve ser antes do fim.';
        }
        if (bs < sm || be > em) {
          return 'Pausa de ${_dayLabel(d)} deve estar dentro do expediente.';
        }
      }
    }
    if (!anyEnabled) {
      return 'Selecione pelo menos um dia de trabalho.';
    }
    return null;
  }

  Future<TimeOfDay?> _pickTime(BuildContext context, String? initial) async {
    final init = initial != null ? _hhmmMin(initial) : null;
    final t = await showTimePicker(
      context: context,
      initialTime: init != null
          ? TimeOfDay(hour: init ~/ 60, minute: init % 60)
          : const TimeOfDay(hour: 8, minute: 0),
    );
    return t;
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static int? _hhmmMin(String s) {
    final p = s.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  static String _dayLabel(int d) {
    const labels = {
      1: 'Segunda',
      2: 'Terça',
      3: 'Quarta',
      4: 'Quinta',
      5: 'Sexta',
      6: 'Sábado',
      7: 'Domingo',
    };
    return labels[d] ?? '';
  }

  void _applyToAllWeekdays(int sourceDay) {
    final src = _daySchedule[sourceDay]!;
    setState(() {
      for (var d = 1; d <= 5; d++) {
        if (d == sourceDay) continue;
        _daySchedule[d] = _DaySched(
          enabled: true,
          start: src.start,
          end: src.end,
          breakStart: src.breakStart,
          breakEnd: src.breakEnd,
        );
      }
    });
  }

  Widget _buildDayScheduleCard(int day) {
    final s = _daySchedule[day]!;
    final hasBreak = s.breakStart != null && s.breakEnd != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: s.enabled ? Colors.white : Colors.grey[50],
        border: Border.all(
          color: s.enabled
              ? AppColors.primaryPurple.withValues(alpha: 0.25)
              : Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 90,
                child: Text(
                  _dayLabel(day),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              Switch(
                value: s.enabled,
                activeColor: AppColors.primaryPurple,
                onChanged: (v) => setState(() => s.enabled = v),
              ),
              const Spacer(),
              if (s.enabled && day <= 5)
                TextButton(
                  onPressed: () => _applyToAllWeekdays(day),
                  child: const Text('Aplicar a Seg–Sex',
                      style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          if (s.enabled) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _timeField(
                    label: 'Início',
                    value: s.start,
                    onTap: () async {
                      final t = await _pickTime(context, s.start);
                      if (t != null) setState(() => s.start = _fmtTime(t));
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _timeField(
                    label: 'Fim',
                    value: s.end,
                    onTap: () async {
                      final t = await _pickTime(context, s.end);
                      if (t != null) setState(() => s.end = _fmtTime(t));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Checkbox(
                  value: hasBreak,
                  activeColor: AppColors.primaryPurple,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        s.breakStart = '12:00';
                        s.breakEnd = '13:00';
                      } else {
                        s.breakStart = null;
                        s.breakEnd = null;
                      }
                    });
                  },
                ),
                const Text('Pausa (almoço)', style: TextStyle(fontSize: 12)),
              ],
            ),
            if (hasBreak)
              Row(
                children: [
                  Expanded(
                    child: _timeField(
                      label: 'Pausa início',
                      value: s.breakStart!,
                      onTap: () async {
                        final t = await _pickTime(context, s.breakStart);
                        if (t != null) {
                          setState(() => s.breakStart = _fmtTime(t));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _timeField(
                      label: 'Pausa fim',
                      value: s.breakEnd!,
                      onTap: () async {
                        final t = await _pickTime(context, s.breakEnd);
                        if (t != null) {
                          setState(() => s.breakEnd = _fmtTime(t));
                        }
                      },
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _timeField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          prefixIcon:
              const Icon(Icons.access_time, size: 16, color: Colors.grey),
        ),
        child: Text(value, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

class _DaySched {
  bool enabled;
  String start;
  String end;
  String? breakStart;
  String? breakEnd;
  _DaySched({
    required this.enabled,
    required this.start,
    required this.end,
    required this.breakStart,
    required this.breakEnd,
  });
}
