import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_colors.dart';
import '../../pages/checkout_page.dart';

import '../../core/utils/availability_utils.dart';
import '../../core/services/client_verification_service.dart';
import '../clients/widgets/restricted_client_view.dart';

class BookingPage extends StatefulWidget {
  final DocumentSnapshot shop;
  final DocumentSnapshot serviceDoc;
  final Map<String, dynamic>? selectedVariation;
  final bool isReschedule;
  final String? appointmentId;
  final bool fromSubdomain;
  final DateTime? oldDate;
  final String? oldProfessional;
  final String? oldServiceName;

  const BookingPage({
    super.key,
    required this.shop,
    required this.serviceDoc,
    this.selectedVariation,
    this.isReschedule = false,
    this.appointmentId,
    this.fromSubdomain = false,
    this.oldDate,
    this.oldProfessional,
    this.oldServiceName,
  });

  Map<String, dynamic> get serviceData =>
      serviceDoc.data() as Map<String, dynamic>;
  String get serviceId => serviceDoc.id;

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  DocumentSnapshot? _selectedProfessional;

  late String shopId;
  late Map<String, dynamic> shopData;

  Map<String, dynamic> _shopConfig = {};
  int _intervalMinutes = 60;
  bool _clientChoosesProfessional = true;
  // o controle de evitar buracos é lido via shopConfig quando necessário
  int _bookingWindowDays = 90;
  int _minAdvanceHours = 7;

  bool _isRestricted = false;
  bool _loadingRestriction = true;

  @override
  void initState() {
    super.initState();
    shopId = widget.shop.id;
    shopData = widget.shop.data() as Map<String, dynamic>;
    _loadShopSettings();
    _checkRestriction();
  }

  Future<void> _checkRestriction() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      try {
        final status =
            await ClientVerificationService.getClientStatus(user.uid, shopId);
        if (status['isProblematic'] == true) {
          if (mounted) {
            setState(() {
              _isRestricted = true;
              _loadingRestriction = false;
            });
          }
          return;
        }
      } catch (e) {
        debugPrint('❌ Erro checkRestriction: $e');
      }
    }
    if (mounted) {
      setState(() {
        _loadingRestriction = false;
      });
    }
  }

  void _loadShopSettings() {
    if (shopData.containsKey('config')) {
      _shopConfig = shopData['config'] as Map<String, dynamic>;
      setState(() {
        _intervalMinutes = _shopConfig['intervalo_agenda_min'] ?? 60;
        _clientChoosesProfessional =
            _shopConfig['cliente_escolhe_prof'] ?? true;
        _bookingWindowDays = _shopConfig['janela_agendamento_dias'] ?? 90;
        _minAdvanceHours = _shopConfig['limite_minimo_agendamento_horas'] ?? 7;
      });
    }
  }

  void _autoSelectFirstAvailableDate(DocumentSnapshot profDoc) {
    final profData = profDoc.data() as Map<String, dynamic>;
    List<dynamic> rawWorkDays = profData['dias_trabalho'] ?? [1, 2, 3, 4, 5, 6];
    List<int> workDays =
        rawWorkDays.map((e) => int.parse(e.toString())).toList();

    DateTime testDate = DateTime.now();

    if (testDate.hour >= 18) {
      testDate = testDate.add(const Duration(days: 1));
    }

    for (int i = 0; i < _bookingWindowDays; i++) {
      if (workDays.contains(testDate.weekday)) {
        // encontrado primeiro dia disponível (não armazenamos na página pai)
        break;
      }
      testDate = testDate.add(const Duration(days: 1));
    }
  }

  Widget _buildHeader() {
    String serviceName = widget.serviceData['nome'];
    if (widget.selectedVariation != null) {
      serviceName += " (${widget.selectedVariation!['name']})";
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.primaryPurple,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
              color: AppColors.primaryPurple.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 10),
              const Text("Agendamento",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.15))),
            child: Row(
              children: [
                Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.cut,
                        color: AppColors.primaryPurple, size: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(serviceName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                          "${widget.serviceData['tempo_min'] ?? 30} min • ${currencyFormat.format(widget.selectedVariation?['price'] ?? widget.serviceData['preco'])}",
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfessionalList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('employees')
          .where('shopId', isEqualTo: shopId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint(
              'âŒ BookingPage: ERRO ao carregar profissionais: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text("Erro ao carregar profissionais: ${snapshot.error}"),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryPurple));
        }

        final profs = snapshot.data!.docs.where((d) {
          final skills =
              (d.data() as Map)['servicos_habilidade'] as List? ?? [];
          return skills.isEmpty || skills.contains(widget.serviceId);
        }).toList();

        if (profs.isEmpty) {
          return const Center(
              child: Text("Nenhum profissional disponível para este serviço."));
        }

        if (!_clientChoosesProfessional) {
          if (_selectedProfessional == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                final selected = profs.first;
                setState(() {
                  _selectedProfessional = selected;
                });
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookingTimePage(
                      shop: widget.shop,
                      serviceDoc: widget.serviceDoc,
                      selectedVariation: widget.selectedVariation,
                      professionalDoc: selected,
                      shopConfig: _shopConfig,
                      intervalMinutes: _intervalMinutes,
                      minAdvanceHours: _minAdvanceHours,
                      isReschedule: widget.isReschedule,
                      appointmentId: widget.appointmentId,
                    ),
                  ),
                );
              }
            });
          }
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryPurple));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Text("Quem vai te atender?",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 15,
                    mainAxisSpacing: 15,
                    childAspectRatio: 0.8),
                itemCount: profs.length,
                itemBuilder: (context, index) {
                  final doc = profs[index];
                  final data = doc.data() as Map<String, dynamic>;
                  final isSelected = _selectedProfessional?.id == doc.id;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        setState(() {
                          _selectedProfessional = doc;
                          _autoSelectFirstAvailableDate(doc);
                        });
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BookingTimePage(
                              shop: widget.shop,
                              serviceDoc: widget.serviceDoc,
                              selectedVariation: widget.selectedVariation,
                              professionalDoc: doc,
                              shopConfig: _shopConfig,
                              intervalMinutes: _intervalMinutes,
                              minAdvanceHours: _minAdvanceHours,
                              fromSubdomain: widget.fromSubdomain,
                            ),
                          ),
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primaryPurple
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: isSelected
                                  ? AppColors.primaryPurple
                                  : Colors.transparent,
                              width: 2),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 35,
                              backgroundColor: Colors.grey[100],
                              backgroundImage: data['foto_url'] != null
                                  ? NetworkImage(data['foto_url'])
                                  : null,
                              child: data['foto_url'] == null
                                  ? Text(data['nome'][0].toUpperCase(),
                                      style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? AppColors.primaryPurple
                                              : Colors.grey))
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Text(data['nome'],
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRestriction) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryPurple),
        ),
      );
    }

    if (_isRestricted) {
      return RestrictedClientView(
        onRefresh: () async {
          setState(() {
            _isRestricted = false;
            _loadingRestriction = true;
          });
          await _checkRestriction();
        },
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildProfessionalList()),
        ],
      ),
    );
  }
}

