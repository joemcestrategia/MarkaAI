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
import 'package:table_calendar/table_calendar.dart';
import '../backup/calendar_backup_page.dart';

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

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _cargoController = TextEditingController(); // Cargo ou Especialidade
  double _comissaoValue = 0.0;

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

  // Estado
  io.File? _imageFile;
  String? _existingPhotoUrl;
  String? _shopId;

  List<String> _selectedServices = [];
  List<Map<String, dynamic>> _folgas = [];

  bool _isSaving = false;
  bool _isDeleting = false;
  double _uploadProgress = 0.0;
  String? _currentEmployeeId;

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
          _existingPhotoUrl = data['photo_url'];
          _loadScheduleFromEmployee(data);
          
          if (data['commission_percent'] != null) {
            _comissaoValue = double.tryParse(data['commission_percent'].toString()) ?? 0.0;
            if (_comissaoValue > 100) _comissaoValue = 100;
            if (_comissaoValue < 0) _comissaoValue = 0;
          }
          
          _cargoController.text = data['role'] ?? data['position'] ?? "";
          if (data['services_ids'] != null) {
            _selectedServices = List<String>.from(data['services_ids']);
          }

          if (data['breaks'] != null) {
            _folgas = List<Map<String, dynamic>>.from(data['breaks']);
          }
          
          _currentEmployeeId = data['id'];
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

  Future<DateTimeRange?> _showCustomDateRangePicker(BuildContext context) async {
    DateTime? rangeStart;
    DateTime? rangeEnd;
    DateTime focusedDay = DateTime.now();
    
    return await showDialog<DateTimeRange>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              backgroundColor: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Selecione o Período",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.deepPurple),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Toque no dia de início e no dia de término da folga.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 380,
                      width: 320,
                      child: TableCalendar(
                        firstDay: DateTime.now().subtract(const Duration(days: 1)),
                        lastDay: DateTime.now().add(const Duration(days: 365)),
                        focusedDay: focusedDay,
                        rangeStartDay: rangeStart,
                        rangeEndDay: rangeEnd,
                        rangeSelectionMode: RangeSelectionMode.toggledOn,
                        locale: 'pt_BR',
                        headerStyle: const HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          leftChevronIcon: Icon(Icons.chevron_left, color: AppColors.primaryPurple),
                          rightChevronIcon: Icon(Icons.chevron_right, color: AppColors.primaryPurple),
                        ),
                        calendarStyle: CalendarStyle(
                          rangeHighlightColor: AppColors.primaryPurple.withValues(alpha: 0.15),
                          rangeStartDecoration: const BoxDecoration(
                            color: AppColors.primaryPurple,
                            shape: BoxShape.circle,
                          ),
                          rangeEndDecoration: const BoxDecoration(
                            color: AppColors.primaryPurple,
                            shape: BoxShape.circle,
                          ),
                          withinRangeTextStyle: const TextStyle(color: AppColors.primaryPurple),
                          todayDecoration: BoxDecoration(
                            color: Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primaryPurple),
                          ),
                          todayTextStyle: const TextStyle(color: AppColors.primaryPurple, fontWeight: FontWeight.bold),
                          selectedDecoration: const BoxDecoration(
                            color: AppColors.primaryPurple,
                            shape: BoxShape.circle,
                          ),
                        ),
                        onRangeSelected: (start, end, focused) {
                          setState(() {
                            rangeStart = start;
                            rangeEnd = end;
                            focusedDay = focused;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("CANCELAR", style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryPurple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          onPressed: () {
                            if (rangeStart != null) {
                              Navigator.pop(context, DateTimeRange(start: rangeStart!, end: rangeEnd ?? rangeStart!));
                            }
                          },
                          child: const Text("CONFIRMAR", style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }
    );
  }

  Future<void> _showAddFolgaDialog({int? editIndex}) async {
    Map<String, dynamic>? existingFolga;
    if (editIndex != null) {
      existingFolga = _folgas[editIndex];
    }

    DateTimeRange? pickedRange;
    
    if (existingFolga != null) {
       final st = existingFolga['start'] is String ? DateTime.parse(existingFolga['start']) : existingFolga['start'];
       final ed = existingFolga['end'] is String ? DateTime.parse(existingFolga['end']) : existingFolga['end'];
       pickedRange = DateTimeRange(start: st, end: ed);
    } else {
      pickedRange = await _showCustomDateRangePicker(context);
    }

    if (pickedRange != null) {
      if (!mounted) return;
      String obs = existingFolga?['notes'] ?? "";
      final obsController = TextEditingController(text: obs);
      
      bool isPartial = existingFolga?['type'] == 'partial';
      TimeOfDay partialStart = const TimeOfDay(hour: 8, minute: 0);
      TimeOfDay partialEnd = const TimeOfDay(hour: 12, minute: 0);

      if (isPartial && existingFolga != null) {
        if (existingFolga['start_time'] != null) {
          final parts = existingFolga['start_time'].split(':');
          if (parts.length >= 2) partialStart = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
        if (existingFolga['end_time'] != null) {
          final parts = existingFolga['end_time'].split(':');
          if (parts.length >= 2) partialEnd = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
        }
      }

      bool applyToAll = false;

      await showDialog(
          context: context,
          builder: (context) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  title: Text(editIndex != null ? "Editar Folga" : "Configurar Folga",
                      style: const TextStyle(fontSize: 16)),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                            controller: obsController,
                            decoration: const InputDecoration(
                                labelText: "Motivo",
                                hintText: "Ex: Férias, Médico...")),
                        const SizedBox(height: 16),
                        const Text("Tipo de folga",
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setDialogState(() => isPartial = false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: !isPartial
                                        ? AppColors.primaryPurple
                                            .withValues(alpha: 0.1)
                                        : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: !isPartial
                                          ? AppColors.primaryPurple
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(Icons.calendar_today,
                                          size: 20,
                                          color: !isPartial
                                              ? AppColors.primaryPurple
                                              : Colors.grey),
                                      const SizedBox(height: 4),
                                      Text("Dia Inteiro",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: !isPartial
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: !isPartial
                                                ? AppColors.primaryPurple
                                                : Colors.grey,
                                          )),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setDialogState(() => isPartial = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: isPartial
                                        ? AppColors.primaryPurple
                                            .withValues(alpha: 0.1)
                                        : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isPartial
                                          ? AppColors.primaryPurple
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Icon(Icons.access_time,
                                          size: 20,
                                          color: isPartial
                                              ? AppColors.primaryPurple
                                              : Colors.grey),
                                      const SizedBox(height: 4),
                                      Text("Período",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: isPartial
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isPartial
                                                ? AppColors.primaryPurple
                                                : Colors.grey,
                                          )),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isPartial) ...[
                          const SizedBox(height: 16),
                          const Text("Horário da folga",
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final t = await showTimePicker(
                                      context: context,
                                      initialTime: partialStart,
                                    );
                                    if (t != null) {
                                      setDialogState(() => partialStart = t);
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: "Início",
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      prefixIcon: const Icon(
                                          Icons.access_time,
                                          size: 16,
                                          color: Colors.grey),
                                    ),
                                    child: Text(_fmtTime(partialStart),
                                        style: const TextStyle(
                                            fontSize: 13)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InkWell(
                                  onTap: () async {
                                    final t = await showTimePicker(
                                      context: context,
                                      initialTime: partialEnd,
                                    );
                                    if (t != null) {
                                      setDialogState(() => partialEnd = t);
                                    }
                                  },
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: "Fim",
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      prefixIcon: const Icon(
                                          Icons.access_time,
                                          size: 16,
                                          color: Colors.grey),
                                    ),
                                    child: Text(_fmtTime(partialEnd),
                                        style: const TextStyle(
                                            fontSize: 13)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (editIndex == null) ...[
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text("Aplicar folga a toda a equipe", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            subtitle: const Text("Isso replicará a mesma folga para os demais funcionários ao salvar.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                            value: applyToAll,
                            activeColor: AppColors.primaryPurple,
                            onChanged: (val) {
                              if (val != null) setDialogState(() => applyToAll = val);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
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
                      child: Text(editIndex != null ? "Atualizar" : "Adicionar",
                          style: const TextStyle(color: Colors.white)),
                    )
                  ],
                );
              },
            );
          });

      if (obs.isNotEmpty) {
        setState(() {
          final folgaData = <String, dynamic>{
            'start': pickedRange!.start.toIso8601String(),
            'end': (isPartial ? pickedRange.end : pickedRange.end.add(const Duration(hours: 23, minutes: 59)))
                .toIso8601String(),
            'notes': obs.isEmpty && existingFolga != null ? existingFolga['notes'] : obs,
          };

          if (isPartial) {
            folgaData['type'] = 'partial';
            folgaData['start_time'] =
                '${partialStart.hour.toString().padLeft(2, '0')}:${partialStart.minute.toString().padLeft(2, '0')}';
            folgaData['end_time'] =
                '${partialEnd.hour.toString().padLeft(2, '0')}:${partialEnd.minute.toString().padLeft(2, '0')}';
          } else {
            folgaData['type'] = 'full_day';
          }

          if (applyToAll) {
            folgaData['apply_to_all'] = true;
          }

          if (editIndex != null) {
            _folgas[editIndex] = folgaData;
          } else {
            _folgas.add(folgaData);
          }

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
        'photo_url': photoUrl,
        'services_ids': _selectedServices,
        'work_schedule': wsJson,
        'breaks': _folgas,
        'shop_id': _shopId,
        'commission_percent': _comissaoValue,
        'role': _cargoController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      debugPrint(
          '[employee_register] saving work_schedule=${employeeData['work_schedule']}');

      Map<String, dynamic>? saved;
      String targetId;

      if (widget.employeeToEdit == null && _currentEmployeeId == null) {
        targetId = const Uuid().v4();
        employeeData['id'] = targetId; // 🆕 Gera ID para evitar erro de null value
        final res = await sb.Supabase.instance.client
            .from('employees')
            .insert(employeeData)
            .select()
            .maybeSingle();
        saved = res;
      } else {
        targetId = _currentEmployeeId ?? widget.employeeToEdit!['id'];
        final res = await sb.Supabase.instance.client
            .from('employees')
            .update(employeeData)
            .eq('id', targetId)
            .select()
            .maybeSingle();
        saved = res;
      }
      debugPrint(
          '[employee_register] saved row work_schedule=${saved?['work_schedule']}');

      // 🆕 Aplicar folgas para toda a equipe
      final folgasToApplyAll = _folgas.where((f) => f['apply_to_all'] == true).toList();
      if (folgasToApplyAll.isNotEmpty) {
        try {
          final otherEmployees = await sb.Supabase.instance.client
              .from('employees')
              .select('id, breaks')
              .eq('shop_id', _shopId!)
              .neq('id', targetId);

          for (var other in otherEmployees) {
            List<dynamic> otherBreaks = other['breaks'] ?? [];
            List<Map<String, dynamic>> newBreaks = List<Map<String, dynamic>>.from(otherBreaks);
            
            for (var folga in folgasToApplyAll) {
              // Limpa a flag e evita duplicação exata por segurança
              final cleanFolga = Map<String, dynamic>.from(folga)..remove('apply_to_all');
              newBreaks.add(cleanFolga);
            }
            
            await sb.Supabase.instance.client
                .from('employees')
                .update({'breaks': newBreaks})
                .eq('id', other['id']);
          }
        } catch (e) {
          debugPrint('[employee_register] Erro ao aplicar folgas em lote: $e');
        }
        
        // Remove a flag de apply_to_all do funcionário atual para o futuro
        for (var f in _folgas) {
          f.remove('apply_to_all');
        }
        await sb.Supabase.instance.client
            .from('employees')
            .update({'breaks': _folgas})
            .eq('id', targetId);
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

    return DefaultTabController(
      length: 4,
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            // HEADER MODERNO (Exibido apenas no Desktop/Tablet)
            if (MediaQuery.of(context).size.width >= 850)
              Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryPurple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            widget.employeeToEdit != null ? Icons.edit_note_rounded : Icons.person_add_rounded,
                            color: AppColors.primaryPurple,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          widget.employeeToEdit != null
                              ? "Editar Membro"
                              : "Novo Membro",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.deepPurple,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 24, color: AppColors.textSecondary),
                      onPressed: widget.onClose,
                      splashRadius: 24,
                    ),
                  ],
                ),
              ),

            // ABAS ESTILIZADAS
            Material(
              color: Colors.white,
              elevation: 0,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                ),
                child: TabBar(
                  labelColor: AppColors.primaryPurple,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.primaryPurple,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  tabs: const [
                    Tab(icon: Icon(Icons.person_outline_rounded, size: 20), text: 'Perfil'),
                    Tab(icon: Icon(Icons.schedule_rounded, size: 20), text: 'Jornada'),
                    Tab(icon: Icon(Icons.event_busy_rounded, size: 20), text: 'Folgas'),
                    Tab(icon: Icon(Icons.spa_rounded, size: 20), text: 'Serviços'),
                  ],
                ),
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
                    _buildFolgasTab(),
                    _buildServicesTab(),
                  ],
                ),
              ),
            ),

            // RODAPÉ
            SafeArea(
              bottom: true,
              child: Container(
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

          _sectionTitle("Dados Pessoais"),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // FOTO
              Padding(
                padding: const EdgeInsets.only(right: 16, top: 4),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: AppColors.surface,
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
                                ? const Icon(Icons.add_a_photo_rounded,
                                    size: 24, color: AppColors.textSecondary)
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
                        width: 80,
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
              
              // INPUTS DE NOME E CARGO
              Expanded(
                child: Column(
                  children: [
                    _buildField("Nome Completo", _nameController,
                        icon: Icons.person_outline, maxLength: 150),
                    _buildField(
                        "Cargo / Especialidade",
                        _cargoController,
                        icon: Icons.work_outline, maxLength: 100),
                  ],
                ),
              ),
            ],
          ),
          _sectionTitle("Comissão"),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Porcentagem de comissão",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryPurple.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "${_comissaoValue.toInt()}%",
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryPurple, fontSize: 15),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.primaryPurple,
                    inactiveTrackColor: AppColors.primaryPurple.withValues(alpha: 0.2),
                    thumbColor: AppColors.primaryPurple,
                    overlayColor: AppColors.primaryPurple.withValues(alpha: 0.1),
                    valueIndicatorColor: AppColors.primaryPurple,
                    trackHeight: 6,
                  ),
                  child: Slider(
                    value: _comissaoValue,
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: "${_comissaoValue.toInt()}%",
                    onChanged: (val) {
                      setState(() {
                        _comissaoValue = val;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          if (widget.employeeToEdit != null) ...[
            _sectionTitle("Integrações"),
            Container(
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[100]!),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, color: Colors.blue, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Google Calendar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A8A))),
                        Text("Sincronizar agendamentos", style: TextStyle(fontSize: 12, color: Colors.blue[800])),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 36,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CalendarBackupPage(
                              isOwner: false,
                              employeeId: widget.employeeToEdit!['id'],
                              shopId: _shopId,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blue[700],
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Text("Configurar", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Center(
              child: TextButton.icon(
                onPressed: _deleteEmployee,
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                label: const Text("Remover da Equipe",
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  backgroundColor: Colors.red.withValues(alpha: 0.05),
                ),
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
        ],
      ),
    );
  }

  // ─── Aba: Folgas ────────────────────────────────────────────────────────────

  Widget _buildFolgasTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            "Bloqueia dias ou períodos específicos sem precisar mexer na configuração semanal. "
            "Use 'Período' para bloquear apenas parte do dia.",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          _buildFolgasList(),
          if (_folgas.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.event_available,
                      size: 40, color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  Text("Nenhuma folga configurada",
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[500])),
                  const SizedBox(height: 4),
                  Text(
                      "Toque em 'Add Folga' para bloquear dias ou períodos",
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[400])),
                ],
              ),
            ),
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
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.primaryPurple,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.deepPurple,
              letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller,
      {IconData? icon,
      TextInputType? keyboardType,
      String? Function(String?)? validator,
      List<MaskTextInputFormatter>? inputFormatters,
      int? maxLength}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        validator: (v) {
          if (validator != null) {
            final result = validator(v);
            if (result != null) return result;
          }
          if (v == null || v.isEmpty) return "Campo obrigatório";
          if (maxLength != null && v.length > maxLength!) return "Máximo $maxLength caracteres";
          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.8)),
          prefixIcon: icon != null ? Icon(icon, size: 20, color: AppColors.primaryPurple.withValues(alpha: 0.7)) : null,
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primaryPurple, width: 1.5),
          ),
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
        final end = e.value['end'] is String 
            ? DateTime.parse(e.value['end'])
            : (e.value['end'] as DateTime);
        final folgaType =
            (e.value['type']?.toString() ?? 'full_day').toLowerCase();
        final isPartial = folgaType == 'partial';

        String dateStr;
        if (start.year == end.year &&
            start.month == end.month &&
            start.day == end.day) {
          dateStr = DateFormat('dd/MM/yyyy').format(start);
        } else {
          dateStr =
              '${DateFormat('dd/MM').format(start)} — ${DateFormat('dd/MM/yyyy').format(end)}';
        }

        String subtitleText = dateStr;
        if (isPartial) {
          final stTime = e.value['start_time'] ?? '??';
          final etTime = e.value['end_time'] ?? '??';
          subtitleText = '$dateStr • $stTime–$etTime';
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isPartial
                ? Colors.orange.withValues(alpha: 0.06)
                : Colors.red.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isPartial
                  ? Colors.orange.withValues(alpha: 0.3)
                  : Colors.red.withValues(alpha: 0.3),
            ),
          ),
          child: ListTile(
            onTap: () => _showAddFolgaDialog(editIndex: e.key),
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            leading: Icon(
              isPartial ? Icons.access_time : Icons.event_busy,
              color: isPartial ? Colors.orange : Colors.red,
              size: 20,
            ),
            title: Text(e.value['notes'] ?? 'Folga',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
            subtitle: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isPartial
                        ? Colors.orange.withValues(alpha: 0.15)
                        : Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isPartial ? 'Período' : 'Dia Inteiro',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: isPartial ? Colors.orange[800] : Colors.red[800],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(subtitleText,
                      style: const TextStyle(fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            trailing: IconButton(
                icon: const Icon(Icons.close, size: 16, color: Colors.red),
                onPressed: () => setState(() => _folgas.removeAt(e.key))),
          ),
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
