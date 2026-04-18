import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import '../clients/client_details_page.dart';
import 'edit_appointment_date_page.dart';
import 'transaction_details_page.dart';
import '../../core/services/mercado_pago_service.dart';

class AppointmentDetailsPage extends StatefulWidget {
  final Map<String, dynamic> appointmentDoc;

  // ?? Parâmetros para o modo 3 Colunas (Desktop)
  final bool isEmbedded;
  final VoidCallback? onClose;
  final bool startInEditMode; // ?? Iniciar direto em modo de edição
  final VoidCallback? onEdit; // ?? Callback para edição externa (Modal Refatorado)
  final void Function(Map<String, dynamic> updatedData)? onAppointmentUpdated;

  const AppointmentDetailsPage({
    super.key,
    required this.appointmentDoc,
    this.isEmbedded = false,
    this.onClose,
    this.startInEditMode = false,
    this.onEdit,
    this.onAppointmentUpdated,
  });

  @override
  State<AppointmentDetailsPage> createState() => _AppointmentDetailsPageState();
}

class _AppointmentDetailsPageState extends State<AppointmentDetailsPage> {
  bool _isEditing = false;
  bool _isLoading = false;

  // Cópia local do doc para evitar exibir dados obsoletos após edição
  Map<String, dynamic> _localDoc = {};

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
  String? _selectedClientPhoto;
  String? _selectedProfessionalFoto;
  String? _selectedProfessionalCargo;
  double? _selectedPrice;
  int? _selectedServiceDuration;
  final TextEditingController _priceController = TextEditingController();
  List<String> _clientTags = [];
  double _shopBirthdayDiscount = 0.0;
  String? _selectedPaymentMethod;
  
  // Variáveis para Precificação e Descontos
  double _basePrice = 0.0;
  double _discountAmount = 0.0;
  bool _isBirthdayDiscountApplied = false;
  bool _isCouponApplied = false;
  String? _couponCode;

  @override
  void initState() {
    super.initState();
    _localDoc = Map<String, dynamic>.from(widget.appointmentDoc);
    _loadData();
    _refreshFromDb();
    _loadShopConfig();
    if (widget.startInEditMode) {
      _isEditing = true;
    }
  }

  // Busca dados frescos do banco para garantir que payment_method e outros campos estejam atualizados
  Future<void> _refreshFromDb() async {
    final id = widget.appointmentDoc['id']?.toString();
    if (id == null || id.isEmpty) return;
    try {
      final fresh = await Supabase.instance.client
          .from('appointments')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (fresh != null && mounted && !_isEditing) {
        setState(() {
          _localDoc = Map<String, dynamic>.from(fresh);
          _selectedPaymentMethod = (_localDoc['payment_method']?.toString() ?? '').isNotEmpty
              ? _localDoc['payment_method']!.toString()
              : 'Pessoalmente';
          _basePrice = double.tryParse(_localDoc['total_price']?.toString() ?? '0') ?? _basePrice;
          _selectedPrice = double.tryParse(
                  _localDoc['total_payable']?.toString() ??
                  _localDoc['valor_com_desconto']?.toString() ??
                  _localDoc['total_value']?.toString() ?? '0') ??
              _selectedPrice;
          _discountAmount = double.tryParse(_localDoc['discount_amount']?.toString() ?? '0') ?? 0.0;
          _isBirthdayDiscountApplied = _localDoc['birthday_discount_applied'] == true;
          _isCouponApplied = _localDoc['coupon_applied'] == true;
        });
      }
    } catch (e) {
      debugPrint('Erro ao atualizar agendamento do DB: $e');
    }
  }

