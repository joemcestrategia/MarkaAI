import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';

class AppointmentDetailsPage extends StatefulWidget {
  final DocumentSnapshot appointmentDoc;

  // 🔥 Parâmetros para o modo 3 Colunas (Desktop)
  final bool isEmbedded;
  final VoidCallback? onClose;
  final bool startInEditMode; // 🆕 Iniciar direto em modo de edição

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
  double? _selectedPrice;
  final TextEditingController _priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    // 🆕 Inicia em modo de edição se solicitado
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
    _selectedClientId = data['clientId'];
    _selectedClientName = data['client_nome'] ?? data['cliente_nome'];
    _selectedPrice = double.tryParse(data['valor_total']?.toString() ??
            data['valor']?.toString() ??
            "0") ??
        0.0;
    _priceController.text =
        _selectedPrice!.toStringAsFixed(2).replaceAll('.', ',');
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

      await widget.appointmentDoc.reference.update({
        'clientId': _selectedClientId,
        'client_nome': _selectedClientName,
        'data_agendamento': Timestamp.fromDate(fullDate),
        'servicoId': _selectedServiceId,
        'servico_nome': _selectedServiceName,
        'profissionalId': _selectedProfessionalId,
        'profissional_nome': _selectedProfessionalName,
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

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Excluir Agendamento?"),
        content: Text(
          isHistory
              ? "Este agendamento será removido permanentemente do histórico.\n\nEsta ação não pode ser desfeita."
              : "Este agendamento ativo será excluído permanentemente.\n\nEsta ação não pode ser desfeita.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("CANCELAR"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text(
              "EXCLUIR PERMANENTEMENTE",
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      try {
        await widget.appointmentDoc.reference.delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Agendamento excluído com sucesso'),
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.black, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Detalhes",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        actions: [
          // botão superior removido por solicitação — exclusão permanece disponível no botão inferior
        ],
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
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          );
  }

  // --- HEADER COMPACTO ---
  Widget _buildCompactHeader(String status) {
    Color statusColor = status == 'confirmado'
        ? Colors.green
        : (status == 'cancelado' ? Colors.red : Colors.orange);
    return Container(
      padding: const EdgeInsets.all(10), // Padding interno reduzido
      decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18, // Avatar menor (era 20)
            backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.1),
            child: const Icon(Icons.person,
                color: AppColors.primaryPurple, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _selectedClientName ?? "Cliente",
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87), // Fonte reduzida
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _selectedServiceName ?? "Serviço",
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey), // Fonte reduzida
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6)),
            child: Text(status.toUpperCase(),
                style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 9)),
          ),
        ],
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
            _selectedProfessionalName ?? ""),
        const SizedBox(height: 8), // Espaçamento reduzido (15 -> 8)
        _buildEditableField("Serviço", Icons.content_cut_outlined, _isEditing,
            _buildServiceDropdown(shopId), _selectedServiceName ?? ""),
        const SizedBox(height: 8),
        // Price editable field
        _buildPriceField(),
        const SizedBox(height: 8),
        _buildEditableField("Cliente", Icons.person_outline, _isEditing,
            _buildClientDropdown(shopId), _selectedClientName ?? ""),
        const SizedBox(height: 8),
        _buildDateTimeField(),
      ],
    );
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
    return Row(children: [
      Expanded(
          child: InkWell(
              onTap: _isEditing
                  ? () async {
                      final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate!,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030));
                      if (date != null) setState(() => _selectedDate = date);
                    }
                  : null,
              child: _buildEditableField("Data", Icons.event, false, null,
                  DateFormat('dd/MM/yyyy').format(_selectedDate!)))),
      const SizedBox(width: 10),
      Expanded(
          child: InkWell(
              onTap: _isEditing
                  ? () async {
                      final time = await showTimePicker(
                          context: context, initialTime: _selectedTime!);
                      if (time != null) setState(() => _selectedTime = time);
                    }
                  : null,
              child: _buildEditableField("Horário", Icons.schedule, false, null,
                  _selectedTime!.format(context))))
    ]);
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
            setState(() {
              _selectedServiceId = val;
              _selectedServiceName = data['nome'];
              _selectedPrice = double.tryParse(data['preco'].toString()) ?? 0.0;
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
        return DropdownButton<String>(
          value: _selectedProfessionalId,
          isExpanded: true,
          underline: const SizedBox(),
          items: snapshot.data!.docs
              .map((doc) => DropdownMenuItem(
                  value: doc.id,
                  child:
                      Text(doc['nome'], style: const TextStyle(fontSize: 13))))
              .toList(),
          onChanged: (val) {
            final doc = snapshot.data!.docs.firstWhere((d) => d.id == val);
            setState(() {
              _selectedProfessionalId = val;
              _selectedProfessionalName = doc['nome'];
            });
          },
        );
      },
    );
  }
}