// ========================================
// PÁGINA DE SELEÇÃO DE DATA - SEM PROBLEMAS
// ========================================
class BookingTimePage extends StatefulWidget {
  final DocumentSnapshot shop;
  final DocumentSnapshot serviceDoc;
  final Map<String, dynamic>? selectedVariation;
  final DocumentSnapshot professionalDoc;
  final Map<String, dynamic> shopConfig;
  final int intervalMinutes;
  final int minAdvanceHours;
  final bool isReschedule;
  final String? appointmentId;
  final bool fromSubdomain;

  const BookingTimePage({
    super.key,
    required this.shop,
    required this.serviceDoc,
    this.selectedVariation,
    required this.professionalDoc,
    required this.shopConfig,
    required this.intervalMinutes,
    required this.minAdvanceHours,
    this.isReschedule = false,
    this.appointmentId,
    this.fromSubdomain = false,
  });

  Map<String, dynamic> get serviceData =>
      serviceDoc.data() as Map<String, dynamic>;

  @override
  State<BookingTimePage> createState() => _BookingTimePageState();
}

class _BookingTimePageState extends State<BookingTimePage> {
  DateTime? _selectedDate;
  int _bookingWindowDays = 90;
  bool _isVip = false;
  int _vipExtraDays = 0;
  bool _isRestricted = false;