  Future<void> _loadShopConfig() async {
    final shopId = widget.appointmentDoc['shop_id'] ?? widget.appointmentDoc['shopId'];
    if (shopId == null) return;

    try {
      final doc = await Supabase.instance.client
          .from('shops')
          .select('config')
          .eq('id', shopId)
          .maybeSingle();

      if (doc != null && mounted) {
        final config = doc['config'] as Map<String, dynamic>? ?? {};
        setState(() {
          _shopBirthdayDiscount = double.tryParse(config['birthday_discount_percent']?.toString() ?? '0') ?? 0.0;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar shop config: $e');
    } finally {
    }
  }

  // Atualiza dados ao trocar agendamento ou ao receber atualização externa do mesmo agendamento
  @override
  void didUpdateWidget(covariant AppointmentDetailsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId = oldWidget.appointmentDoc['id']?.toString();
    final newId = widget.appointmentDoc['id']?.toString();
    if (oldId != newId) {
      // Agendamento diferente: recarrega tudo
      _localDoc = Map<String, dynamic>.from(widget.appointmentDoc);
      setState(() {
        _loadData();
      });
      _refreshFromDb();
    } else if (!_isEditing) {
      // Mesmo agendamento, atualização externa (ex: modal de edição rápida)
      // Mescla novos campos sem resetar estado de edição
      final newDoc = widget.appointmentDoc;
      final updatedPayment = newDoc['payment_method']?.toString();
      final bool paymentChanged = updatedPayment != null &&
          updatedPayment.isNotEmpty &&
          updatedPayment != _localDoc['payment_method']?.toString();
      if (paymentChanged) {
        setState(() {
          _localDoc = {..._localDoc, ...newDoc};
          _selectedPaymentMethod = updatedPayment;
        });
      } else {
        // Mescla outros campos que possam ter mudado (data, serviço, etc.)
        final oldUpdatedAt = oldWidget.appointmentDoc['updated_at']?.toString();
        final newUpdatedAt = newDoc['updated_at']?.toString();
        if (oldUpdatedAt != newUpdatedAt) {
          setState(() {
            _localDoc = {..._localDoc, ...newDoc};
          });
        }
      }
    }
  }

  void _loadData() {
    _localDoc = Map<String, dynamic>.from(widget.appointmentDoc);
    final data = _localDoc;
    final rawDate = data['scheduled_at'];
    if (rawDate is DateTime) {
      _selectedDate = rawDate;
    } else if (rawDate is String) {
      _selectedDate = DateTime.tryParse(rawDate);
    } else {
      _selectedDate = DateTime.now();
    }
    
    _selectedTime = TimeOfDay.fromDateTime(_selectedDate!);
    _selectedServiceId = data['service_id'] ?? data['servicoId'];
    _selectedServiceName = (data['service_name'] ?? '').toString();
    _selectedProfessionalId = data['professional_id']?.toString();
    _selectedProfessionalName = (data['professional_name'] ?? 'Não definido').toString();
    _selectedProfessionalFoto = data['professional_photo']?.toString();
    _selectedProfessionalCargo = data['professional_role']?.toString();
    _selectedClientId = data['client_id']?.toString();
    _selectedClientName = (data['client_name'] ?? '').toString();
    _selectedClientPhone = (data['client_phone'] ?? '').toString();
    if (_selectedClientPhone == 'null') _selectedClientPhone = '';

    // --- LÓGICA FINANCEIRA ---
    _basePrice = double.tryParse(data['total_price']?.toString() ??
            data['valor_total']?.toString() ??
            "0") ?? 0.0;
            
    _selectedPrice = double.tryParse(data['total_payable']?.toString() ??
            data['valor_com_desconto']?.toString() ??
            data['total_value']?.toString() ??
            "0") ?? 0.0;
            
    _discountAmount = double.tryParse(data['discount_amount']?.toString() ?? "0") ?? 0.0;
    _isBirthdayDiscountApplied = data['birthday_discount_applied'] == true;
    _isCouponApplied = data['coupon_applied'] == true;
    _couponCode = data['coupon_code']?.toString();
    
    // Fallback se o total_payable estiver zerado mas o valor_total existir
    if ((_selectedPrice ?? 0.0) < 0.01 && _basePrice > 0.01) {
      _selectedPrice = _basePrice;
    }

    _selectedServiceDuration =
        int.tryParse(data['duration_min']?.toString() ?? data['duracao_min']?.toString() ?? '') ?? 30;
    _selectedPaymentMethod = data['payment_method']?.toString() ?? 'Pessoalmente';
    
    _priceController.text = _selectedPrice!.toStringAsFixed(2).replaceAll('.', ',');

    // --- NOVA LÓGICA: Sincronizar dados do cliente em tempo real ---
    if (_selectedClientId != null) {
      _syncClientData();
    }
  }

  Future<void> _syncClientData() async {
    try {
      final shopId = widget.appointmentDoc['shop_id'] ?? widget.appointmentDoc['shopId'];

      // 1. Tenta buscar no perfil global (users)
      final userDoc = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', _selectedClientId!)
          .maybeSingle();

      Map<String, dynamic>? clientData = userDoc;

      if (clientData != null && mounted) {
        final String profileName = clientData['name'] ?? '';
        if (profileName.isNotEmpty &&
            (_selectedClientName == null ||
                _selectedClientName!.contains('@') ||
                _selectedClientName!.isEmpty)) {
          await Supabase.instance.client
              .from('appointments')
              .update({'client_name': profileName})
              .eq('id', widget.appointmentDoc['id']);
          if (mounted) {
            setState(() {
              _selectedClientName = profileName;
            });
          }
        }

        final String profilePhone =
            clientData['phone'] ?? clientData['telefone'] ?? clientData['whatsapp'] ?? '';
        if (profilePhone.isNotEmpty &&
            (_selectedClientPhone == null ||
                _selectedClientPhone!.isEmpty ||
                _selectedClientPhone == 'Não informado' ||
                _selectedClientPhone == 'null')) {
          await Supabase.instance.client
              .from('appointments')
              .update({'client_phone': profilePhone})
              .eq('id', widget.appointmentDoc['id']);
          if (mounted) {
            setState(() {
              _selectedClientPhone = profilePhone;
              _localDoc['client_phone'] = profilePhone;
            });
          }
        }

        // Busca foto do perfil (Google ou cadastro)
        final String profilePhoto = clientData['photo_url']?.toString() ?? '';
        if (profilePhoto.isNotEmpty && mounted) {
          setState(() {
            _selectedClientPhoto = profilePhoto;
          });
        }

        if (mounted) {
          setState(() {
            _clientTags = [];
            if (_selectedProfessionalId != null &&
                (_selectedProfessionalName == null ||
                    _selectedProfessionalName == "Não definido" ||
                    _selectedProfessionalName!.isEmpty)) {
              _fetchProfessionalName(shopId);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao sincronizar dados do cliente: $e');
    }
  }

  Future<void> _fetchProfessionalName(String shopId) async {
    try {
      final doc = await Supabase.instance.client
          .from('employees')
          .select()
          .eq('id', _selectedProfessionalId!)
          .maybeSingle();
      if (doc != null && mounted) {
        final pData = doc;
        setState(() {
          _selectedProfessionalName = pData['name'];
          _selectedProfessionalFoto = pData['photo_url'] ?? pData['foto_url'];
          _selectedProfessionalCargo = pData['role'] ?? pData['cargo'];
        });
        // Atualiza o agendamento para persistir
        await Supabase.instance.client
            .from('appointments')
            .update({
              'professional_name': pData['name'] ?? pData['nome'],
              if ((pData['photo_url'] ?? pData['foto_url']) != null) 'professional_photo': pData['photo_url'] ?? pData['foto_url'],
              if ((pData['role'] ?? pData['cargo']) != null) 'professional_role': pData['role'] ?? pData['cargo'],
            })
            .eq('id', widget.appointmentDoc['id']);
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
      final snapProf = await Supabase.instance.client
          .from('appointments')
          .select()
          .eq('professional_id', _selectedProfessionalId!)
          .gte('scheduled_at', dayStart.toIso8601String())
          .lte('scheduled_at', dayEnd.toIso8601String());

      bool hasProfConflict = false;
      for (final doc in snapProf) {
        if (doc['id'] == widget.appointmentDoc['id']) continue;
        final data = doc;
        final status = (data['status'] ?? '').toString().toLowerCase();
        if (status == 'cancelado' ||
            status == 'recusado' ||
            status == 'excluido') {
          continue;
        }

        final dtStr = (data['scheduled_at']).toString();
        final dt = DateTime.parse(dtStr);
        final dur = int.tryParse(data['duration_min']?.toString() ?? data['duracao_min']?.toString() ?? '') ?? 30;
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
        final snapClient = await Supabase.instance.client
            .from('appointments')
            .select()
            .eq('client_id', _selectedClientId!)
            .gte('scheduled_at', dayStart.toIso8601String())
            .lte('scheduled_at', dayEnd.toIso8601String());

        bool hasClientConflict = false;
        for (final doc in snapClient) {
          if (doc['id'] == widget.appointmentDoc['id']) continue;
          final data = doc;
          final status = (data['status'] ?? '').toString().toLowerCase();
          if (status == 'cancelado' ||
              status == 'recusado' ||
              status == 'excluido') {
            continue;
          }

          final dtStr = (data['scheduled_at']).toString();
          final dt = DateTime.parse(dtStr);
          final dur = int.tryParse(data['duration_min']?.toString() ?? data['duracao_min']?.toString() ?? '') ?? 30;
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

      final double savedPrice = _selectedPrice ??
          double.tryParse(_priceController.text.replaceAll(',', '.')) ??
          0.0;
      final Map<String, dynamic> updateData = {
        'client_id': _selectedClientId,
        'client_name': _selectedClientName,
        'scheduled_at': fullDate.toIso8601String(),
        'service_id': _selectedServiceId,
        'service_name': _selectedServiceName,
        'professional_id': _selectedProfessionalId,
        'professional_name': _selectedProfessionalName,
        'professional_photo': _selectedProfessionalFoto,
        'professional_role': _selectedProfessionalCargo,
        'total_price': savedPrice,
        'price': savedPrice,
        'total_value': savedPrice,
        'valor_total': savedPrice,
        'duration_min': _selectedServiceDuration ?? 30,
        'payment_method': _selectedPaymentMethod,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await Supabase.instance.client
          .from('appointments')
          .update(updateData)
          .eq('id', widget.appointmentDoc['id']);

      if (mounted) {
        // Sincroniza _localDoc com os dados salvos para evitar stale state
        setState(() {
          _localDoc = {..._localDoc, ...updateData};
          _isEditing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Atualizado!"), backgroundColor: Colors.green));
        // Notifica o pai para atualizar sua lista local
        widget.onAppointmentUpdated?.call(_localDoc);
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
    final data = widget.appointmentDoc;
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
              const SizedBox(height: 40),
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
        await Supabase.instance.client
          .from('appointments')
          .delete()
          .eq('id', widget.appointmentDoc['id']);

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
            if (mounted) {
              Navigator.pop(context);
            }
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('â Œ Erro ao excluir: $e'),
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
    // ðŸ›¡ï¸  Ajuste de Padding: Se for embutido, usa menos espaço lateral
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
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: actions,
        ),
      ),
      body: content,
    );
  }

  Widget _buildBodyContent(double hPadding) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final data = _localDoc.isNotEmpty ? _localDoc : widget.appointmentDoc;
    final shopId = data['shop_id'] ?? data['shopId'];
    final status = data['status'] ?? 'agendado';

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: hPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 15),
          _buildCompactHeader(status),
          const SizedBox(height: 15),
          _buildFinancialHeroPanel(data),
          const SizedBox(height: 15),
          _buildForm(shopId),
          const SizedBox(height: 15),
          _buildSystemLog(data),
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
                  onPressed: () {
                    if (widget.onEdit != null) {
                      widget.onEdit!();
                    } else {
                      setState(() => _isEditing = true);
                    }
                  },
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

  // --- NAVEGAÇÃO PARA O PERFIL DO CLIENTE ---
  Future<void> _navigateToClientProfile() async {
    if (_selectedClientId == null) return;
    setState(() => _isLoading = true);
    try {
      // shop_id pode estar em snake_case ou camelCase
      final shopId = widget.appointmentDoc['shop_id'] ??
          widget.appointmentDoc['shopId'];

      // Busca dados completos do cliente na tabela users
      final userDoc = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', _selectedClientId!)
          .maybeSingle();

      Map<String, dynamic> clientData;
      if (userDoc != null) {
        clientData = Map<String, dynamic>.from(userDoc);
        // Garante chaves compatíveis com ClientDetailsPage
        clientData['nome'] = clientData['name'] ?? clientData['nome'] ?? _selectedClientName ?? '';
        clientData['telefone'] = clientData['phone'] ?? clientData['telefone'] ?? _selectedClientPhone ?? '';
        // Foto do Google ou cadastro (photo_url → foto → foto_perfil)
        final photoFromDb = clientData['photo_url']?.toString() ?? '';
        if (photoFromDb.isNotEmpty) {
          clientData['foto'] = photoFromDb;
          clientData['foto_perfil'] = photoFromDb;
        } else if (_selectedClientPhoto != null && _selectedClientPhoto!.isNotEmpty) {
          clientData['foto'] = _selectedClientPhoto;
          clientData['photo_url'] = _selectedClientPhoto;
        }
      } else {
        // Fallback: usa os dados que já temos no agendamento
        clientData = {
          'nome': _selectedClientName ?? '',
          'name': _selectedClientName ?? '',
          'telefone': _selectedClientPhone ?? '',
          'origem': 'manual',
        };
        if (_selectedClientPhoto != null && _selectedClientPhoto!.isNotEmpty) {
          clientData['foto'] = _selectedClientPhoto;
          clientData['photo_url'] = _selectedClientPhoto;
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

  // --- HEADER COMPACTO (Focado no Cliente) ---
  Widget _buildCompactHeader(String status) {
    Color statusColor = status == 'confirmado'
        ? Colors.green
        : (status == 'cancelado' ? Colors.red : Colors.orange);

    return Container(
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
        ],
      ),
      child: Row(
        children: [
            // Avatar clicável → leva ao perfil
            GestureDetector(
              onTap: _selectedClientId != null ? _navigateToClientProfile : null,
              child: CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.1),
                backgroundImage: _selectedClientPhoto != null && _selectedClientPhoto!.isNotEmpty
                    ? NetworkImage(_selectedClientPhoto!)
                    : null,
                onBackgroundImageError: _selectedClientPhoto != null ? (_, __) {} : null,
                child: (_selectedClientPhoto == null || _selectedClientPhoto!.isEmpty)
                    ? const Icon(Icons.person, color: AppColors.primaryPurple, size: 22)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nome clicável com indicação visual
                  GestureDetector(
                    onTap: _selectedClientId != null ? _navigateToClientProfile : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _selectedClientName ?? "Cliente",
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: _selectedClientId != null
                                  ? AppColors.primaryPurple
                                  : Colors.black87,
                              decoration: _selectedClientId != null
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
                              decorationColor: AppColors.primaryPurple.withValues(alpha: 0.5),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_selectedClientId != null) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 11,
                            color: AppColors.primaryPurple,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (_selectedClientPhone != null &&
                      _selectedClientPhone!.isNotEmpty &&
                      _selectedClientPhone != 'Não informado')
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            final phone = _selectedClientPhone!
                                .replaceAll(RegExp(r'\D'), '');
                            final url = 'https://wa.me/55$phone';
                            if (await canLaunchUrl(Uri.parse(url))) {
                              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                            }
                          },
                          icon: const Icon(Icons.chat_rounded, size: 14),
                          label: const Text("WhatsApp", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                            minimumSize: const Size(0, 30),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          ),
                        ),
                      ],
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
    );
  }

  // --- PAINEL FINANCEIRO ULTRA-COMPACTO ---
  Widget _buildFinancialHeroPanel(Map<String, dynamic> data) {
    // ✅ Prioriza total_value ou valor_com_desconto como o preço final pago
    final double total = double.tryParse(data['total_value']?.toString() ??
            data['valor_com_desconto']?.toString() ??
            data['total_payable']?.toString() ??
            data['total_price']?.toString() ??
            data['valor_total']?.toString() ??
            data['price']?.toString() ??
            data['valor']?.toString() ??
            "0") ??
        0.0;
    final double pago =
        double.tryParse(data['paid_amount']?.toString() ?? data['valor_pago']?.toString() ?? "0") ?? 0.0;
    final double restante = total - pago;
    final String paymentMethod = _selectedPaymentMethod ?? data['payment_method']?.toString() ?? 'Não informado';

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
          Column(
            children: [
              // Exibição de Desconto (Preço Original Riscado com Cálculos Reais)
              Builder(
                builder: (context) {
                  // Valor final que o cliente paga
                  double finalPrice = double.tryParse(
                    data['valor_com_desconto']?.toString() ?? 
                    data['total_value']?.toString() ?? 
                    data['total_price']?.toString() ?? 
                    data['labor_value']?.toString() ?? '0'
                  ) ?? 0;

                  // Valor original (tabela)
                  double originalPrice = double.tryParse(
                    data['labor_value']?.toString() ?? 
                    data['total_price']?.toString() ?? 
                    data['total_value']?.toString() ?? '0'
                  ) ?? 0;
                  
                  final bool isBirthday = data['birthday_discount_applied'] == true;
                  final bool isCoupon = data['coupon_applied'] == true;
                  
                  final double descontoGravado = double.tryParse(data['discount_amount']?.toString() ?? '0') ?? 0;
                  
                  // Se os preços forem iguais mas houver flag de desconto, calculamos o original baseado no percentual (legado)
                  if (originalPrice <= finalPrice + 0.01 && descontoGravado < 0.01) {
                    if (isBirthday && _shopBirthdayDiscount > 0) {
                      originalPrice = finalPrice / (1 - (_shopBirthdayDiscount / 100));
                    } else if (isCoupon) {
                      double couponPercent = double.tryParse(data['coupon_discount_percent']?.toString() ?? '0') ?? 0;
                      if (couponPercent > 0) {
                        originalPrice = finalPrice / (1 - (couponPercent / 100));
                      }
                    }
                  }
                  
                  // Prioriza o valor do desconto gravado no banco
                  final double finalDiscount = descontoGravado > 0.01 ? descontoGravado : (originalPrice - finalPrice);
                  final double finalOriginal = originalPrice > finalPrice ? originalPrice : (finalPrice + finalDiscount);
                  
                  final bool temDesconto = finalDiscount > 0.01;
                                           
                  if (temDesconto) {
                    return Column(
                      children: [
                        Text(
                          "${money(finalOriginal)} (- ${money(finalDiscount)})",
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                }
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(money(total),
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(paymentMethod.toUpperCase(), 
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                  ),
                ],
              ),
            ],
          ),
          
          if (data['coupon_applied'] == true || data['birthday_discount_applied'] == true) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (data['coupon_applied'] == true)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.confirmation_number_outlined, size: 12, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          "CUPOM: ${data['coupon_code'] ?? 'ATIVO'}",
                          style: const TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                if (data['birthday_discount_applied'] == true)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.pink.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cake_outlined, size: 12, color: Colors.pink),
                        SizedBox(width: 4),
                        Text(
                          "ANIVERSÁRIO",
                          style: TextStyle(color: Colors.pink, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
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
                const Text("JÁ PAGO",
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

          // NOVO: Botão de verificar pagamento PIX manualmente
          if (restante > 0.01 && data['payment_id'] != null && data['payment_id'].toString().isNotEmpty && (data['metodo_pagamento']?.toString().toLowerCase().contains('pix') ?? false)) ...[
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text("Verificar Pagamento Pix"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple.withValues(alpha: 0.1),
                  foregroundColor: AppColors.primaryPurple,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                onPressed: () async {
                  setState(() => _isLoading = true);
                  try {
                    final statusPix = await MercadoPagoService.verificarStatusPix(
                      shopId: data['shop_id'] ?? data['shopId'],
                      paymentId: data['payment_id'],
                    );
                    if (statusPix == 'approved') {
                      final novoPago = pago + restante;
                      await Supabase.instance.client
                          .from('appointments')
                          .update({
                        'status': 'confirmado',
                        'valor_pago': novoPago,
                        'restante_a_pagar': 0,
                        'pago_em': DateTime.now().toIso8601String(),
                      }).eq('id', widget.appointmentDoc['id']);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Pagamento confirmado e agendamento atualizado!'), backgroundColor: Colors.green),
                        );
                        _loadData();
                      }
                    } else if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Status atual do pagamento: $statusPix'), backgroundColor: Colors.orange),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro ao verificar pagamento: $e'), backgroundColor: Colors.red),
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                },
              ),
            ),
          ],
          // NOVO: Botão Marcar como Pago (Aprovação Manual)
          if (restante > 0.01) ...[
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text("Marcar como Pago"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.withValues(alpha: 0.1),
                  foregroundColor: Colors.green,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                onPressed: () => _marcarComoPagoManual(pago, restante),
              ),
            ),
          ] else if (pago > 0.01) ...[
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.undo, size: 16),
                label: const Text("Marcar como Não Pago"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withValues(alpha: 0.1),
                  foregroundColor: Colors.red,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                onPressed: () => _desmarcarComoPagoManualmente(total),
              ),
            ),
          ],
          
          // ✅ BOTÃO: VER DETALHES TÉCNICOS DA TRANSAÇÃO (NOVA PÁGINA)
          if (data['metadata']?['payment_id'] != null) ...[
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                label: const Text("Ver Detalhes do Pagamento"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TransactionDetailsPage(
                        appointmentData: data,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _marcarComoPagoManual(double pago, double restante) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Marcar como Pago"),
        content: const Text(
            "Tem certeza que deseja marcar este agendamento como aprovado? O valor pendente será zerado e o status será alterado para confirmado."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text("Confirmar"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      final novoPago = pago + restante;
      await Supabase.instance.client
          .from('appointments')
          .update({
            'status': 'confirmado',
            'paid_amount': novoPago,
            'remaining_amount': 0,
            'payment_method': _selectedPaymentMethod ?? 'Manual',
            'payment_status': 'pago',
          })
          .eq('id', widget.appointmentDoc['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pagamento confirmado manualmente!'), backgroundColor: Colors.green),
        );
        setState(() {
          _isEditing = false;
          _loadData();
        });
      }
    } catch (e) {
      debugPrint('Erro ao atualizar pagamento: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar pagamento: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- FORMULÁRIO COMPACTO ---
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
        _buildPaymentMethodField(),
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
      final data = widget.appointmentDoc;
      final shopId = data['shop_id'] ?? data['shopId'];

      final userDoc = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', _selectedClientId!)
          .maybeSingle();

      Map<String, dynamic> clientData;
      if (userDoc != null) {
        clientData = userDoc;
        clientData['nome'] = clientData['name'] ?? clientData['nome'];
        clientData['telefone'] = clientData['phone'] ?? clientData['telefone'];
      } else {
        clientData = {
          'nome': _selectedClientName,
          'telefone': _selectedClientPhone,
          'origem': 'manual',
        };
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

  Widget _buildPaymentMethodField() {
    if (!_isEditing) {
      return _buildEditableField(
        "Forma de Pagamento",
        Icons.payment_outlined,
        false,
        null,
        _selectedPaymentMethod ?? "Não informado",
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.payment_outlined,
                    size: 18, color: AppColors.primaryPurple)),
            const SizedBox(width: 12),
            const Text("Forma de Pagamento",
                style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _paymentChip("Pix", Icons.pix),
            const SizedBox(width: 8),
            _paymentChip("Cartão", Icons.credit_card),
            const SizedBox(width: 8),
            _paymentChip("Pessoalmente", Icons.person_pin_circle_outlined),
          ],
        ),
      ],
    );
  }

  Widget _paymentChip(String label, IconData icon) {
    final String current = (_selectedPaymentMethod ?? '').toString().trim().toLowerCase();
    final String target = label.trim().toLowerCase();
    
    final bool isSelected = current == target ||
        (current == 'no local' && target == 'pessoalmente') ||
        (current == 'pessoalmente' && target == 'no local') ||
        (current == 'cartao' && target == 'cartão') ||
        (current == 'cartão' && target == 'cartao');
    
    return Expanded(
      child: ChoiceChip(
        showCheckmark: false,
        label: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.grey),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : Colors.black87)),
          ],
        ),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) {
            setState(() => _selectedPaymentMethod = label);
          }
        },
        selectedColor: AppColors.primaryPurple,
        backgroundColor: Colors.grey.shade100,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildPriceField() {
    final bool hasDiscount = _discountAmount > 0.01 || (_basePrice > _selectedPrice! + 0.01);
    
    return Row(
      children: [
        Container(
            padding: const EdgeInsets.all(8),
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
              Row(
                children: [
                  const Text("Valor do Serviço",
                      style: TextStyle(fontSize: 10, color: Colors.grey)),
                  if (_isBirthdayDiscountApplied)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: Colors.pink.shade50, borderRadius: BorderRadius.circular(4)),
                      child: Text("ANIVERSÁRIO 🎂", style: TextStyle(color: Colors.pink.shade400, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  if (_isCouponApplied)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                      child: Text("CUPOM: ${_couponCode ?? 'ATIVO'}", style: TextStyle(color: Colors.blue.shade400, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              const SizedBox(height: 1),
              _isEditing
                  ? SizedBox(
                      height: 35,
                      child: TextField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                            border: InputBorder.none,
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: AppColors.primaryPurple, width: 2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.transparent,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
                        onChanged: (v) {
                          final parsed = double.tryParse(v.replaceAll(',', '.'));
                          if (parsed != null) _selectedPrice = parsed;
                        },
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          money(_selectedPrice!),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.primaryPurple),
                        ),
                        if (hasDiscount) ...[
                          const SizedBox(width: 6),
                          Text(
                            money(_basePrice),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "-${money(_discountAmount)}",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green.shade600,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
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
      final data = widget.appointmentDoc;
      final shopId = data['shop_id'] ?? data['shopId'];
      final serviceId = _selectedServiceId ?? data['service_id'] ?? data['servicoId'];
      final profId =
          _selectedProfessionalId ?? data['professional_id'] ?? data['profissionalId'];

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
        Supabase.instance.client.from('shops').select().eq('id', shopId).maybeSingle(),
        Supabase.instance.client.from('services').select().eq('id', serviceId).maybeSingle(),
        Supabase.instance.client.from('employees').select().eq('id', profId).maybeSingle(),
      ]);

      final shopDoc = results[0];
      final serviceDoc = results[1];
      final profDoc = results[2];

      if (shopDoc == null || serviceDoc == null || profDoc == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Não foi possível carregar os dados da agenda.')),
          );
        }
        return;
      }

      final shopData = shopDoc;
      final Map<String, dynamic> shopConfig =
          shopData['config'] as Map<String, dynamic>? ?? {};
      final int intervalMinutes =
          (shopConfig['intervalo_agenda_min'] as num?)?.toInt() ?? 60;

      // Group all pending non-saved state edits
      final pendingUpdates = <String, dynamic>{
        if (_selectedClientId != null) 'client_id': _selectedClientId,
        if (_selectedClientName != null) 'client_name': _selectedClientName,
        if (_selectedServiceId != null) 'service_id': _selectedServiceId,
        if (_selectedServiceName != null) 'service_name': _selectedServiceName,
        if (_selectedProfessionalId != null)
          'professional_id': _selectedProfessionalId,
        if (_selectedProfessionalName != null)
          'professional_name': _selectedProfessionalName,
        if (_selectedProfessionalFoto != null)
          'professional_photo': _selectedProfessionalFoto,
        if (_selectedProfessionalCargo != null)
          'professional_role': _selectedProfessionalCargo,
        if (_selectedServiceDuration != null)
          'duration_min': _selectedServiceDuration,
        'total_price': _selectedPrice ??
            double.tryParse(_priceController.text.replaceAll(',', '.')) ??
            0.0,
        'price': _selectedPrice ??
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
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('shop_clients')
          .stream(primaryKey: ['id'])
          .eq('shop_id', shopId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();

        final docs = snapshot.data!;
        if (docs.isEmpty) {
          return const Text("Nenhum cliente cadastrado",
              style: TextStyle(fontSize: 13, color: Colors.grey));
        }

        return Autocomplete<Map<String, dynamic>>(
          initialValue: TextEditingValue(text: _selectedClientName ?? ''),
          optionsBuilder: (TextEditingValue textEditingValue) {
            if (textEditingValue.text.isEmpty) {
              return docs;
            }
            return docs.where((doc) {
              final data = doc;
              final nome = (data['nome'] ?? '').toString().toLowerCase();
              final search = textEditingValue.text.toLowerCase();
              return nome.contains(search);
            });
          },
          displayStringForOption: (Map<String, dynamic> option) {
            final data = option;
            return data['nome'] ?? '';
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Buscar ou digitar cliente',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
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
          onSelected: (Map<String, dynamic> selection) {
            final data = selection;
            setState(() {
              _selectedClientId = selection['user_id'] ?? selection['id'];
              _selectedClientName = data['nome'];
            });
          },
        );
      },
    );
  }

  Widget _buildServiceDropdown(String shopId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('services')
          .stream(primaryKey: ['id'])
          .map((list) => list.where((d) => d['shop_id'] == shopId && (d['is_active'] ?? d['ativo']) == true).toList()),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        
        // WORKAROUND: Client-side filtering because of compilation issues with stream.eq()
        final filteredDocs = snapshot.data!;

        if (filteredDocs.isEmpty) {
          return const Text("Nenhum serviço ativo",
              style: TextStyle(fontSize: 13, color: Colors.grey));
        }

        // Verifica se o serviço selecionado existe na lista
        final sortedDocs = filteredDocs
          ..sort((a, b) {
            final nomeA = (a['nome'] ?? '').toString().toLowerCase();
            final nomeB = (b['nome'] ?? '').toString().toLowerCase();
            return nomeA.compareTo(nomeB);
          });

        return LayoutBuilder(
          builder: (context, constraints) => Autocomplete<Map<String, dynamic>>(
            initialValue: TextEditingValue(text: _selectedServiceName ?? ''),
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) return sortedDocs;
              return sortedDocs.where((doc) {
                final name = (doc['name'] ?? '').toString().toLowerCase();
                return name.contains(textEditingValue.text.toLowerCase());
              });
            },
            displayStringForOption: (option) => option['name'] ?? '',
            onSelected: (selection) {
              final data = selection;
              final newPrice = double.tryParse(data['price']?.toString() ?? '0') ?? 0.0;
              final newDur = int.tryParse(data['duration_min']?.toString() ?? '30') ?? 30;
              setState(() {
                _selectedServiceId = data['id'].toString();
                _selectedServiceName = data['name'];
                _selectedPrice = newPrice;
                _selectedServiceDuration = newDur;
                _priceController.text = newPrice.toStringAsFixed(2).replaceAll('.', ',');

                // Reset professional and date
                _selectedProfessionalId = null;
                _selectedProfessionalName = null;
                _selectedProfessionalFoto = null;
                _selectedProfessionalCargo = null;
                _selectedDate = null;
                _selectedTime = null;
              });
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar serviço...',
                  hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  suffixIcon: controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            controller.clear();
                            setState(() {
                              _selectedServiceId = null;
                              _selectedServiceName = null;
                            });
                          },
                        )
                      : null,
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: constraints.maxWidth,
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (ctx, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          title: Text(option['name'] ?? '', style: const TextStyle(fontSize: 13)),
                          subtitle: Text('R\$ ${option['price'] ?? '0.00'}', style: const TextStyle(fontSize: 11)),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildProfessionalDropdown(String shopId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('employees')
          .stream(primaryKey: ['id'])
          .map((list) => list.where((d) => (d['shop_id'] ?? d['shopId']) == shopId).toList()),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox();
        final profs = snapshot.data!.where((d) {
          final skills = d['servicos_habilidade'] as List? ?? [];
          return skills.isEmpty || skills.contains(_selectedServiceId);
        }).toList();

        if (profs.isEmpty) {
          return const Text("Nenhum profissional apto para este serviço",
              style: TextStyle(fontSize: 12, color: Colors.red));
        }

        return LayoutBuilder(
          builder: (context, constraints) => Autocomplete<Map<String, dynamic>>(
            initialValue: TextEditingValue(text: _selectedProfessionalName ?? ''),
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) return profs;
              return profs.where((doc) {
                final name = (doc['name'] ?? '').toString().toLowerCase();
                return name.contains(textEditingValue.text.toLowerCase());
              });
            },
            displayStringForOption: (option) => option['name'] ?? '',
            onSelected: (selection) {
              final data = selection;
              setState(() {
                _selectedProfessionalId = data['id'].toString();
                _selectedProfessionalName = data['name'];
                _selectedProfessionalFoto = data['photo_url'] ?? data['foto_url'];
                _selectedProfessionalCargo = data['role'] ?? data['cargo'];

                // Mudou profissional > Zera Data/Hora
                _selectedDate = null;
                _selectedTime = null;
              });
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Buscar profissional...',
                  hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  suffixIcon: controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            controller.clear();
                            setState(() {
                              _selectedProfessionalId = null;
                              _selectedProfessionalName = null;
                            });
                          },
                        )
                      : null,
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: constraints.maxWidth,
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (ctx, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundImage: (option['photo_url'] ?? option['foto_url']) != null
                                ? NetworkImage(option['photo_url'] ?? option['foto_url'])
                                : null,
                            child: (option['photo_url'] ?? option['foto_url']) == null
                                ? const Icon(Icons.person, size: 14)
                                : null,
                          ),
                          title: Text(option['name'] ?? option['nome'] ?? '', style: const TextStyle(fontSize: 13)),
                          subtitle: Text(option['role'] ?? option['cargo'] ?? 'Profissional', style: const TextStyle(fontSize: 11)),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // --- LOG DO SISTEMA (AUDITORIA) ---
  Widget _buildSystemLog(Map<String, dynamic> data) {
    final createdAt = data['created_at'] != null ? DateTime.tryParse(data['created_at'].toString()) : null;
    final updatedAt = data['updated_at'] != null ? DateTime.tryParse(data['updated_at'].toString()) : null;
    final scheduledAt = data['scheduled_at'] != null ? DateTime.tryParse(data['scheduled_at'].toString()) : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.history, size: 14, color: Colors.grey),
              SizedBox(width: 8),
              Text("LOG DO AGENDAMENTO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.0)),
            ],
          ),
          const SizedBox(height: 12),
          _buildLogItem("Registro criado em:", createdAt),
          _buildLogItem("Agendado para:", scheduledAt),
          if (updatedAt != null && updatedAt != createdAt) 
            _buildLogItem("Última modificação:", updatedAt),
          const SizedBox(height: 8),
          const Text(
            "* Esta trilha de auditoria é permanente e ajuda no resguardo financeiro da loja.",
            style: TextStyle(fontSize: 9, color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildLogItem(String label, DateTime? date) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          Text(
            date != null ? DateFormat('dd/MM/yyyy HH:mm:ss').format(date) : "Sem registro",
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _desmarcarComoPagoManualmente(double total) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Marcar como Não Pago"),
        content: const Text(
            "Deseja realmente remover o registro de pagamento deste agendamento? O valor pago será zerado e ele voltará ao status pendente."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text("Confirmar"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client
          .from('appointments')
          .update({
            'status': 'agendado',
            'paid_amount': 0,
            'remaining_amount': total,
          })
          .eq('id', widget.appointmentDoc['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pagamento removido com sucesso!'), backgroundColor: Colors.orange),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
