import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/session_service.dart';

class EmployeeRegisterPage extends StatefulWidget {
  final DocumentSnapshot? employeeToEdit;
  final VoidCallback onClose;

  const EmployeeRegisterPage(
      {super.key, this.employeeToEdit, required this.onClose});

  @override
  State<EmployeeRegisterPage> createState() => _EmployeeRegisterPageState();
}

class _EmployeeRegisterPageState extends State<EmployeeRegisterPage> {
  final _formKey = GlobalKey<FormState>();

  // Controladores (HORÃRIO CORRIGIDO PARA 08:00)
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _backupEmailController =
      TextEditingController(); // ðŸ†• Email para backup Google Calendar
  final _phoneController = TextEditingController();
  final _startWorkController = TextEditingController(text: "08:00");
  final _endWorkController = TextEditingController(text: "18:00");
  final _comissaoController = TextEditingController(text: "0");

  // Máscara de telefone
  final phoneMask = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {"#": RegExp(r'[0-9]')},
  );

  // Estado
  File? _imageFile;
  String? _existingPhotoUrl;
  String? _shopId;

  List<String> _selectedServices = [];
  List<int> _workDays = [1, 2, 3, 4, 5, 6];
  List<Map<String, dynamic>> _folgas = [];

  bool _isSaving = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    String? sId = await SessionService.getShopId();

    if (sId == null || sId.isEmpty) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          sId = doc.data()?['shopId'];
        }
      }
    }

    if (mounted) {
      setState(() {
        _shopId = sId;

        if (widget.employeeToEdit != null) {
          final data = widget.employeeToEdit!.data() as Map<String, dynamic>;

          _nameController.text = data['nome'] ?? "";
          _emailController.text = data['email'] ?? "";
          _backupEmailController.text =
              data['backup_email'] ?? ""; // ðŸ†• Carrega email de backup
          _phoneController.text = data['telefone'] ?? "";
          _startWorkController.text = data['horario_inicio'] ?? "08:00";
          _endWorkController.text = data['horario_fim'] ?? "18:00";
          _existingPhotoUrl = data['foto_url'];
          _comissaoController.text = (data['comissao_percent'] != null)
              ? data['comissao_percent'].toString()
              : '0';
          if (data['servicos_habilidade'] != null) {
            _selectedServices = List<String>.from(data['servicos_habilidade']);
          }

          if (data['dias_trabalho'] != null) {
            _workDays = List<int>.from(data['dias_trabalho']);
          }

          if (data['folgas'] != null) {
            _folgas = List<Map<String, dynamic>>.from(data['folgas']);
          }
        }
      });
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _imageFile = File(picked.path));
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
                  decoration: const InputDecoration(
                      hintText: "Ex: Férias, Médico...")),
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
            'inicio': Timestamp.fromDate(pickedRange.start),
            'fim': Timestamp.fromDate(
                pickedRange.end.add(const Duration(hours: 23, minutes: 59))),
            'obs': obs,
          });
          _folgas.sort((a, b) =>
              (a['inicio'] as Timestamp).compareTo(b['inicio'] as Timestamp));
        });
      }
    }
  }

  Future<void> _deleteEmployee() async {
    bool confirm = await showDialog(
            context: context,
            builder: (context) => AlertDialog(
                  title: const Text("Excluir Membro?"),
                  content: const Text(
                      "O funcionário será removido da lista ativa."),
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
        await widget.employeeToEdit!.reference.delete();
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
      String? photoUrl = _existingPhotoUrl;

      if (_imageFile != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('employees/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(_imageFile!);
        photoUrl = await ref.getDownloadURL();
      }

      final employeeData = {
        'nome': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'backup_email':
            _backupEmailController.text.trim(), // ðŸ†• Salva email de backup
        'telefone': _phoneController.text.trim(),
        'horario_inicio': _startWorkController.text,
        'horario_fim': _endWorkController.text,
        'foto_url': photoUrl,
        'servicos_habilidade': _selectedServices,
        'dias_trabalho': _workDays,
        'folgas': _folgas,
        'shopId': _shopId,
        'tipo': 'funcionario',
        'comissao_percent':
            double.tryParse(_comissaoController.text.replaceAll(',', '.')) ??
                0.0,
        'atualizado_em': FieldValue.serverTimestamp(),
      };

      if (widget.employeeToEdit == null) {
        await FirebaseFirestore.instance
            .collection('employees')
            .add(employeeData);
      } else {
        await widget.employeeToEdit!.reference.update(employeeData);
      }

      widget.onClose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Membro salvo com sucesso!"),
            backgroundColor: Colors.green));
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
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: CircleAvatar(
                          radius: 45,
                          backgroundColor: Colors.grey[100],
                          backgroundImage: _imageFile != null
                              ? FileImage(_imageFile!)
                              : (_existingPhotoUrl != null
                                  ? NetworkImage(_existingPhotoUrl!)
                                  : null) as ImageProvider?,
                          child:
                              (_imageFile == null && _existingPhotoUrl == null)
                                  ? const Icon(Icons.camera_alt,
                                      size: 24, color: Colors.grey)
                                  : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    _sectionTitle("Dados Pessoais"),
                    _buildField("Nome Completo", _nameController,
                        icon: Icons.person_outline),
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
                      validator: (v) =>
                          (v?.length ?? 0) < 14 ? "Telefone inválido" : null,
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

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('services')
          .where('shopId', isEqualTo: _shopId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();

        if (snapshot.data!.docs.isEmpty) {
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
            children: snapshot.data!.docs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              String sId = doc.id;
              String nome = data['nome'] ?? "Serviço";
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
        final start = (e.value['inicio'] as Timestamp).toDate();
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_busy, color: Colors.red, size: 20),
          title: Text(e.value['obs'],
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