  @override
  void initState() {
    super.initState();
    debugPrint(
        'ðŸš€ BookingPage: initState | shopId: ${widget.shop.id} | serviceId: ${widget.serviceDoc.id}');

    // Proteção de Rota Direta (Web Bypass Prevention)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.isAnonymous) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/');
        }
      }
    });

    _bookingWindowDays = widget.shopConfig['janela_agendamento_dias'] ?? 90;
    _vipExtraDays = (widget.shopConfig['vip_extra_booking_days'] ?? 0).toInt();
    _checkVipStatus();
    _checkRestriction();
  }

  Future<void> _checkRestriction() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      final status = await ClientVerificationService.getClientStatus(
          user.uid, widget.shop.id);
      if (status['isProblematic'] == true) {
        if (mounted) {
          setState(() {
            _isRestricted = true;
          });
        }
      }
    }
  }

  Future<void> _checkVipStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      final status = await ClientVerificationService.getClientStatus(
          user.uid, widget.shop.id);
      if (mounted) {
        setState(() {
          _isVip = status['isVip'] ?? false;
          if (_isVip) {
            _bookingWindowDays += _vipExtraDays;
          }
        });
        // Reinicializa a data automática se o status VIP mudar a janela
        _autoSelectFirstAvailableDate(widget.professionalDoc);
      }
    } else {
      _autoSelectFirstAvailableDate(widget.professionalDoc);
    }
  }

  void _autoSelectFirstAvailableDate(DocumentSnapshot profDoc) {
    final profData = profDoc.data() as Map<String, dynamic>;
    List<dynamic> rawWorkDays = profData['dias_trabalho'] ?? [1, 2, 3, 4, 5, 6];
    List<int> workDays =
        rawWorkDays.map((e) => int.parse(e.toString())).toList();

    final now = DateTime.now();
    // Respeita minAdvanceHours: começa da data mínima permitida
    final minAdvanceDateRaw = now.add(Duration(hours: widget.minAdvanceHours));
    DateTime testDate = DateTime(
        minAdvanceDateRaw.year, minAdvanceDateRaw.month, minAdvanceDateRaw.day);

    for (int i = 0; i < _bookingWindowDays; i++) {
      if (workDays.contains(testDate.weekday)) {
        setState(() {
          _selectedDate = testDate;
        });
        break;
      }
      testDate = testDate.add(const Duration(days: 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isRestricted) {
      return RestrictedClientView(
        onRefresh: () async {
          setState(() {
            _isRestricted = false;
          });
          await _checkRestriction();
        },
      );
    }

    final svcName = widget.serviceData['nome'] ?? 'Serviço';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Calcula a data mínima real permitida baseado em _minAdvanceHours (regra de 3 dias etc)
    final minAdvanceDateRaw = now.add(Duration(hours: widget.minAdvanceHours));
    final minAllowedDate = DateTime(
        minAdvanceDateRaw.year, minAdvanceDateRaw.month, minAdvanceDateRaw.day);

    // firstDate precisa ser no minimo hoje (por conta do componente), mas usaremos a trava real na validacao visual.
    final firstDateBound =
        minAllowedDate.isAfter(today) ? minAllowedDate : today;

    final lastAllowedDay = today.add(Duration(days: _bookingWindowDays));
    final profData = widget.professionalDoc.data() as Map<String, dynamic>;
    List<dynamic> rawWorkDays = profData['dias_trabalho'] ?? [1, 2, 3, 4, 5, 6];
    List<int> workDays =
        rawWorkDays.map((e) => int.parse(e.toString())).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Agendamento - $svcName'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF8F9FD),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // âœ… USANDO CALENDARDATEPICKER - MAIS ESTÁVEL
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8)
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Selecione uma data',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      // ✅ CalendarDatePicker - RÁPIDO E RESPONSIVO
                      CalendarDatePicker(
                        initialDate: () {
                          // Garante que initialDate satisfaz o selectableDayPredicate:
                          // deve ser >= minAllowedDate E ser um dia de trabalho
                          DateTime candidate = _selectedDate ?? firstDateBound;
                          if (candidate.isBefore(firstDateBound)) {
                            candidate = firstDateBound;
                          }
                          // Avança até encontrar um dia de trabalho válido
                          int safety = 0;
                          while ((!workDays.contains(candidate.weekday) ||
                                  candidate.isBefore(minAllowedDate)) &&
                              safety < 60) {
                            candidate = candidate.add(const Duration(days: 1));
                            safety++;
                          }
                          return candidate;
                        }(),
                        firstDate: firstDateBound,
                        lastDate: lastAllowedDay,
                        selectableDayPredicate: (day) {
                          // Bloqueia dias antes do mínimo de antecedência
                          if (day.isBefore(minAllowedDate)) return false;
                          if (day.isAfter(lastAllowedDay)) return false;
                          return workDays.contains(day.weekday);
                        },
                        onDateChanged: (selected) {
                          setState(() {
                            _selectedDate = selected;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // âœ… DATA SELECIONADA
              if (_selectedDate != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primaryPurple),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppColors.primaryPurple),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          DateFormat('EEEE, dd/MM/yyyy', 'pt_BR')
                              .format(_selectedDate!),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              // âœ… BOTÕES
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
                      onPressed: () => Navigator.pop(context),
                      child: const Text('VOLTAR',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selectedDate == null
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BookingSlotsPage(
                                    shop: widget.shop,
                                    serviceDoc: widget.serviceDoc,
                                    selectedVariation: widget.selectedVariation,
                                    professionalDoc: widget.professionalDoc,
                                    shopConfig: widget.shopConfig,
                                    intervalMinutes: widget.intervalMinutes,
                                    minAdvanceHours: widget.minAdvanceHours,
                                    selectedDate: _selectedDate!,
                                    isReschedule: widget.isReschedule,
                                    appointmentId: widget.appointmentId,
                                    fromSubdomain: widget.fromSubdomain,
                                  ),
                                ),
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'VER HORÁRIOS',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================================
// PÁGINA DE SELEÇÃO DE HORÁRIOS
// ========================================
class BookingSlotsPage extends StatefulWidget {
  final DocumentSnapshot shop;
  final DocumentSnapshot serviceDoc;
  final Map<String, dynamic>? selectedVariation;
  final DocumentSnapshot professionalDoc;
  final Map<String, dynamic> shopConfig;
  final int intervalMinutes;
  final int minAdvanceHours;
  final DateTime selectedDate;
  final bool isReschedule;
  final String? appointmentId;
  final bool fromSubdomain;

  // ── Props opcionais para o modo de edição do dono ──────────────────────
  // Nenhuma dessas props afeta o comportamento padrão (cliente).
  /// Id do agendamento sendo editado — excluído do cálculo de ocupação.
  final String? ownerExcludeAppointmentId;

  /// Horário original do agendamento ("HH:mm") — exibe badge "Horário atual".
  final String? ownerHighlightedSlotTime;

  /// Quando true, slots ocupados ficam clicáveis (privilégio do dono).
  final bool allowOccupiedSelection;

  /// Callback chamado ao selecionar um slot que já está ocupado.
  /// Recebe o horário selecionado e os dados do agendamento conflitante.
  final void Function(String slot, Map<String, dynamic> conflictData)?
      onOccupiedSlotSelected;

  /// Callback exclusivo do modo dono: chamado ao confirmar o horário.
  /// Quando definido, substitui completamente o fluxo de checkout e a cloud
  /// function de reagendamento do cliente. Recebe o [TimeOfDay] selecionado e,
  /// opcionalmente, os dados do agendamento conflitante (sobreposição).
  final void Function(
          TimeOfDay selectedTime, Map<String, dynamic>? conflictData)?
      onOwnerSlotConfirmed;

  // ── Props para a tela de sucesso de reagendamento ─────────────────────
  final DateTime? oldDate;
  final String? oldProfessional;
  final String? oldServiceName;

  const BookingSlotsPage({
    super.key,
    required this.shop,
    required this.serviceDoc,
    this.selectedVariation,
    required this.professionalDoc,
    required this.shopConfig,
    required this.intervalMinutes,
    required this.minAdvanceHours,
    required this.selectedDate,
    this.isReschedule = false,
    this.appointmentId,
    this.fromSubdomain = false,
    // Modo dono — todos opcionais
    this.ownerExcludeAppointmentId,
    this.ownerHighlightedSlotTime,
    this.allowOccupiedSelection = false,
    this.onOccupiedSlotSelected,
    // Callback exclusivo do modo dono: quando definido, substitui checkout/cloud function
    this.onOwnerSlotConfirmed,
    // Dados do agendamento original (para tela de sucesso do reagendamento)
    this.oldDate,
    this.oldProfessional,
    this.oldServiceName,
  });

  Map<String, dynamic> get serviceData =>
      serviceDoc.data() as Map<String, dynamic>;

  @override
  State<BookingSlotsPage> createState() => _BookingSlotsPageState();
}

class _BookingSlotsPageState extends State<BookingSlotsPage> {
  TimeOfDay? _selectedTime;

  /// Dados do último conflito detectado ao selecionar um slot no modo dono.
  Map<String, dynamic>? _lastConflictData;

  @override
  void initState() {
    super.initState();
    debugPrint(
        'ðŸš€ BookingSlotsPage: initState | date: ${widget.selectedDate}');
  }

  @override
  Widget build(BuildContext context) {
    final svcName = widget.serviceData['nome'] ?? 'Serviço';
    final isOwnerConfirmMode = widget.onOwnerSlotConfirmed != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isOwnerConfirmMode
            ? 'Reagendar — $svcName'
            : 'Horários - $svcName'),
        backgroundColor: AppColors.primaryPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF8F9FD),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    "Data: ${DateFormat('dd/MM/yyyy').format(widget.selectedDate)}",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildSlotsList()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
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
                      onPressed: () => Navigator.pop(context),
                      child: const Text('VOLTAR',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _selectedTime == null
                          ? null
                          : isOwnerConfirmMode
                              // ── Modo dono: chama callback (sem checkout, sem cloud fn) ──
                              ? () => widget.onOwnerSlotConfirmed!(
                                    _selectedTime!,
                                    _lastConflictData,
                                  )
                              // ── Modo cliente: fluxo original inalterado ──
                              : () async {
                                  final shopId = widget.shop.id;
                                  final shopData = widget.shop.data()
                                      as Map<String, dynamic>;

                                  final profData = widget.professionalDoc.data()
                                      as Map<String, dynamic>;

                                  String finalName = widget.serviceData['nome'];
                                  double finalPrice = double.tryParse(widget
                                          .serviceData['preco']
                                          .toString()) ??
                                      0.0;

                                  if (widget.selectedVariation != null) {
                                    finalName +=
                                        " (${widget.selectedVariation!['name']})";
                                    finalPrice = double.tryParse(widget
                                            .selectedVariation!['price']
                                            .toString()) ??
                                        finalPrice;
                                  }

                                  if (widget.isReschedule &&
                                      widget.appointmentId != null) {
                                    final newDateTime = DateTime(
                                      widget.selectedDate.year,
                                      widget.selectedDate.month,
                                      widget.selectedDate.day,
                                      _selectedTime!.hour,
                                      _selectedTime!.minute,
                                    );

                                    final utcDateTimeIso =
                                        newDateTime.toUtc().toIso8601String();

                                    final sm = ScaffoldMessenger.of(context);

                                    // ── Mostra modal de confirmação antes de reagendar ──
                                    final confirmed =
                                        await showModalBottomSheet<bool>(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (_) => _RescheduleConfirmSheet(
                                        oldDate: widget.oldDate,
                                        oldServiceName:
                                            widget.oldServiceName ?? finalName,
                                        oldPrice: widget.oldDate != null
                                            ? finalPrice
                                            : null,
                                        oldProfessional:
                                            widget.oldProfessional ?? '',
                                        newDate: newDateTime,
                                        newServiceName: finalName,
                                        newPrice: finalPrice,
                                        newProfessional:
                                            profData['nome'] ?? 'Profissional',
                                      ),
                                    );

                                    if (confirmed != true) return;
                                    if (!mounted) return;

                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (ctx) => const Center(
                                          child: CircularProgressIndicator()),
                                    );

                                    try {
                                      final functions =
                                          FirebaseFunctions.instance;
                                      await functions
                                          .httpsCallable(
                                              'rescheduleAppointment')
                                          .call({
                                        'appointmentId': widget.appointmentId,
                                        'newDateISO': utcDateTimeIso,
                                        'newServiceId': widget.serviceDoc.id,
                                        'newServiceName': finalName,
                                        'newPrice': finalPrice,
                                        'newProfessionalId':
                                            widget.professionalDoc.id,
                                        'newProfessionalName':
                                            profData['nome'] ?? 'Profissional',
                                      });

                                      if (!mounted) return;

                                      // Em vez de voltar 3 telas, vamos direcionar para a página de sucesso
                                      // passando os dados antigos e novos

                                      Navigator.of(context)
                                          .pop(); // tira o loading dialog

                                      Navigator.pushReplacementNamed(
                                          context, '/reschedule_success',
                                          arguments: {
                                            'appointmentId':
                                                widget.appointmentId,
                                            'newDate': newDateTime,
                                            'newProfessional':
                                                profData['nome'] ??
                                                    'Profissional',
                                            'newServiceName': finalName,
                                            'oldDate': widget.oldDate,
                                            'oldProfessional':
                                                widget.oldProfessional ?? '',
                                            'oldServiceName': widget
                                                    .oldServiceName ??
                                                widget.serviceData['nome'] ??
                                                '',
                                          });
                                    } catch (e) {
                                      if (!mounted) return;
                                      if (Navigator.canPop(context)) {
                                        Navigator.pop(context);
                                      }
                                      final errMsg =
                                          e is FirebaseFunctionsException
                                              ? (e.message ?? e.toString())
                                              : e.toString();
                                      sm.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'Erro ao reagendar: $errMsg'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (c) => CheckoutPage(
                                          shopId: shopId,
                                          shopData: shopData,
                                          shopConfig: widget.shopConfig,
                                          serviceDoc: widget.serviceDoc,
                                          serviceNameOverride: finalName,
                                          servicePriceOverride: finalPrice,
                                          professionalDoc:
                                              widget.professionalDoc,
                                          date: widget.selectedDate,
                                          time: _selectedTime!,
                                          fromSubdomain: widget.fromSubdomain,
                                        ),
                                      ),
                                    );
                                  }
                                },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isOwnerConfirmMode
                            ? AppColors.primaryPurple
                            : widget.isReschedule
                                ? AppColors.primaryPurple
                                : const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        isOwnerConfirmMode
                            ? 'CONFIRMAR HORÁRIO'
                            : widget.isReschedule
                                ? 'CONFIRMAR HORÁRIO'
                                : 'CONTINUAR',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAppointmentsAndIntervals(
      DateTime startDay, DateTime endDay, bool isOwnerMode) async {
    final querySnapshot = await FirebaseFirestore.instance
        .collection('appointments')
        .where('shopId', isEqualTo: widget.shop.id)
        .where('profissionalId', isEqualTo: widget.professionalDoc.id)
        .where('data_agendamento', isGreaterThanOrEqualTo: startDay)
        .where('data_agendamento', isLessThanOrEqualTo: endDay)
        .get();

    List<Map<String, dynamic>> results = [];

    for (var d in querySnapshot.docs) {
      final data = d.data();
      final status = (data['status'] ?? '').toString().toLowerCase();

      if (status == 'cancelado' ||
          status == 'recusado' ||
          status == 'excluido') {
        continue;
      }

      if (widget.ownerExcludeAppointmentId != null &&
          d.id == widget.ownerExcludeAppointmentId) {
        continue;
      }

      int? agDuration = int.tryParse(data['duracao_min']?.toString() ?? '') ??
          int.tryParse(data['duracao']?.toString() ?? '');

      if (agDuration == null) {
        String? savedServiceId = data['servicoId'] ?? data['servico_id'];
        if (savedServiceId != null && savedServiceId.isNotEmpty) {
          try {
            final svcDoc = await FirebaseFirestore.instance
                .collection('services')
                .doc(savedServiceId)
                .get();
            if (svcDoc.exists) {
              final svcData = svcDoc.data();
              if (svcData != null) {
                agDuration =
                    int.tryParse(svcData['tempo_min']?.toString() ?? '');
              }
            }
          } catch (_) {}
        }
        agDuration ??= 30; // fallback final
      }

      results.add({
        ...data,
        'id': d.id,
        'computed_duration': agDuration,
      });
    }

    return results;
  }

  Widget _buildSlotsList() {
    final profData = widget.professionalDoc.data() as Map<String, dynamic>;
    int duration =
        int.tryParse(widget.serviceData['tempo_min'].toString()) ?? 30;
    final startDay = DateTime(widget.selectedDate.year,
        widget.selectedDate.month, widget.selectedDate.day);
    final endDay = startDay.add(const Duration(hours: 23, minutes: 59));
    final isOwnerMode = widget.ownerExcludeAppointmentId != null ||
        widget.allowOccupiedSelection;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchAppointmentsAndIntervals(startDay, endDay, isOwnerMode),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryPurple));
        }

        if (snapshot.hasError) {
          debugPrint('❌ BookingSlotsPage: ERRO: ${snapshot.error}');
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text("Erro ao carregar horários: ${snapshot.error}"),
            ),
          );
        }

        final dataList = snapshot.data ?? [];
        final Map<int, Map<String, dynamic>> occupiedSlotData = {};
        List<Map<String, int>> busyIntervals = [];

        for (var data in dataList) {
          final dt = (data['data_agendamento'] as Timestamp).toDate();
          int startMin = dt.hour * 60 + dt.minute;
          int agDuration = data['computed_duration'] as int;
          int endMin = startMin + agDuration;

          busyIntervals.add({"start": startMin, "end": endMin});

          if (isOwnerMode) {
            occupiedSlotData[startMin] = data;
          }
        }

        final preventGaps = widget.shopConfig['evitar_buracos_agenda'] ?? false;

        // Modo dono: gera TODOS os slots do turno (livres + ocupados visíveis)
        // Modo cliente: comportamento original (apenas livres)
        List<String> slots;
        List<String> allSlots = [];
        if (isOwnerMode) {
          // Gera todos os slots do turno, sem filtro de horário passado.
          // Slots que colidem com um serviço em andamento são marcados como occupied.
          final startStr = profData['horario_inicio'] ?? "08:00";
          final endStr = profData['horario_fim'] ?? "18:00";
          int startDayMin = int.parse(startStr.split(':')[0]) * 60 +
              int.parse(startStr.split(':')[1]);
          int endDayMin = int.parse(endStr.split(':')[0]) * 60 +
              int.parse(endStr.split(':')[1]);
          int current = startDayMin;
          while (current + duration <= endDayMin) {
            final h = (current ~/ 60).toString().padLeft(2, '0');
            final m = (current % 60).toString().padLeft(2, '0');
            allSlots.add('$h:$m');
            current += widget.intervalMinutes;
          }
          slots = allSlots;
        } else {
          slots = AvailabilityUtils.generateSmartSlots(
            startStr: profData['horario_inicio'] ?? "08:00",
            endStr: profData['horario_fim'] ?? "18:00",
            interval: widget.intervalMinutes,
            serviceDuration: duration,
            busyIntervals: busyIntervals,
            preventGaps: preventGaps,
            minAdvanceHours: widget.minAdvanceHours,
            selectedDate: widget.selectedDate,
          );
        }

        if (slots.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                "Sem horários disponíveis para este dia.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ),
          );
        }

        // Slot selecionado atual para exibição de aviso inline
        String? selectedConflictWarning;
        if (_selectedTime != null && isOwnerMode) {
          final selMin = _selectedTime!.hour * 60 + _selectedTime!.minute;
          for (final busy in busyIntervals) {
            if (selMin < busy['end']! && selMin + duration > busy['start']!) {
              // Slot selecionado conflita — encontra os dados do agendamento
              for (final entry in occupiedSlotData.entries) {
                if (selMin < entry.key + duration &&
                    selMin + duration > entry.key) {
                  // entry.value disponível para future use (ex: callback de sobreposição)
                  final conflictDt =
                      (entry.value['data_agendamento'] as Timestamp).toDate();
                  final conflictTime =
                      '${conflictDt.hour.toString().padLeft(2, '0')}:${conflictDt.minute.toString().padLeft(2, '0')}';
                  final conflictClient = entry.value['client_nome'] ??
                      entry.value['cliente_nome'] ??
                      'Cliente';
                  selectedConflictWarning =
                      'Este horário já possui um agendamento de $conflictClient às $conflictTime.';
                  break;
                }
              }
              break;
            }
          }
        }

        return SingleChildScrollView(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Aviso inline de sobreposição (apenas modo dono)
                if (selectedConflictWarning != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.orange, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selectedConflictWarning,
                            style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black87,
                                height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: slots.map((t) {
                    final parts = t.split(':');
                    final slotMin =
                        int.parse(parts[0]) * 60 + int.parse(parts[1]);
                    final isSelected = _selectedTime != null &&
                        "${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}" ==
                            t;
                    final isHighlighted =
                        isOwnerMode && widget.ownerHighlightedSlotTime == t;

                    // Verifica se o slot está ocupado e pega os dados do agendamento
                    bool isOccupied = false;
                    Map<String, dynamic>? conflictObj;
                    if (isOwnerMode) {
                      for (final busy in busyIntervals) {
                        if (slotMin < busy['end']! &&
                            slotMin + duration > busy['start']!) {
                          isOccupied = true;
                          for (final entry in occupiedSlotData.entries) {
                            int occupDuration =
                                entry.value['computed_duration'] ?? 30;
                            if (slotMin < entry.key + occupDuration &&
                                slotMin + duration > entry.key) {
                              conflictObj = entry.value;
                              break;
                            }
                          }
                          break;
                        }
                      }
                    }

                    // Cor do chip
                    Color backgroundColor;
                    Color labelColor;
                    bool showWarningBorder = false;
                    if (isSelected && isOccupied) {
                      backgroundColor = Colors.orange.withValues(alpha: 0.2);
                      labelColor = Colors.deepOrange;
                      showWarningBorder = true;
                    } else if (isSelected) {
                      backgroundColor = AppColors.primaryPurple;
                      labelColor = Colors.white;
                    } else if (isOccupied) {
                      backgroundColor = Colors.grey.withValues(alpha: 0.15);
                      labelColor = Colors.grey[600]!;
                    } else {
                      backgroundColor = Colors.white;
                      labelColor = Colors.black87;
                    }

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (isOccupied && !widget.allowOccupiedSelection) {
                              // Comportamento padrão do cliente: slot ocupado não é clicável
                              return;
                            }
                            final p = t.split(':');
                            setState(() => _selectedTime = TimeOfDay(
                                hour: int.parse(p[0]),
                                minute: int.parse(p[1])));
                            if (isOccupied && widget.allowOccupiedSelection) {
                              // Busca dados do conflito para callback
                              Map<String, dynamic>? conflictData;
                              for (final entry in occupiedSlotData.entries) {
                                if (slotMin < entry.key + duration &&
                                    slotMin + duration > entry.key) {
                                  conflictData = entry.value;
                                  break;
                                }
                              }
                              // Armazena no state para usar no onOwnerSlotConfirmed
                              setState(() => _lastConflictData = conflictData);
                              // Chama callback opcional
                              if (widget.onOccupiedSlotSelected != null) {
                                widget.onOccupiedSlotSelected!(
                                    t, conflictData ?? {});
                              }
                            } else {
                              // Slot livre selecionado: limpa conflito
                              setState(() => _lastConflictData = null);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 8),
                            decoration: BoxDecoration(
                              color: backgroundColor,
                              borderRadius: BorderRadius.circular(10),
                              border: showWarningBorder
                                  ? Border.all(color: Colors.orange, width: 2)
                                  : isSelected
                                      ? null
                                      : Border.all(
                                          color: Colors.grey
                                              .withValues(alpha: 0.2)),
                            ),
                            child: Container(
                              // Formato quadradinho para otimizar espaço de tela
                              constraints: BoxConstraints(
                                  minWidth: isOwnerMode ? 72 : 64,
                                  minHeight: isOwnerMode ? 72 : 48),
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (isOccupied && conflictObj != null)
                                    Container(
                                      constraints:
                                          const BoxConstraints(maxWidth: 86),
                                      padding:
                                          const EdgeInsets.only(bottom: 2.0),
                                      child: Text(
                                        "${conflictObj['servico_nome'] ?? 'Serviço'}\n${conflictObj['client_nome'] ?? conflictObj['cliente_nome'] ?? conflictObj['profissional_nome'] ?? ''}",
                                        style: TextStyle(
                                            color: labelColor.withValues(
                                                alpha: 0.9),
                                            fontSize: 9,
                                            height: 1.1,
                                            fontWeight: FontWeight.w600),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  Text(
                                    t,
                                    style: TextStyle(
                                        color: labelColor,
                                        fontWeight: isSelected || isHighlighted
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: (isOccupied && isOwnerMode)
                                            ? 12
                                            : 14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Badge "Horário atual" (modo dono)
                        if (isHighlighted)
                          Positioned(
                            top: -8,
                            right: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryPurple,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'atual',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Widget: Modal de Confirmação de Reagendamento ─────────────────────────
class _RescheduleConfirmSheet extends StatelessWidget {
  final DateTime? oldDate;
  final String oldServiceName;
  final double? oldPrice;
  final String oldProfessional;
  final DateTime newDate;
  final String newServiceName;
  final double newPrice;
  final String newProfessional;

  const _RescheduleConfirmSheet({
    required this.oldDate,
    required this.oldServiceName,
    required this.oldPrice,
    required this.oldProfessional,
    required this.newDate,
    required this.newServiceName,
    required this.newPrice,
    required this.newProfessional,
  });

  String _fmt(DateTime d) {
    const days = [
      'Segunda',
      'Terça',
      'Quarta',
      'Quinta',
      'Sexta',
      'Sábado',
      'Domingo'
    ];
    final day = days[d.weekday - 1];
    final date =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '$day, $date às $time';
  }

  String _fmtPrice(double p) =>
      'R\$ ${p.toStringAsFixed(2).replaceAll('.', ',')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            "Confirmar Reagendamento",
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
            textAlign: TextAlign.center,
          ),
          const Text(
            "Confira as informações antes de confirmar",
            style: TextStyle(fontSize: 13, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Card: Agendamento ATUAL (antes)
          if (oldDate != null) ...[
            _buildCard(
              label: "AGENDAMENTO ATUAL",
              labelColor: Colors.orange.shade700,
              bgColor: Colors.orange.shade50,
              date: oldDate!,
              serviceName: oldServiceName,
              price: oldPrice ?? newPrice,
              professional: oldProfessional,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade200)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryPurple.withValues(alpha: 0.08),
                      ),
                      child: Icon(Icons.arrow_downward_rounded,
                          color: AppColors.primaryPurple, size: 18),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey.shade200)),
                ],
              ),
            ),
          ],

          // Card: NOVO HORÁRIO (depois)
          _buildCard(
            label: "NOVO HORÁRIO",
            labelColor: Colors.green.shade700,
            bgColor: Colors.green.shade50,
            date: newDate,
            serviceName: newServiceName,
            price: newPrice,
            professional: newProfessional,
          ),
          const SizedBox(height: 24),

          // Botões
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: Colors.grey.shade300),
                    foregroundColor: Colors.black54,
                  ),
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("VOLTAR",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("CONFIRMAR REAGENDAMENTO",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String label,
    required Color labelColor,
    required Color bgColor,
    required DateTime date,
    required String serviceName,
    required double price,
    required String professional,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: labelColor.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: labelColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: labelColor,
                    letterSpacing: 0.5)),
          ),
          const SizedBox(height: 10),
          _row(Icons.event_rounded, _fmt(date), labelColor),
          const SizedBox(height: 5),
          _row(Icons.cut_rounded, serviceName, labelColor),
          const SizedBox(height: 5),
          _row(Icons.attach_money_rounded, _fmtPrice(price), labelColor),
          if (professional.isNotEmpty) ...[
            const SizedBox(height: 5),
            _row(Icons.person_rounded, professional, labelColor),
          ],
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text, Color accentColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: accentColor.withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87)),
        ),
      ],
    );
  }
}
