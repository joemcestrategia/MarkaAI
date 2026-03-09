import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import '../clients/client_details_page.dart';
import 'edit_appointment_date_page.dart';

class AppointmentDetailsPage extends StatefulWidget {
  final DocumentSnapshot appointmentDoc;

  // ?? Parâmetros para o modo 3 Colunas (Desktop)
  final bool isEmbedded;
  final VoidCallback? onClose;
  final bool startInEditMode; // ?? Iniciar direto em modo de edição

  const AppointmentDetailsPage({
    super.key,
    required this.appointmentDoc,
    this.isEmbedded = false,
    this.onClose,
    this.startInEditMode = false,
  });

  @override
  State<AppointmentDetailsPage> createState() => _AppointmentDetailsPageState();
}

class _AppointmentDetailsPageState extends State<AppointmentDetailsPage> {
  bool _isEditing = false;
  bool _isLoading = false;

  // Variáveis de Estado
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _selectedServiceId;
  String? _selectedServiceName;
  String? _selectedProfessionalId;
  String? _selectedProfessionalName;
  String? _selectedClientId;
  String? _selectedClientName;
  String? _selectedClientPhone;
  String? _selectedProfessionalFoto;
  String? _selectedProfessionalCargo;
  double? _selectedPrice;
  int? _selectedServiceDuration;
  final TextEditingController _priceController = TextEditingController();
  List<String> _clientTags = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    // ?? Inicia em modo de edição se solicitado
    if (widget.startInEditMode) {
      _isEditing = true;
    }
  }

  // ðŸ”¥ Atualiza os dados se clicar em outro agendamento na lista (Desktop)
  @override
  void didUpdateWidget(covariant AppointmentDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appointmentDoc.id != widget.appointmentDoc.id) {
      setState(() {
        _isEditing = false;
        _loadData();
      });
    }
  }

  void _loadData() {
    final data = widget.appointmentDoc.data() as Map<String, dynamic>;
    _selectedDate = (data['data_agendamento'] as Timestamp).toDate();
    _selectedTime = TimeOfDay.fromDateTime(_selectedDate!);
    _selectedServiceId = data['servicoId'];
    _selectedServiceName = data['servico_nome'];
    _selectedProfessionalId = data['profissionalId'];
    _selectedProfessionalName = data['profissional_nome'];
    _selectedProfessionalFoto = data['profissional_foto'];
    _selectedProfessionalCargo = data['profissional_cargo'];
    _selectedClientId = data['clientId'];
    _selectedClientName = data['client_nome'] ?? data['cliente_nome'];
    _selectedClientPhone =
        data['client_phone'] ?? data['telefone'] ?? data['whatsapp'];
    _selectedPrice = double.tryParse(data['valor_total']?.toString() ??
            data['valor']?.toString() ??
            "0") ??
        0.0;
    _selectedServiceDuration =
        int.tryParse(data['duracao_min']?.toString() ?? '') ?? 30;
    _priceController.text =
        _selectedPrice!.toStringAsFixed(2).replaceAll('.', ',');

    // --- NOVA LÓGICA: Sincronizar dados do cliente em tempo real ---
    if (_selectedClientId != null) {
      _syncClientData();
    }
  }

  Future<void> _syncClientData() async {
    try {
      final shopId =
          (widget.appointmentDoc.data() as Map<String, dynamic>)['shopId'];

      // 1. Tenta buscar no perfil global (users)
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_selectedClientId)
          .get();

      Map<String, dynamic>? clientData;
      if (userDoc.exists) {
        clientData = userDoc.data() as Map<String, dynamic>?;
      } else {
        // 2. Fallback: Busca na subcoleção de clientes da loja
        final clientDoc = await FirebaseFirestore.instance
            .collection('shops')
            .doc(shopId)
            .collection('clients')
            .doc(_selectedClientId)
            .get();
        if (clientDoc.exists) {
          clientData = clientDoc.data();
        }
      }

      if (clientData != null && mounted) {
        setState(() {
          // Se o nome atual for um e-mail ou estiver vazio, atualiza com o nome do perfil
          final String profileName = clientData?['nome'] ?? '';
          if (profileName.isNotEmpty &&
              (_selectedClientName == null ||
                  _selectedClientName!.contains('@') ||
                  _selectedClientName!.isEmpty)) {
            _selectedClientName = profileName;
            // Opcional: Atualizar o agendamento no Firestore para persistir a correção
            widget.appointmentDoc.reference
                .update({'client_nome': profileName});
          }

          // Atualiza telefone se estiver vazio no agendamento mas existir no perfil
          final String profilePhone =
              clientData?['telefone'] ?? clientData?['whatsapp'] ?? '';
          if (profilePhone.isNotEmpty &&
              (_selectedClientPhone == null ||
                  _selectedClientPhone!.isEmpty ||
                  _selectedClientPhone == 'Não informado')) {
            _selectedClientPhone = profilePhone;
            widget.appointmentDoc.reference
                .update({'client_phone': profilePhone});
          }
          // Sincroniza tags
          _clientTags = List<String>.from(clientData?['manualTags'] ?? []);

          // Sincroniza Profissional se necessário
          if (_selectedProfessionalId != null &&
              (_selectedProfessionalName == null ||
                  _selectedProfessionalName == "Não definido" ||
                  _selectedProfessionalName!.isEmpty)) {
            _fetchProfessionalName(shopId);
          }
        });
      }
    } catch (e) {
      debugPrint('Erro ao sincronizar dados do cliente: $e');
    }
  }

  Future<void> _fetchProfessionalName(String shopId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(_selectedProfessionalId)
          .get();
      if (doc.exists && mounted) {
        final pData = doc.data() as Map<String, dynamic>;
        setState(() {
          _selectedProfessionalName = pData['nome'];
          _selectedProfessionalFoto = pData['foto_url'];
          _selectedProfessionalCargo = pData['cargo'];
        });
        // Atualiza o agendamento para persistir
        widget.appointmentDoc.reference.update({
          'profissional_nome': pData['nome'],
          if (pData['foto_url'] != null) 'profissional_foto': pData['foto_url'],
          if (pData['cargo'] != null) 'profissional_cargo': pData['cargo'],
        });
      }
    } catch (e) {
      debugPrint('Erro ao buscar profissional: $e');
    }
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _updateAppointment() async {
    setState(() => _isLoading = true);
    try {
      final fullDate = DateTime(_selectedDate!.year, _selectedDate!.month,
          _selectedDate!.day, _selectedTime!.hour, _selectedTime!.minute);

      // --- VALIDAÇÃO DE CONFLITO AVANÇADA ---
      if (_selectedProfessionalId == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Selecione um profissional válido.'),
                backgroundColor: Colors.red),
          );
        }
        return;
      }

      int serviceDuration = _selectedServiceDuration ?? 30; // fallback state
      final newStartMin = fullDate.hour * 60 + fullDate.minute;
      final newEndMin = newStartMin + serviceDuration;

      final dayStart = DateTime(fullDate.year, fullDate.month, fullDate.day);
      final dayEnd =
          DateTime(fullDate.year, fullDate.month, fullDate.day, 23, 59);

      // Validação 1: Profissional
      final snapProf = await FirebaseFirestore.instance
          .collection('appointments')
          .where('profissionalId', isEqualTo: _selectedProfessionalId)
          .where('data_agendamento', isGreaterThanOrEqualTo: dayStart)
          .where('data_agendamento', isLessThanOrEqualTo: dayEnd)
          .get();

      bool hasProfConflict = false;
      for (final doc in snapProf.docs) {
        if (doc.id == widget.appointmentDoc.id) continue;
        final data = doc.data();
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'cancelado' ||
            status == 'recusado' ||
            status == 'excluido') continue;

        final dt = (data['data_agendamento'] as Timestamp).toDate();
        final dur = int.tryParse(data['duracao_min']?.toString() ?? '') ?? 30;
        final startMin = dt.hour * 60 + dt.minute;
        final endMin = startMin + dur;

        // Verifica interseção: A.start < B.end && B.start < A.end
        if (newStartMin < endMin && startMin < newEndMin) {
          hasProfConflict = true;
          break;
        }
      }

      if (hasProfConflict) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                '⚠️ Horário indisponível! Já existe um agendamento conflitante para este profissional.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ));
        }
        return;
      }

      // Validação 2: Cliente
      if (_selectedClientId != null) {
        final snapClient = await FirebaseFirestore.instance
            .collection('appointments')
            .where('clientId', isEqualTo: _selectedClientId)
            .where('data_agendamento', isGreaterThanOrEqualTo: dayStart)
            .where('data_agendamento', isLessThanOrEqualTo: dayEnd)
            .get();

        bool hasClientConflict = false;
        for (final doc in snapClient.docs) {
          if (doc.id == widget.appointmentDoc.id) continue;
          final data = doc.data();
          final status = (data['status'] ?? '').toString().toLowerCase();
          if (status == 'cancelado' ||
              status == 'recusado' ||
              status == 'excluido') continue;

          final dt = (data['data_agendamento'] as Timestamp).toDate();
          final dur = int.tryParse(data['duracao_min']?.toString() ?? '') ?? 30;
          final startMin = dt.hour * 60 + dt.minute;
          final endMin = startMin + dur;

          if (newStartMin < endMin && startMin < newEndMin) {
            hasClientConflict = true;
            break;
          }
        }

        if (hasClientConflict) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  '⚠️ Conflito! O cliente já possui um ou mais serviços agendados para este mesmo horário.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ));
          }
          return;
        }
      }
      // --- FIM VALIDAÇÃO AVANÇADA ---

      await widget.appointmentDoc.reference.update({
        'clientId': _selectedClientId,
        'client_nome': _selectedClientName,
        'data_agendamento': Timestamp.fromDate(fullDate),
        'servicoId': _selectedServiceId,
        'servico_nome': _selectedServiceName,
        'profissionalId': _selectedProfessionalId,
        'profissional_nome': _selectedProfessionalName,
        'profissional_foto': _selectedProfessionalFoto,
        'profissional_cargo': _selectedProfessionalCargo,
        'valor_total': _selectedPrice ??
            double.tryParse(_priceController.text.replaceAll(',', '.')) ??
            0.0,
        'valor': _selectedPrice ??
            double.tryParse(_priceController.text.replaceAll(',', '.')) ??
            0.0,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Atualizado!"), backgroundColor: Colors.green));
        setState(() => _isEditing = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erro: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteAppointment() async {
    final data = widget.appointmentDoc.data() as Map<String, dynamic>;
    final status = data['status'] ?? '';
    final isHistory = status == 'cancelado' || status == 'concluido';

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.fromLTRB(
              24, 24, 24, MediaQuery.of(ctx).padding.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Excluir Agendamento?',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                isHistory
                    ? "Este agendamento será removido permanentemente do histórico.\nEsta ação não pode ser desfeita."
                    : "Este agendamento ativo será excluído permanentemente.\nEsta ação não pode ser desfeita.",
                style: const TextStyle(fontSize: 15, color: Colors.black87),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade400),
                        foregroundColor: Colors.black87,
                      ),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('VOLTAR',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text('EXCLUIR',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        await widget.appointmentDoc.reference.delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('? Agendamento excluído com sucesso'),
              backgroundColor: Colors.green,
            ),
          );

          if (widget.isEmbedded) {
            widget.onClose?.call();
          } else {
            Navigator.pop(context);
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('âŒ Erro ao excluir: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String money(double v) => "R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}";

  @override
  Widget build(BuildContext context) {
    // ðŸ›¡ï¸ Ajuste de Padding: Se for embutido, usa menos espaço lateral
    final double paddingVal = widget.isEmbedded ? 15 : 20;

    final content = _buildBodyContent(paddingVal);
    final actions = _buildBottomActions();

    // MODO DESKTOP (PAINEL LATERAL)
    if (widget.isEmbedded) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(left: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Column(
          children: [
            // Header Compacto
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Detalhes",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: content),
            Padding(padding: const EdgeInsets.all(15), child: actions),
          ],
        ),
      );
    }

    // MODO MOBILE (SCAFFOLD)
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text("Detalhes do Agendamento",
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: actions,
        ),
      ),
      body: content,
    );
  }

  Widget _buildBodyContent(double hPadding) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final data = widget.appointmentDoc.data() as Map<String, dynamic>;
    final shopId = data['shopId'];
    final status = data['status'] ?? 'agendado';

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: hPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 15), // Topo reduzido
          _buildCompactHeader(status),
          const SizedBox(height: 15),
          if (!_isEditing) ...[
            _buildFinancialHeroPanel(data),
            const SizedBox(height: 15),
          ],
          _buildForm(shopId),
          const SizedBox(height: 20), // Fim reduzido
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return _isEditing
        ? ElevatedButton(
            onPressed: _updateAppointment,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryPurple,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(vertical: 12), // Botão mais fino
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              minimumSize: const Size(double.infinity, 45),
            ),
            child: const Text("SALVAR",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          )
        : Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _deleteAppointment,
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 18),
                  label: const Text("Excluir",
                      style: TextStyle(color: Colors.red, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Colors.redAccent),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _isEditing = true),
                  icon: const Icon(Icons.edit, color: Colors.white, size: 18),
                  label: const Text("Editar",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          );
  }

  // --- HEADER COMPACTO (Focado no Cliente) ---
  Widget _buildCompactHeader(String status) {
    Color statusColor = status == 'confirmado'
        ? Colors.green
        : (status == 'cancelado' ? Colors.red : Colors.orange);

    return InkWell(
      onTap: _selectedClientId != null
          ? () async {
              // Buscar dados completos do cliente no Firestore antes de navegar
              setState(() => _isLoading = true);
              try {
                final shopId = (widget.appointmentDoc.data()
                    as Map<String, dynamic>)['shopId'];

                // Tenta buscar na coleção users
                DocumentSnapshot userDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(_selectedClientId)
                    .get();

                Map<String, dynamic> clientData;
                if (userDoc.exists) {
                  clientData = userDoc.data() as Map<String, dynamic>;
                } else {
                  // Fallback: Tenta buscar na subcoleção de clientes da loja
                  final clientDoc = await FirebaseFirestore.instance
                      .collection('shops')
                      .doc(shopId)
                      .collection('clients')
                      .doc(_selectedClientId)
                      .get();

                  if (clientDoc.exists) {
                    clientData = clientDoc.data() as Map<String, dynamic>;
                  } else {
                    // Fallback final: Usa os dados que já temos no agendamento
                    clientData = {
                      'nome': _selectedClientName,
                      'telefone': _selectedClientPhone,
                      'origem': 'manual',
                    };
                  }
                }

                if (mounted) {
                  setState(() => _isLoading = false);
                  // Navega para o perfil do cliente
                  if (widget.isEmbedded) {
                    // No Desktop, idealmente abriria na mesma coluna ou substituiria
                    // Por enquanto, seguimos o padrão de diálogo ou push
                    showDialog(
                      context: context,
                      builder: (context) => Dialog(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 500),
                          child: ClientDetailsPage(
                            clientData: clientData,
                            clientId: _selectedClientId!,
                            onClose: () => Navigator.pop(context),
                            shopIdOverride: shopId,
                          ),
                        ),
                      ),
                    );
                  } else {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => Scaffold(
                          appBar: AppBar(
                            title: const Text("Perfil do Cliente"),
                            backgroundColor: AppColors.primaryPurple,
                            foregroundColor: Colors.white,
                          ),
                          body: ClientDetailsPage(
                            clientData: clientData,
                            clientId: _selectedClientId!,
                            onClose: () => Navigator.pop(context),
                            shopIdOverride: shopId,
                          ),
                        ),
                      ),
                    ).then((_) {
                      // Recarrega os dados caso o nome tenha sido editado
                      _loadData();
                      setState(() {});
                    });
                  }
                }
              } catch (e) {
                if (mounted) {
                  setState(() => _isLoading = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Erro ao carregar cliente: $e")),
                  );
                }
              }
            }
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              )
            ]),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.1),
              child: const Icon(Icons.person,
                  color: AppColors.primaryPurple, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _selectedClientName ?? "Cliente",
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_selectedClientPhone != null &&
                          _selectedClientPhone!.isNotEmpty &&
                          _selectedClientPhone != 'Não informado') ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () async {
                            final phone = _selectedClientPhone!
                                .replaceAll(RegExp(r'\D'), '');
                            final url = 'https://wa.me/55$phone';
                            if (await canLaunchUrl(Uri.parse(url))) {
                              await launchUrl(Uri.parse(url));
                            }
                          },
                          child: const Icon(Icons.chat_rounded,
                              color: Colors.green, size: 14),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _selectedClientPhone != null &&
                            _selectedClientPhone!.isNotEmpty
                        ? _selectedClientPhone!
                        : "Telefone não informado",
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_clientTags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: _clientTags.map((tag) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                AppColors.primaryPurple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tag,
                            style: const TextStyle(
                              color: AppColors.primaryPurple,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Tag de Status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(status.toUpperCase(),
                  style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10)),
            ),
          ],
        ),
      ),
    );
  }

  // --- PAINEL FINANCEIRO ULTRA-COMPACTO ---
  Widget _buildFinancialHeroPanel(Map<String, dynamic> data) {
    final double total = double.tryParse(data['valor_total']?.toString() ??
            data['valor']?.toString() ??
            "0") ??
        0.0;
    final double pago =
        double.tryParse(data['valor_pago']?.toString() ?? "0") ?? 0.0;
    final double restante = total - pago;

    double percentPaid = total > 0 ? (pago / total) : 0.0;
    if (percentPaid > 1.0) percentPaid = 1.0;

    return Container(
      padding: const EdgeInsets.all(15), // Padding reduzido de 20 para 15
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
            color: restante > 0.01
                ? Colors.red.withValues(alpha: 0.3)
                : Colors.green.withValues(alpha: 0.3),
            width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        children: [
          // Título menor e com menos espaço
          const Text("RESUMO FINANCEIRO",
              style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  fontSize: 9)),
          const SizedBox(height: 5),

          // Valor total menor (28 -> 24)
          Text(money(total),
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87)),
          const SizedBox(height: 10),

          // Barra mais fina (12 -> 8)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: percentPaid,
              minHeight: 8,
              backgroundColor: Colors.grey[100],
              valueColor: AlwaysStoppedAnimation<Color>(
                  pago >= total ? Colors.green : Colors.orange),
            ),
          ),
          const SizedBox(height: 4),
          Align(
              alignment: Alignment.centerRight,
              child: Text("${(percentPaid * 100).toInt()}% Quitado",
                  style: TextStyle(
                      fontSize: 9,
                      color: pago >= total ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold))),

          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                  child: Column(children: [
                const Text("JÃ PAGO",
                    style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 10)),
                const SizedBox(height: 2),
                Text(money(pago),
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green))
              ])),
              Container(width: 1, height: 25, color: Colors.grey[300]),
              Expanded(
                  child: Column(children: [
                Text("A RECEBER",
                    style: TextStyle(
                        color: restante > 0.01 ? Colors.red : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 10)),
                const SizedBox(height: 2),
                Text(money(restante),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: restante > 0.01 ? Colors.red : Colors.grey))
              ])),
            ],
          ),
        ],
      ),
    );
  }

  // --- FORMULÃRIO COMPACTO ---
  Widget _buildForm(String shopId) {
    return Column(
      children: [
        _buildEditableField(
            "Profissional",
            Icons.badge_outlined,
            _isEditing,
            _buildProfessionalDropdown(shopId),
            _selectedProfessionalName ?? "Não definido"),
        const SizedBox(height: 8), // Espaçamento reduzido (15 -> 8)
        _buildEditableField("Serviço", Icons.content_cut_outlined, _isEditing,
            _buildServiceDropdown(shopId), _selectedServiceName ?? ""),
        const SizedBox(height: 8),
        // Price editable field
        _buildPriceField(),
        const SizedBox(height: 8),
        InkWell(
          onTap: !_isEditing && _selectedClientId != null
              ? () => _openClientProfile()
              : null,
          child: _buildEditableField(
              "Cliente",
              Icons.person_outline,
              _isEditing,
              _buildClientDropdown(shopId),
              _selectedClientName ?? ""),
        ),
        const SizedBox(height: 8),
        _buildDateTimeField(),
      ],
    );
  }

  // Helper para abrir o perfil do cliente centralizado
  Future<void> _openClientProfile() async {
    setState(() => _isLoading = true);
    try {
      final data = widget.appointmentDoc.data() as Map<String, dynamic>;
      final shopId = data['shopId'];

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_selectedClientId)
          .get();

      Map<String, dynamic> clientData;
      if (userDoc.exists) {
        clientData = userDoc.data() as Map<String, dynamic>;
      } else {
        final clientDoc = await FirebaseFirestore.instance
            .collection('shops')
            .doc(shopId)
            .collection('clients')
            .doc(_selectedClientId)
            .get();

        if (clientDoc.exists) {
          clientData = clientDoc.data() as Map<String, dynamic>;
        } else {
          clientData = {
            'nome': _selectedClientName,
            'telefone': _selectedClientPhone,
            'origem': 'manual',
          };
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
        if (widget.isEmbedded) {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: ClientDetailsPage(
                  clientData: clientData,
                  clientId: _selectedClientId!,
                  onClose: () => Navigator.pop(context),
                  shopIdOverride: shopId,
                ),
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => Scaffold(
                appBar: AppBar(
                  title: const Text("Perfil do Cliente"),
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                ),
                body: ClientDetailsPage(
                  clientData: clientData,
                  clientId: _selectedClientId!,
                  onClose: () => Navigator.pop(context),
                  shopIdOverride: shopId,
                ),
              ),
            ),
          ).then((_) {
            _loadData();
            setState(() {});
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao carregar cliente: $e")),
        );
      }
    }
  }

  Widget _buildPriceField() {
    return Row(
      children: [
        Container(
            padding: const EdgeInsets.all(8), // Icone menor
            decoration: BoxDecoration(
                color: AppColors.primaryPurple.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.attach_money,
                size: 18, color: AppColors.primaryPurple)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Valor do Serviço",
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey)), // Label menor
              const SizedBox(height: 1),
              _isEditing
                  ? SizedBox(
                      height: 35,
                      child: TextField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6)),
                        onChanged: (v) {
                          final parsed =
                              double.tryParse(v.replaceAll(',', '.'));
                          if (parsed != null) _selectedPrice = parsed;
                        },
                      ),
                    )
                  : Text(_selectedPrice != null ? money(_selectedPrice!) : '-',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildEditableField(String label, IconData icon, bool isDropdown,
      Widget? dropdown, String value) {
    return Row(
      children: [
        Container(
            padding: const EdgeInsets.all(8), // Icone menor
            decoration: BoxDecoration(
                color: AppColors.primaryPurple.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 18, color: AppColors.primaryPurple)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10, color: Colors.grey)), // Label menor
              const SizedBox(height: 1),
              isDropdown
                  ? SizedBox(height: 35, child: dropdown) // Dropdown mais baixo
                  : Text(value,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500)), // Texto valor menor
            ],
          ),
        )
      ],
    );
  }

  Widget _buildDateTimeField() {
    // ── Modo de visualização: exibe data e hora lado a lado ───────────────────
    if (!_isEditing) {
      final dateText = _selectedDate != null
          ? DateFormat('dd/MM/yyyy').format(_selectedDate!)
          : 'Pendente';
      final timeText =
          _selectedTime != null ? _selectedTime!.format(context) : 'Pendente';

      return Row(children: [
        Expanded(
            child: _buildEditableField(
                "Data", Icons.event, false, null, dateText)),
        const SizedBox(width: 10),
        Expanded(
            child: _buildEditableField(
                "Horário", Icons.schedule, false, null, timeText)),
      ]);
    }

    // ── Modo de edição: card que abre o fluxo visual de reagendamento ────────
    return InkWell(
      onTap: _openRescheduleFlow,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primaryPurple.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppColors.primaryPurple.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.primaryPurple.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.event_repeat,
                  size: 17, color: AppColors.primaryPurple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Data / Horário',
                      style: TextStyle(fontSize: 10, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text(
                    _selectedDate != null && _selectedTime != null
                        ? '${DateFormat('dd/MM/yyyy').format(_selectedDate!)}  •  ${_selectedTime!.format(context)}'
                        : 'Pendente (Toque para reagendar)',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _selectedDate != null
                            ? Colors.black87
                            : Colors.orange),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 13, color: AppColors.primaryPurple),
          ],
        ),
      ),
    );
  }

  /// Carrega os documentos necessários e abre o fluxo visual de reagendamento.
  Future<void> _openRescheduleFlow() async {
    setState(() => _isLoading = true);
    try {
      final data = widget.appointmentDoc.data() as Map<String, dynamic>;
      final shopId = data['shopId'] as String?;
      final serviceId = _selectedServiceId ?? data['servicoId'] as String?;
      final profId =
          _selectedProfessionalId ?? data['profissionalId'] as String?;

      if (shopId == null || serviceId == null || profId == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Dados incompletos para reagendar. Verifique serviço e profissional.')),
          );
        }
        return;
      }

      // Carrega em paralelo
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('shops').doc(shopId).get(),
        FirebaseFirestore.instance.collection('services').doc(serviceId).get(),
        FirebaseFirestore.instance.collection('employees').doc(profId).get(),
      ]);

      final shopDoc = results[0];
      final serviceDoc = results[1];
      final profDoc = results[2];

      if (!shopDoc.exists || !serviceDoc.exists || !profDoc.exists) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Não foi possível carregar os dados da agenda.')),
          );
        }
        return;
      }

      final shopData = shopDoc.data() as Map<String, dynamic>;
      final Map<String, dynamic> shopConfig =
          shopData['config'] as Map<String, dynamic>? ?? {};
      final int intervalMinutes =
          (shopConfig['intervalo_agenda_min'] as num?)?.toInt() ?? 60;

      // Group all pending non-saved state edits
      final pendingUpdates = <String, dynamic>{
        if (_selectedClientId != null) 'clientId': _selectedClientId,
        if (_selectedClientName != null) 'client_nome': _selectedClientName,
        if (_selectedServiceId != null) 'servicoId': _selectedServiceId,
        if (_selectedServiceName != null) 'servico_nome': _selectedServiceName,
        if (_selectedProfessionalId != null)
          'profissionalId': _selectedProfessionalId,
        if (_selectedProfessionalName != null)
          'profissional_nome': _selectedProfessionalName,
        if (_selectedProfessionalFoto != null)
          'profissional_foto': _selectedProfessionalFoto,
        if (_selectedProfessionalCargo != null)
          'profissional_cargo': _selectedProfessionalCargo,
        if (_selectedServiceDuration != null)
          'duracao_min': _selectedServiceDuration,
        'valor_total': _selectedPrice ??
            double.tryParse(_priceController.text.replaceAll(',', '.')) ??
            0.0,
        'valor': _selectedPrice ??
            double.tryParse(_priceController.text.replaceAll(',', '.')) ??
            0.0,
      };

      if (mounted) {
        setState(() => _isLoading = false);
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EditAppointmentDatePage(
              appointmentDoc: widget.appointmentDoc,
              shop: shopDoc,
              serviceDoc: serviceDoc,
              professionalDoc: profDoc,
              shopConfig: shopConfig,
              intervalMinutes: intervalMinutes,
              pendingUpdates: pendingUpdates, // Passando pra Base
              onSuccess: () {
                // Recarrega dados após confirmação do reagendamento
                setState(() {
                  _isEditing = false;
                  _loadData();
                });
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao abrir reagendamento: $e')),
        );
      }
    }
  }

  // --- DROPDOWNS (Mantidos com estilo de texto ajustado) ---
  Widget _buildClientDropdown(String shopId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('clients')
          .where('shopId', isEqualTo: shopId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Text("Nenhum cliente cadastrado",
              style: TextStyle(fontSize: 13, color: Colors.grey));
        }

        return Autocomplete<DocumentSnapshot>(
          initialValue: TextEditingValue(text: _selectedClientName ?? ''),
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return docs;
            }
            return docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final nome = (data['nome'] ?? '').toString().toLowerCase();
              final search = textEditingValue.text.toLowerCase();
              return nome.contains(search);
            });
          },
          displayStringForOption: (DocumentSnapshot option) {
            final data = option.data() as Map<String, dynamic>;
            return data['nome'] ?? '';
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Buscar ou digitar cliente',
                hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (value) {
                // Permite digitação livre (cliente não cadastrado)
                setState(() {
                  _selectedClientName = value;
                  _selectedClientId = null; // Remove ID se digitado manualmente
                });
              },
            );
          },
          onSelected: (DocumentSnapshot selection) {
            final data = selection.data() as Map<String, dynamic>;
            setState(() {
              _selectedClientId = selection.id;
              _selectedClientName = data['nome'];
            });
          },
        );
      },
    );
  }

  Widget _buildServiceDropdown(String shopId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('services')
          .where('shopId', isEqualTo: shopId)
          .where('ativo', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Text("Nenhum serviço ativo",
              style: TextStyle(fontSize: 13, color: Colors.grey));
        }

        // ðŸ”¥ Verifica se o serviço selecionado existe na lista
        final serviceExists = docs.any((d) => d.id == _selectedServiceId);
        final validValue = serviceExists ? _selectedServiceId : null;

        return DropdownButton<String>(
          value: validValue,
          isExpanded: true,
          underline: const SizedBox(),
          hint: Text(_selectedServiceName ?? 'Selecione um serviço',
              style: const TextStyle(fontSize: 13)),
          items: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return DropdownMenuItem(
                value: doc.id,
                child: Text('${data['nome']} - R\$ ${data['preco']}',
                    style: const TextStyle(fontSize: 13)));
          }).toList(),
          onChanged: (val) {
            final doc = docs.firstWhere((d) => d.id == val);
            final data = doc.data() as Map<String, dynamic>;
            final newPrice = double.tryParse(data['preco'].toString()) ?? 0.0;
            final newDur = int.tryParse(data['tempo_min'].toString()) ?? 30;
            setState(() {
              _selectedServiceId = val;
              _selectedServiceName = data['nome'];
              _selectedPrice = newPrice;
              _selectedServiceDuration = newDur;
              // Atualiza campo de texto do preço
              _priceController.text =
                  newPrice.toStringAsFixed(2).replaceAll('.', ',');

              // Reforça fluxo rigoroso sequencial:
              // Mudou serviço > Zera Profissional > Zera Data/Hora
              _selectedProfessionalId = null;
              _selectedProfessionalName = null;
              _selectedProfessionalFoto = null;
              _selectedProfessionalCargo = null;

              _selectedDate = null;
              _selectedTime = null;
            });
          },
        );
      },
    );
  }

  Widget _buildProfessionalDropdown(String shopId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('employees')
          .where('shopId', isEqualTo: shopId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final profs = snapshot.data!.docs.where((d) {
          final skills =
              (d.data() as Map)['servicos_habilidade'] as List? ?? [];
          return skills.isEmpty || skills.contains(_selectedServiceId);
        }).toList();

        if (profs.isEmpty) {
          return const Text("Nenhum profissional apto para este serviço",
              style: TextStyle(fontSize: 12, color: Colors.red));
        }

        return DropdownButton<String>(
          value: profs.any((d) => d.id == _selectedProfessionalId)
              ? _selectedProfessionalId
              : null,
          isExpanded: true,
          underline: const SizedBox(),
          hint: Text(_selectedProfessionalName ?? 'Selecione o profissional',
              style: const TextStyle(fontSize: 13)),
          items: profs
              .map((doc) => DropdownMenuItem(
                  value: doc.id,
                  child:
                      Text(doc['nome'], style: const TextStyle(fontSize: 13))))
              .toList(),
          onChanged: (val) {
            final doc = profs.firstWhere((d) => d.id == val);
            final data = doc.data() as Map<String, dynamic>;
            setState(() {
              _selectedProfessionalId = val;
              _selectedProfessionalName = data['nome'];
              _selectedProfessionalFoto = data['foto_url'];
              _selectedProfessionalCargo = data['cargo'];

              // Reforça fluxo rigoroso sequencial:
              // Mudou profissional > Zera Data/Hora, pois a disponibilidade
              // do novo profissional será diferente.
              _selectedDate = null;
              _selectedTime = null;
            });
          },
        );
      },
    );
  }
}
