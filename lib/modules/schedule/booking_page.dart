import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../pages/checkout_page.dart';
import '../clients/rescheduling_success_page.dart';
import '../clients/client_register_page.dart';

import '../../core/utils/availability_utils.dart';
import '../../core/utils/work_schedule.dart';
import '../../core/services/client_verification_service.dart';
import '../../core/services/plan_features_service.dart';
import '../../core/constants/plan_features.dart';
import '../clients/widgets/restricted_client_view.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/services/brasilapi_service.dart';

class BookingPage extends StatefulWidget {
  final Map<String, dynamic> shop;
  final Map<String, dynamic> serviceDoc;
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

  Map<String, dynamic> get serviceData => serviceDoc;
  String get serviceId => (serviceDoc['id'] ?? '').toString();

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  Map<String, dynamic>? _selectedProfessional;

  late String shopId;
  late Map<String, dynamic> shopData;

  Map<String, dynamic> _shopConfig = {};
  int _intervalMinutes = 60;
  bool _clientChoosesProfessional = true;
  // o controle de evitar buracos é lido via shopConfig quando necessário
  int _minAdvanceHours = 7;

  late PlanFeatures _planFeatures;

  bool _isRestricted = false;
  String? _restrictionReason;
  bool _loadingRestriction = true;
  Map<String, bool>? _clientStatus;

  @override
  void initState() {
    super.initState();
    shopId = (widget.shop['id'] ?? '').toString();
    shopData = widget.shop;
    _loadShopSettings();
    _checkRestriction();
  }

  Future<void> _checkRestriction() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        _clientStatus ??=
            await ClientVerificationService.getClientStatus(user.id, shopId);

        final restrictProblematic =
            _shopConfig['restrict_problematic_clients'] ?? false;
        final bool isProbRestricted =
            (_clientStatus!['isProblematic'] == true && restrictProblematic);

        final requireCpf = _shopConfig['require_cpf'] == true;
        final bool isCpfRestricted = (_planFeatures.requireCpfForBooking &&
            requireCpf &&
            _clientStatus!['hasCpf'] == false);

        if (isProbRestricted || isCpfRestricted) {
          if (mounted) {
            setState(() {
              _isRestricted = true;
              _restrictionReason =
                  isCpfRestricted ? 'cpf_missing' : 'problematic';
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
    debugPrint('🚀 BookingPage: _loadShopSettings | shopId: $shopId');
    if (shopData.containsKey('config')) {
      final rawConfig = shopData['config'];
      debugPrint(
          '🔍 BookingPage: rawConfig type: ${rawConfig?.runtimeType} | value: $rawConfig');

      _shopConfig = (rawConfig as Map<String, dynamic>?) ?? {};
      _planFeatures = PlanFeaturesService.getFeaturesForShop(shopData);
      setState(() {
        _intervalMinutes = _shopConfig['intervalo_agenda_min'] ?? 60;

        // A regra do plano sobrepõe a configuração da loja.
        // Se o plano não permite escolha, forçamos false.
        final configAllowsChoice = _shopConfig['cliente_escolhe_prof'] ?? true;
        _clientChoosesProfessional = _planFeatures.clientChoosesProfessional
            ? configAllowsChoice
            : false;

        _minAdvanceHours = _shopConfig['limite_minimo_agendamento_horas'] ?? 7;
      });
    } else {
      debugPrint('⚠️ BookingPage: Chave "config" não encontrada no shopData');
      _planFeatures = PlanFeaturesService.getFeaturesForShop(shopData);
    }
  }

  Widget _buildHeader() {
    String serviceName =
        (widget.serviceData['name'] ?? widget.serviceData['nome'] ?? 'Serviço')
            .toString();
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
                          "${widget.serviceData['duration_min'] ?? 30} min • ${currencyFormat.format(widget.selectedVariation?['price'] ?? widget.serviceData['price'])}",
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
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('employees')
          .stream(primaryKey: ['id']).eq('shop_id', shopId),
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

        final profs = ((snapshot.data ?? []).where((d) {
          final List<dynamic> skills = d['services_ids'] ?? [];
          final String targetId = widget.serviceId.toString();
          return skills.map((id) => id.toString()).contains(targetId);
        }).toList())
          ..sort((a, b) => ((a['schedule_priority'] ?? 0) as int)
              .compareTo((b['schedule_priority'] ?? 0) as int));

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
                      oldDate: widget.oldDate,
                      oldProfessional: widget.oldProfessional,
                      oldServiceName: widget.oldServiceName,
                      clientStatus: _clientStatus,
                      // fix: passa todos os profissionais qualificados para que o calendário
                      // mostre disponibilidade combinada (não apenas a do profissional prioridade 0)
                      qualifiedProfessionals: profs,
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
                  final data = doc;
                  final isSelected = _selectedProfessional != null &&
                      _selectedProfessional!['id'] == doc['id'];

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        setState(() {
                          _selectedProfessional = doc;
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
                              clientStatus: _clientStatus,
                              isReschedule: widget.isReschedule,
                              appointmentId: widget.appointmentId,
                              oldDate: widget.oldDate,
                              oldProfessional: widget.oldProfessional,
                              oldServiceName: widget.oldServiceName,
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
                              backgroundImage: data['photo_url'] != null
                                  ? NetworkImage(data['photo_url'])
                                  : null,
                              child: data['photo_url'] == null
                                  ? Text(data['name'][0].toUpperCase(),
                                      style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? AppColors.primaryPurple
                                              : Colors.grey))
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Text(data['name'],
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
      if (_restrictionReason == 'cpf_missing') {
        return RestrictedClientView(
          title: "Complete seu Perfil",
          message:
              "Esta loja exige que o cliente tenha CPF cadastrado antes de prosseguir, para fins de emissão de Nota Fiscal.\n\nPor favor, atualize o seu perfil e tente novamente.",
          icon: Icons.badge_outlined,
          actionLabel: "ATUALIZAR PERFIL",
          onCustomAction: () async {
            final user = Supabase.instance.client.auth.currentUser;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ClientRegisterPage(
                  user: user,
                  isBusinessAdding: false,
                  returnOnSuccess: true,
                ),
              ),
            );
            if (mounted) {
              setState(() {
                _clientStatus = null;
                _isRestricted = false;
                _restrictionReason = null;
                _loadingRestriction = true;
              });
              await _checkRestriction();
            }
          },
          onRefresh: () async {
            setState(() {
              _isRestricted = false;
              _restrictionReason = null;
              _loadingRestriction = true;
            });
            await _checkRestriction();
          },
        );
      }
      return RestrictedClientView(
        onRefresh: () async {
          setState(() {
            _isRestricted = false;
            _restrictionReason = null;
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
  final Map<String, dynamic> shop;
  final Map<String, dynamic> serviceDoc;
  final Map<String, dynamic>? selectedVariation;
  final Map<String, dynamic> professionalDoc;
  final Map<String, dynamic> shopConfig;
  final int intervalMinutes;
  final int minAdvanceHours;
  final bool isReschedule;
  final String? appointmentId;
  final bool fromSubdomain;
  final DateTime? oldDate;
  final String? oldProfessional;
  final String? oldServiceName;

  /// Lista de todos os profissionais qualificados para o serviço.
  /// Quando não nula (modo sem escolha do cliente), o calendário verifica
  /// a disponibilidade de TODOS eles antes de marcar um dia como indisponível.
  /// Quando nula (modo com escolha), o calendário usa apenas professionalDoc.
  final List<Map<String, dynamic>>? qualifiedProfessionals;

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
    this.oldDate,
    this.oldProfessional,
    this.oldServiceName,
    this.clientStatus,
    this.qualifiedProfessionals,
  });

  final Map<String, bool>? clientStatus;

  Map<String, dynamic> get serviceData => serviceDoc;

  @override
  State<BookingTimePage> createState() => _BookingTimePageState();
}

class _BookingTimePageState extends State<BookingTimePage> {
  DateTime? _selectedDate;
  DateTime _focusedDay = DateTime.now();
  int _bookingWindowDays = 90;
  bool _isVip = false;
  int _vipExtraDays = 0;
  bool _isRestricted = false;
  String? _restrictionReason;

  // Cache de disponibilidade
  Map<DateTime, bool> _dayAvailability = {};
  List<dynamic> _nationalHolidays = [];
  bool _isLoadingAvailability = false;
  // fix: bloquear dias sem equipe ativa para qualquer estabelecimento
  // _availabilityReady: calendário só renderiza quando verdadeiro
  // _availabilityVersion: incrementado após cada fetch completo para forçar rebuild do TableCalendar
  bool _availabilityReady = false;
  int _availabilityVersion = 0;

  // ── SHADOW MODE ──────────────────────────────────────────────────────────
  // Quando false (padrão): usa apenas a lógica local (código Dart).
  // Quando true: tenta a Edge Function primeiro; se falhar, cai no código local.
  // Para ativar o log de comparação, ligue _shadowModeCompare = true também.
  // ATENÇÃO: Mude apenas para testes via USB. Não suba 'true' sem validação.
  static const bool _useEdgeFunction = false;
  static const bool _shadowModeCompare =
      false; // true → executa os dois e loga divergências
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    debugPrint(
        '🚀 BookingPage: initState | shopId: ${(widget.shop['id'] ?? '').toString()} | serviceId: ${(widget.serviceDoc['id'] ?? '').toString()}');

    // Proteção de Rota Direta (Web Bypass Prevention)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/');
        }
      }
    });

    _bookingWindowDays = widget.shopConfig['janela_agendamento_dias'] ?? 90;
    _vipExtraDays = (widget.shopConfig['vip_extra_booking_days'] ?? 0).toInt();

    // Calcula a data efetiva de foco considerando antecedência mínima,
    // para que o calendário e a pré-população usem o mesmo mês desde o início.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final minAdvanceDateRaw = now.add(Duration(hours: widget.minAdvanceHours));
    final minAllowedDate = DateTime(
        minAdvanceDateRaw.year, minAdvanceDateRaw.month, minAdvanceDateRaw.day);
    final effectiveFocusedDay =
        minAllowedDate.isAfter(today) ? minAllowedDate : today;
    _focusedDay = effectiveFocusedDay;

    // fix: bloquear dias sem equipe ativa para qualquer estabelecimento
    // Pré-popula work_days de forma SÍNCRONA antes do primeiro build.
    // Isso garante que o calendário aparece imediatamente com o padrão correto
    // (dias de trabalho habilit., não-trabalho bloqueados) sem depender de Supabase.
    // O _fetchMonthAvailability depois refina com contagem real de slots disponíveis.
    _prePopulateWorkDays(effectiveFocusedDay);

    _checkRestriction();
    _fetchNationalHolidays(effectiveFocusedDay);
    _initWithVipCheck(); // aguarda VIP antes de buscar disponibilidade
  }

  Future<void> _fetchNationalHolidays(DateTime month) async {
    try {
      final year = month.year;
      final response = await BrasilApiService.getHolidays(year);
      if (mounted) {
        setState(() {
          _nationalHolidays = response;
        });
      }
    } catch (e) {
      debugPrint("Erro ao buscar feriados nacionais: $e");
    }
  }

  // fix: bloquear dias sem equipe ativa para qualquer estabelecimento
  // Pré-população síncrona: só verifica work_days (sem Supabase, sem slots).
  // Quando qualifiedProfessionals existe, um dia é habilitado se QUALQUER profissional trabalha nele.
  // Chamado em initState antes do primeiro build.
  void _prePopulateWorkDays(DateTime month) {
    try {
      final endOfMonth = DateTime(month.year, month.month + 1, 0);

      // Coleta os work_days de todos os profissionais relevantes (OR lógico)
      final profsToCheck =
          widget.qualifiedProfessionals ?? [widget.professionalDoc];
      final Set<int> allWorkDays = {};
      for (final prof in profsToCheck) {
        final rawWorkDays = prof['work_days'] ?? [];
        final days = (rawWorkDays as List).map((e) => int.parse(e.toString()));
        allWorkDays.addAll(days);
      }

      for (int day = 1; day <= endOfMonth.day; day++) {
        final date = DateTime(month.year, month.month, day);
        // Disponível se qualquer profissional trabalha neste dia da semana
        _dayAvailability[date] = allWorkDays.contains(date.weekday);
      }
    } catch (_) {
      // Se falhar, _dayAvailability fica vazio mas _availabilityReady ainda será true
    }
    _availabilityReady = true;
    _availabilityVersion = 1;
  }

  /// Chama a Edge Function `getCalendarAvailability` e retorna o mapa de disponibilidade.
  /// Retorna null se a função falhar (rede, timeout, erro 500), permitindo o fallback local.
  Future<Map<DateTime, bool>?> _fetchEdgeFunctionAvailability(
      DateTime month) async {
    try {
      final serviceId = (widget.serviceDoc['id'] ?? '').toString();
      final shopId = (widget.shop['id'] ?? '').toString();
      final profId = widget.qualifiedProfessionals == null
          ? (widget.professionalDoc['id'] ?? '').toString()
          : null; // null = verifica todos os qualificados
      final monthStr =
          '${month.year}-${month.month.toString().padLeft(2, '0')}';

      final payload = <String, dynamic>{
        'shop_id': shopId,
        'service_id': serviceId,
        'month': monthStr,
        'is_vip': _isVip,
        if (profId != null) 'professional_id': profId,
      };

      debugPrint(
          '🌐 [EdgeFunction] Chamando getCalendarAvailability | payload: $payload');

      final response = await Supabase.instance.client.functions
          .invoke('getCalendarAvailability', body: payload)
          .timeout(const Duration(seconds: 10));

      if (response.status != 200 || response.data == null) {
        debugPrint('⚠️ [EdgeFunction] Status inesperado: ${response.status}');
        return null;
      }

      final rawAvail = response.data['availability'] as Map<String, dynamic>?;
      if (rawAvail == null) {
        debugPrint('⚠️ [EdgeFunction] Resposta sem campo availability');
        return null;
      }

      // Converte { "2026-05-19": true, ... } → { DateTime: bool }
      final Map<DateTime, bool> result = {};
      rawAvail.forEach((key, value) {
        final parts = key.split('-').map(int.parse).toList();
        if (parts.length == 3) {
          result[DateTime(parts[0], parts[1], parts[2])] = value as bool;
        }
      });

      debugPrint(
          '✅ [EdgeFunction] Recebeu ${result.length} dias de disponibilidade');
      return result;
    } catch (e) {
      debugPrint('❌ [EdgeFunction] Falha ao chamar Edge Function: $e');
      return null; // Sinaliza para usar o fallback local
    }
  }

  /// Calcula disponibilidade localmente (lógica Dart original).
  /// Retorna o mapa de disponibilidade SEM aplicar ao estado.
  /// Chamado tanto no modo local direto quanto no Shadow Mode para comparação.
  Future<Map<DateTime, bool>> _fetchLocalAvailability(DateTime month) async {
    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
    final shopData = widget.shop;
    final configurados = shopData['configured_holidays'] ?? {};
    final pendentes = shopData['pending_holidays'] ?? [];
    final autoBlock = widget.shopConfig['auto_block_holidays'] ?? false;
    final preventGaps = widget.shopConfig['evitar_buracos_agenda'] ?? false;
    final serviceDuration =
        int.tryParse(widget.serviceData['duration_min'].toString()) ?? 30;
    final shopId = (widget.shop['id'] ?? '').toString();
    final profsToCheck =
        widget.qualifiedProfessionals ?? [widget.professionalDoc];

    final snapshot = await Supabase.instance.client.rpc(
      'get_shop_blocked_slots',
      params: {
        'p_shop_id': shopId,
        'p_start_date': startOfMonth.toIso8601String(),
        'p_end_date': endOfMonth.toIso8601String(),
      },
    );

    Map<String, List<Map<String, int>>> groupedByProfDay = {};
    for (var data in snapshot) {
      final status = data['status']?.toString().toLowerCase() ?? '';
      if (status == 'cancelado' ||
          status == 'rejeitado' ||
          status == 'recusado' ||
          status == 'excluido') continue;
      if (widget.isReschedule &&
          data['id'].toString() == widget.appointmentId.toString()) continue;

      final profId = data['professional_id']?.toString() ?? '';
      final dt = DateTime.parse(data['scheduled_at']);
      final key = '${profId}_${dt.day}';
      final startMin = dt.hour * 60 + dt.minute;
      final duration =
          int.tryParse(data['duration_min']?.toString() ?? '') ?? 30;
      groupedByProfDay
          .putIfAbsent(key, () => [])
          .add({'start': startMin, 'end': startMin + duration});
    }

    Map<DateTime, bool> newAvail = {};
    for (int day = 1; day <= endOfMonth.day; day++) {
      final date = DateTime(month.year, month.month, day);
      final iso = date.toIso8601String().split('T')[0];

      if (autoBlock) {
        bool isNational = _nationalHolidays.any((f) => f['date'] == iso);
        if (pendentes.contains(iso) || isNational) {
          newAvail[date] = false;
          continue;
        }
      }

      if (configurados.containsKey(iso)) {
        final config = configurados[iso];
        if (config == 'fechado') {
          newAvail[date] = false;
          continue;
        }
      }

      bool dayHasSlot = false;
      for (final prof in profsToCheck) {
        final profId = prof['id']?.toString() ?? '';
        final rawWorkDays = prof['work_days'] ?? [];
        final workDays =
            (rawWorkDays as List).map((e) => int.parse(e.toString())).toList();
        if (!workDays.contains(date.weekday)) continue;

        if (configurados.containsKey(iso)) {
          final config = configurados[iso];
          if (config is Map && config.containsKey('escala')) {
            final List escala = config['escala'] ?? [];
            if (!escala.contains(profId)) continue;
          }
        }

        // fix: per-day schedule + pausa diária via WorkSchedule
        final wsProf = WorkSchedule.fromEmployeeRow(
            Map<String, dynamic>.from(prof));
        final dayCfg = wsProf.forWeekday(date.weekday);
        if (dayCfg == null) continue;
        final startStr = dayCfg.start;
        final endStr = dayCfg.end;
        final key = '${profId}_$day';
        final busy = [...(groupedByProfDay[key] ?? <Map<String, int>>[])]; 

        // Inclui folgas do profissional como busyIntervals
        final profBreaks = prof['breaks'];
        if (profBreaks != null && profBreaks is List) {
          busy.addAll(AvailabilityUtils.parseFolgasForDate(profBreaks, date));
        }

        final breakI = dayCfg.breakInterval == null
            ? null
            : {
                'start': dayCfg.breakInterval!.startMin,
                'end': dayCfg.breakInterval!.endMin,
              };

        final slots = AvailabilityUtils.generateSmartSlots(
          startStr: startStr,
          endStr: endStr,
          interval: widget.intervalMinutes,
          serviceDuration: serviceDuration,
          busyIntervals: busy,
          preventGaps: preventGaps,
          minAdvanceHours: widget.minAdvanceHours,
          selectedDate: date,
          breakInterval: breakI,
        );

        if (slots.isNotEmpty) {
          dayHasSlot = true;
          break;
        }
      }
      newAvail[date] = dayHasSlot;
    }
    return newAvail;
  }

  Future<void> _fetchMonthAvailability(DateTime month) async {
    if (mounted) setState(() => _isLoadingAvailability = true);

    try {
      Map<DateTime, bool> newAvail;

      if (_useEdgeFunction) {
        // ── MODO EDGE FUNCTION ───────────────────────────────────────────────
        debugPrint(
            '🟢 [Availability] Usando Edge Function como fonte primária.');
        final edgeResult = await _fetchEdgeFunctionAvailability(month);

        if (edgeResult != null) {
          // Edge Function respondeu com sucesso.
          newAvail = edgeResult;
          debugPrint(
              '✅ [Availability] Edge Function entregou ${edgeResult.length} dias.');
        } else {
          // Fallback: Edge Function falhou → usa lógica local.
          debugPrint(
              '⚠️ [Availability] Fallback para lógica LOCAL (Edge falhou).');
          newAvail = await _fetchLocalAvailability(month);
        }
      } else if (_shadowModeCompare) {
        // ── MODO SOMBRA (COMPARAÇÃO) ─────────────────────────────────────────
        // Executa os DOIS modos em paralelo e loga divergências.
        // O resultado aplicado ao calendário é SEMPRE o local (seguro).
        debugPrint(
            '🔬 [ShadowMode] Executando comparação Local vs Edge Function...');
        final results = await Future.wait([
          _fetchLocalAvailability(month),
          _fetchEdgeFunctionAvailability(month)
              .then((v) => v ?? <DateTime, bool>{}),
        ]);
        final localResult = results[0];
        final edgeResult = results[1];

        // Compara os mapas e loga divergências dia a dia
        int divergencias = 0;
        for (final entry in localResult.entries) {
          final dateKey = entry.key;
          final localVal = entry.value;
          final edgeVal = edgeResult[dateKey];
          if (edgeVal == null) {
            debugPrint(
                '🔍 [ShadowMode] Dia ${dateKey.day}/${dateKey.month}: Edge não retornou este dia.');
          } else if (localVal != edgeVal) {
            divergencias++;
            final localStr = localVal ? 'DISPONÍVEL' : 'INDISPONÍVEL';
            final edgeStr = edgeVal ? 'DISPONÍVEL' : 'INDISPONÍVEL';
            debugPrint(
              '🚨 [ShadowMode] DIVERGÊNCIA no dia ${dateKey.day}/${dateKey.month}: '
              'Local=$localStr | Edge=$edgeStr',
            );
          }
        }
        if (divergencias == 0) {
          debugPrint(
              '✅ [ShadowMode] Resultado IDÊNTICO entre Local e Edge Function (${localResult.length} dias).');
        } else {
          debugPrint(
              '⚠️ [ShadowMode] $divergencias divergência(s) encontrada(s). Revise os logs acima.');
        }

        // Calendário usa o resultado LOCAL (mais seguro)
        newAvail = localResult;
      } else {
        // ── MODO LOCAL (PADRÃO) ──────────────────────────────────────────────
        debugPrint('📱 [Availability] Usando lógica LOCAL (padrão).');
        newAvail = await _fetchLocalAvailability(month);
      }

      if (mounted) {
        setState(() {
          _dayAvailability.addAll(newAvail);
          _isLoadingAvailability = false;
          _availabilityReady = true;
          _availabilityVersion++; // força rebuild do TableCalendar via ValueKey
        });
      }
    } catch (e) {
      debugPrint('❌ [Availability] Erro geral ao buscar disponibilidade: $e');
      // Em caso de erro, o calendário já está visível (pré-populado em initState).
      if (mounted)
        setState(() {
          _isLoadingAvailability = false;
        });
    }
  }

  Future<void> _checkRestriction() async {
    final user = Supabase.instance.client.auth.currentUser;
    final planFeatures = PlanFeaturesService.getFeaturesForShop(widget.shop);
    final requireCpf = widget.shopConfig['require_cpf'] == true;

    if (widget.clientStatus != null) {
      final restrictProblematic =
          widget.shopConfig['restrict_problematic_clients'] ?? false;
      final isProbRestricted = (widget.clientStatus!['isProblematic'] == true &&
          restrictProblematic);
      final isCpfRestricted = (planFeatures.requireCpfForBooking &&
          requireCpf &&
          widget.clientStatus!['hasCpf'] == false);

      if (isProbRestricted || isCpfRestricted) {
        if (mounted) {
          setState(() {
            _isRestricted = true;
            _restrictionReason =
                isCpfRestricted ? 'cpf_missing' : 'problematic';
          });
        }
      }
      return;
    }

    if (user != null) {
      final status = await ClientVerificationService.getClientStatus(
          user.id, (widget.shop['id'] ?? '').toString());
      final restrictProblematic =
          widget.shopConfig['restrict_problematic_clients'] ?? false;

      final isProbRestricted =
          (status['isProblematic'] == true && restrictProblematic);
      final isCpfRestricted = (planFeatures.requireCpfForBooking &&
          requireCpf &&
          status['hasCpf'] == false);

      if (isProbRestricted || isCpfRestricted) {
        if (mounted) {
          setState(() {
            _isRestricted = true;
            _restrictionReason =
                isCpfRestricted ? 'cpf_missing' : 'problematic';
          });
        }
      }
    }
  }

  Future<void> _checkVipStatus() async {
    if (widget.clientStatus != null) {
      if (mounted) {
        setState(() {
          _isVip = widget.clientStatus!['isVip'] ?? false;
          if (_isVip) {
            _bookingWindowDays += _vipExtraDays;
            _availabilityVersion++; // Força rebuild do calendário para atualizar lastDay
          }
        });
        // _autoSelectFirstAvailableDate(widget.professionalDoc);
      }
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    final status = widget.clientStatus ??
        (user != null
            ? await ClientVerificationService.getClientStatus(
                user.id, (widget.shop['id'] ?? '').toString())
            : null);

    if (status != null) {
      if (mounted) {
        setState(() {
          _isVip = status['isVip'] ?? false;
          if (_isVip) {
            _bookingWindowDays += _vipExtraDays;
            _availabilityVersion++; // Força rebuild do calendário para atualizar lastDay
          }
        });
        // Reinicializa a data automática se o status VIP mudar a janela
        // _autoSelectFirstAvailableDate(widget.professionalDoc);
      }
    } else {
      // _autoSelectFirstAvailableDate(widget.professionalDoc);
    }
  }

  Future<void> _initWithVipCheck() async {
    await _checkVipStatus();
    if (mounted) {
      _fetchMonthAvailability(_focusedDay);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isRestricted) {
      if (_restrictionReason == 'cpf_missing') {
        return RestrictedClientView(
          title: "Complete seu Perfil",
          message:
              "Esta loja exige que o cliente tenha CPF cadastrado antes de prosseguir, para fins de emissão de Nota Fiscal.\n\nPor favor, atualize o seu perfil e tente novamente.",
          icon: Icons.badge_outlined,
          actionLabel: "ATUALIZAR PERFIL",
          onCustomAction: () async {
            final user = Supabase.instance.client.auth.currentUser;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ClientRegisterPage(
                  user: user,
                  isBusinessAdding: false,
                  returnOnSuccess: true,
                ),
              ),
            );
            if (mounted && user != null) {
              final shopIdStr = (widget.shop['id'] ?? '').toString();
              final status = await ClientVerificationService.getClientStatus(
                  user.id, shopIdStr);
              final planFeatures =
                  PlanFeaturesService.getFeaturesForShop(widget.shop);
              final requireCpf = widget.shopConfig['require_cpf'] == true;
              final isCpfRestricted = planFeatures.requireCpfForBooking &&
                  requireCpf &&
                  status['hasCpf'] == false;
              if (mounted) {
                setState(() {
                  _isRestricted = isCpfRestricted;
                  _restrictionReason = isCpfRestricted ? 'cpf_missing' : null;
                });
              }
            }
          },
          onRefresh: () async {
            setState(() {
              _isRestricted = false;
              _restrictionReason = null;
            });
            await _checkRestriction();
          },
        );
      }
      return RestrictedClientView(
        onRefresh: () async {
          setState(() {
            _isRestricted = false;
            _restrictionReason = null;
          });
          await _checkRestriction();
        },
      );
    }

    final svcName =
        (widget.serviceData['name'] ?? widget.serviceData['nome'] ?? 'Serviço')
            .toString();
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
                      if (_isLoadingAvailability)
                        const LinearProgressIndicator(
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primaryPurple),
                        ),
                      const SizedBox(height: 16),
                      // fix: bloquear dias sem equipe ativa para qualquer estabelecimento
                      // _availabilityReady é true desde initState (pré-população síncrona).
                      // ValueKey com _availabilityVersion força rebuild do TableCalendar
                      // após o fetch async com dados refinados de slots.
                      if (_availabilityReady)
                        TableCalendar(
                          key: ValueKey(
                              'cal_${_focusedDay.year}_${_focusedDay.month}_$_availabilityVersion'),
                          firstDay: firstDateBound,
                          lastDay: lastAllowedDay,
                          focusedDay: _focusedDay.isBefore(firstDateBound)
                              ? firstDateBound
                              : (_focusedDay.isAfter(lastAllowedDay)
                                  ? lastAllowedDay
                                  : _focusedDay),
                          selectedDayPredicate: (day) =>
                              isSameDay(_selectedDate, day),
                          onDaySelected: (selectedDay, focusedDay) {
                            setState(() {
                              _selectedDate = selectedDay;
                              _focusedDay = focusedDay;
                            });
                          },
                          onPageChanged: (focusedDay) {
                            setState(() {
                              _focusedDay = focusedDay;
                              // Pré-popula work_days imediatamente para evitar dias
                              // piscando como bloqueados enquanto o fetch async carrega
                              _prePopulateWorkDays(focusedDay);
                            });
                            _fetchMonthAvailability(focusedDay);
                          },
                          locale: 'pt_BR',
                          headerStyle: const HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                            titleTextStyle: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryPurple,
                            ),
                          ),
                          calendarStyle: CalendarStyle(
                            selectedDecoration: const BoxDecoration(
                              color: AppColors.primaryPurple,
                              shape: BoxShape.circle,
                            ),
                            todayDecoration: BoxDecoration(
                              color: AppColors.primaryPurple
                                  .withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            outsideDaysVisible: false,
                            disabledTextStyle:
                                const TextStyle(color: Colors.transparent),
                          ),
                          enabledDayPredicate: (day) {
                            final dateKey =
                                DateTime(day.year, day.month, day.day);
                            // fix: bloquear dias sem equipe ativa para qualquer estabelecimento
                            return _dayAvailability[dateKey] ?? false;
                          },
                          calendarBuilders: CalendarBuilders(
                            defaultBuilder: (context, day, focusedDay) {
                              final dateKey =
                                  DateTime(day.year, day.month, day.day);
                              // fix: bloquear dias sem equipe ativa para qualquer estabelecimento
                              final isAvailable =
                                  _dayAvailability[dateKey] ?? false;

                              if (!isAvailable) {
                                return Center(
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Text(
                                        '${day.day}',
                                        style:
                                            const TextStyle(color: Colors.grey),
                                      ),
                                      CustomPaint(
                                        size: const Size(20, 20),
                                        painter: StrikeThroughPainter(),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return null;
                            },
                            disabledBuilder: (context, day, focusedDay) {
                              return Center(
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Text(
                                      '${day.day}',
                                      style: TextStyle(
                                          color: Colors.grey
                                              .withValues(alpha: 0.5)),
                                    ),
                                    CustomPaint(
                                      size: const Size(20, 20),
                                      painter: StrikeThroughPainter(),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // ✅ DATA SELECIONADA
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
              // ✅ BOTÕES
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
                                    qualifiedProfessionals:
                                        widget.qualifiedProfessionals,
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
  final Map<String, dynamic> shop;
  final Map<String, dynamic> serviceDoc;
  final Map<String, dynamic>? selectedVariation;
  final Map<String, dynamic> professionalDoc;
  final Map<String, dynamic> shopConfig;
  final int intervalMinutes;
  final int minAdvanceHours;
  final DateTime selectedDate;
  final bool isReschedule;
  final String? appointmentId;
  final bool fromSubdomain;

  /// Lista de todos os profissionais qualificados (modo sem escolha do cliente).
  /// Quando informada, a tela de horários itera sobre todos para encontrar
  /// o primeiro com disponibilidade no dia. O profissional escolhido é
  /// salvo internamente e passado para o checkout.
  final List<Map<String, dynamic>>? qualifiedProfessionals;

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
    this.qualifiedProfessionals,
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

  Map<String, dynamic> get serviceData => serviceDoc;

  @override
  State<BookingSlotsPage> createState() => _BookingSlotsPageState();
}

class _BookingSlotsPageState extends State<BookingSlotsPage> {
  TimeOfDay? _selectedTime;

  /// Dados do último conflito detectado ao selecionar um slot no modo dono.
  Map<String, dynamic>? _lastConflictData;

  /// Profissional resolvido para o dia (o primeiro com disponibilidade).
  /// Usado no checkout para garantir que o agendamento vá para o profissional correto.
  Map<String, dynamic>? _resolvedProfessional;

  Future<List<Map<String, dynamic>>>? _slotsFuture;

  @override
  void initState() {
    super.initState();
    debugPrint('🚀 BookingSlotsPage: initState | date: ${widget.selectedDate}');
    _initSlotsFuture();
  }

  void _initSlotsFuture() {
    final startDay = DateTime(widget.selectedDate.year,
        widget.selectedDate.month, widget.selectedDate.day);
    final endDay = startDay.add(const Duration(hours: 23, minutes: 59));
    final isOwnerMode = widget.ownerExcludeAppointmentId != null ||
        widget.allowOccupiedSelection;

    _slotsFuture =
        _fetchAppointmentsAndIntervals(startDay, endDay, isOwnerMode);
  }

  @override
  Widget build(BuildContext context) {
    final svcName =
        widget.serviceData['name'] ?? widget.serviceData['nome'] ?? 'Serviço';
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
                                  // Usa o profissional resolvido pelo dia (se disponível),
                                  // caso contrário usa o professionalDoc original.
                                  final profData = _resolvedProfessional ??
                                      widget.professionalDoc;

                                  String finalName =
                                      widget.serviceData['name'] ?? '';
                                  double finalPrice = double.tryParse(widget
                                          .serviceData['price']
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
                                      // --- TRAVA DE SEGURANÇA FINAL ---
                                      final appDoc = await Supabase
                                          .instance.client
                                          .from('appointments')
                                          .select()
                                          .eq('id', widget.appointmentId!)
                                          .maybeSingle();

                                      if (appDoc != null) {
                                        final validation =
                                            await ClientVerificationService
                                                .canModifyAppointment(appDoc);
                                        if (!validation['can']) {
                                          if (!mounted) return;
                                          Navigator.of(context)
                                              .pop(); // tira o loading
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content: Text(
                                                      validation['reason']),
                                                  backgroundColor: Colors.red));
                                          return;
                                        }
                                      }

                                      final duration = int.tryParse(widget
                                                  .serviceDoc['duration_min']
                                                  ?.toString() ??
                                              '30') ??
                                          30;
                                      final endDate = newDateTime
                                          .add(Duration(minutes: duration));

                                      // 1. Validar Disponibilidade Localmente (Evita 401/404 de Edge Functions)
                                      final profData = _resolvedProfessional ??
                                          widget.professionalDoc;
                                      final rawCheck = await Supabase
                                          .instance.client
                                          .rpc(
                                          'get_professional_blocked_slots',
                                          params: {
                                            'p_professional_id': profData['id'],
                                            'p_start_date': newDateTime
                                                .subtract(
                                                    const Duration(hours: 4))
                                                .toIso8601String(),
                                            'p_end_date': newDateTime
                                                .add(const Duration(hours: 4))
                                                .toIso8601String(),
                                          },
                                        );

                                      final conflictCheck = rawCheck
                                          .where((a) =>
                                              a['id'].toString() !=
                                                  widget.appointmentId &&
                                              !const [
                                                'cancelado',
                                                'rejeitado',
                                                'recusado',
                                                'excluido'
                                              ].contains(
                                                  (a['status'] ?? '')
                                                      .toString()
                                                      .toLowerCase()))
                                          .toList();

                                      bool isConflicting = false;
                                      for (var appt in conflictCheck) {
                                        final apptStart = DateTime.parse(
                                            appt['scheduled_at']);
                                        final apptDuration = int.tryParse(
                                                appt['duration_min']
                                                        ?.toString() ??
                                                    '30') ??
                                            30;
                                        final apptEnd = apptStart.add(
                                            Duration(minutes: apptDuration));

                                        // Verificação de sobreposição
                                        if (newDateTime.isBefore(apptEnd) &&
                                            endDate.isAfter(apptStart)) {
                                          isConflicting = true;
                                          break;
                                        }
                                      }

                                      if (isConflicting) {
                                        if (mounted) {
                                          Navigator.of(context)
                                              .pop(); // tira loading
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                            content: Text(
                                                'Este horário não está mais disponível. Por favor, escolha outro.'),
                                            backgroundColor: Colors.red,
                                          ));
                                        }
                                        return;
                                      }

                                      // 2. Atualizar Agendamento Direto
                                      await Supabase.instance.client
                                          .from('appointments')
                                          .update({
                                        'scheduled_at':
                                            newDateTime.toIso8601String(),
                                        'end_at': endDate.toIso8601String(),
                                        'service_id': widget.serviceDoc['id'],
                                        'service_name': finalName,
                                        'total_price': finalPrice,
                                        'total_value': finalPrice,
                                        'professional_id': profData['id'],
                                        'professional_name': profData['name'] ??
                                            profData['nome'] ??
                                            'Profissional',
                                        'duration_min': duration,
                                        'is_rescheduled': true,
                                      }).eq('id', widget.appointmentId!);
                                      // Increment reschedule_count via raw RPC (ignore error if column not exists yet)
                                      try {
                                        await Supabase.instance.client.rpc(
                                          'increment_reschedule_count',
                                          params: {
                                            'appointment_id':
                                                widget.appointmentId!
                                          },
                                        );
                                      } catch (_) {}

                                      if (!mounted) return;
                                      Navigator.of(context)
                                          .pop(); // tira loading

                                      if (!mounted) return;

                                      // Em vez de voltar 3 telas, vamos direcionar para a página de sucesso
                                      // passando os dados antigos e novos

                                      Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                              builder: (context) =>
                                                  RescheduleSuccessPage(
                                                    appointmentId:
                                                        widget.appointmentId!,
                                                    newDate: newDateTime,
                                                    newProfessional:
                                                        profData['name'] ??
                                                            profData['nome'] ??
                                                            'Profissional',
                                                    newServiceName: finalName,
                                                    oldDate: widget.oldDate,
                                                    oldProfessional: widget
                                                            .oldProfessional ??
                                                        '',
                                                    oldServiceName:
                                                        widget.oldServiceName ??
                                                            '',
                                                  )));
                                    } catch (e) {
                                      if (!mounted) return;
                                      if (Navigator.of(context).canPop()) {
                                        Navigator.of(context)
                                            .pop(); // fecha loading se ainda aberto
                                      }
                                      final errStr = e.toString();
                                      final bool isExclusionViolation =
                                          errStr.contains('23P01') ||
                                              errStr.contains(
                                                  'appointments_no_overlap') ||
                                              errStr.contains(
                                                  'exclusion_violation') ||
                                              errStr.toLowerCase().contains(
                                                  'conflicting key value');
                                      sm.showSnackBar(SnackBar(
                                          content: Text(isExclusionViolation
                                              ? 'Este horário acabou de ser preenchido por outra pessoa. Por favor, escolha outro.'
                                              : "Erro: $e"),
                                          backgroundColor: Colors.red));
                                    }
                                  } else {
                                    // ── Modo normal (Checkout) ──
                                    final shopId =
                                        (widget.shop['id'] ?? '').toString();
                                    final shopData = widget.shop;
                                    final profData = _resolvedProfessional ??
                                        widget.professionalDoc;

                                    // ── PRÉ-RESERVA (lock de 5 minutos) ──
                                    // Tenta reservar o horário atomicamente antes do checkout.
                                    // Se outro cliente acabou de pegar o slot, mostra erro
                                    // e aborta. Não bloqueia em caso de erro de rede.
                                    String? preReservaId;
                                    try {
                                      final user = Supabase
                                          .instance.client.auth.currentUser;
                                      if (user != null && shopId.isNotEmpty) {
                                        final newDateTime = DateTime(
                                          widget.selectedDate.year,
                                          widget.selectedDate.month,
                                          widget.selectedDate.day,
                                          _selectedTime!.hour,
                                          _selectedTime!.minute,
                                        );
                                        final duration = int.tryParse(widget
                                                    .serviceDoc['duration_min']
                                                    ?.toString() ??
                                                '30') ??
                                            30;
                                        final servicePrice = double.tryParse(
                                                widget.serviceData['price']
                                                        ?.toString() ??
                                                    '0') ??
                                            0.0;

                                        final rpcRes = await Supabase
                                            .instance.client
                                            .rpc('tentar_pre_reserva', params: {
                                          'p_shop_id': shopId,
                                          'p_client_id': user.id,
                                          'p_professional_id':
                                              profData['id'].toString(),
                                          'p_service_id': widget.serviceDoc['id']
                                              .toString(),
                                          'p_scheduled_at':
                                              newDateTime.toIso8601String(),
                                          'p_duration_min': duration,
                                          'p_client_name': user.userMetadata?[
                                                  'full_name'] ??
                                              user.userMetadata?['name'] ??
                                              user.email ??
                                              'Cliente',
                                          'p_client_email': user.email,
                                          'p_client_phone': user
                                              .userMetadata?['phone']
                                              ?.toString(),
                                          'p_professional_name':
                                              profData['name'] ??
                                                  profData['nome'] ??
                                                  'Profissional',
                                          'p_service_name':
                                              widget.serviceDoc['name'] ??
                                                  'Serviço',
                                          'p_total_value': servicePrice,
                                        });
                                        if (rpcRes is Map &&
                                            rpcRes['success'] == true) {
                                          preReservaId =
                                              rpcRes['appointment_id']
                                                  ?.toString();
                                        } else if (rpcRes is Map &&
                                            rpcRes['reason'] ==
                                                'horario_ocupado') {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                            content: Text(
                                                'Este horário acabou de ser selecionado por outra pessoa. Por favor, escolha outro.'),
                                            backgroundColor: Colors.red,
                                          ));
                                          return;
                                        } else if (rpcRes is Map &&
                                            rpcRes['success'] == false) {
                                          debugPrint(
                                              'tentar_pre_reserva rejeitado: ${rpcRes['reason']}');
                                          // prossegue sem lock, fallback via exclusion constraint
                                        }
                                      }
                                    } catch (e) {
                                      // Falha de rede/RPC: prossegue sem lock. A exclusion
                                      // constraint no DB ainda garante anti double-booking.
                                      debugPrint(
                                          'tentar_pre_reserva falhou: $e');
                                    }

                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => CheckoutPage(
                                          shopId: shopId,
                                          shopData: shopData,
                                          shopConfig: widget.shopConfig,
                                          serviceDoc: widget.serviceDoc,
                                          professionalDoc: profData,
                                          date: widget.selectedDate,
                                          time: _selectedTime!,
                                          selectedVariation:
                                              widget.selectedVariation,
                                          serviceNameOverride: finalName,
                                          servicePriceOverride: finalPrice,
                                          fromSubdomain: widget.fromSubdomain,
                                          rescheduleId: widget.appointmentId,
                                          preReservaId: preReservaId,
                                        ),
                                      ),
                                    );

                                    // Se o usuário voltou sem confirmar e ainda há lock,
                                    // tenta remover imediatamente (cron de 5 min é fallback).
                                    if (preReservaId != null &&
                                        result != 'booking_confirmed') {
                                      try {
                                        await Supabase.instance.client
                                            .from('appointments')
                                            .delete()
                                            .eq('id', preReservaId)
                                            .eq('status', 'pre_reserva');
                                      } catch (e) {
                                        debugPrint('⚠️ Falha ao limpar pre_reserva: $e');
                                      }
                                    }

                                    if (result == 'edit_profile' && mounted) {
                                      final user = Supabase
                                          .instance.client.auth.currentUser;
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ClientRegisterPage(
                                            user: user,
                                            isBusinessAdding: false,
                                          ),
                                        ),
                                      );
                                    }
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
    // Busca agendamentos de TODOS os profissionais qualificados para o dia.
    // Quando qualifiedProfessionals é nulo, usa apenas o professionalDoc (modo com escolha).
    final profsToCheck =
        widget.qualifiedProfessionals ?? [widget.professionalDoc];
    final profIds =
        profsToCheck.map((p) => (p['id'] ?? '').toString()).toList();

    final allDocs = await Supabase.instance.client.rpc(
      'get_shop_blocked_slots',
      params: {
        'p_shop_id': (widget.shop['id'] ?? '').toString(),
        'p_start_date': startDay.toIso8601String(),
        'p_end_date': endDay.toIso8601String(),
      },
    );

    final querySnapshot =
        allDocs.where((d) => profIds.contains(d['professional_id'])).toList();

    List<Map<String, dynamic>> results = [];

    // Otimização N+1: Coletar service_ids que precisam de duração
    final missingDurationServiceIds = querySnapshot
        .where((d) =>
            int.tryParse(d['duration_min']?.toString() ?? '') == null &&
            d['service_id'] != null)
        .map((d) => d['service_id'].toString())
        .toSet()
        .toList();

    Map<String, int> serviceDurations = {};
    if (missingDurationServiceIds.isNotEmpty) {
      try {
        final servicesData = await Supabase.instance.client
            .from('services')
            .select('id, duration_min')
            .inFilter('id', missingDurationServiceIds);

        for (var s in servicesData) {
          serviceDurations[s['id'].toString()] =
              int.tryParse(s['duration_min']?.toString() ?? '') ?? 30;
        }
      } catch (_) {}
    }

    for (var d in querySnapshot) {
      final data = d;
      final status = (data['status'] ?? '').toString().toLowerCase();

      if (status == 'cancelado' ||
          status == 'rejeitado' ||
          status == 'recusado' ||
          status == 'excluido') {
        continue;
      }

      // pendente_pix: só ignora se for antigo (> 20 min), senão considera ocupado
      if (status == 'pendente_pix') {
        final createdAtRaw = data['created_at']?.toString();
        DateTime? createdAt;
        if (createdAtRaw != null && createdAtRaw.isNotEmpty) {
          createdAt = DateTime.tryParse(createdAtRaw);
        }
        final cutoff = DateTime.now().subtract(const Duration(minutes: 20));
        if (createdAt == null || createdAt.isBefore(cutoff)) {
          continue; // PIX abandonado: libera slot
        }
      }

      if (widget.ownerExcludeAppointmentId != null &&
          data['id'] == widget.ownerExcludeAppointmentId) {
        continue;
      }

      // Se for reagendamento do cliente, ignoramos o agendamento atual dele
      if (widget.isReschedule &&
          data['id'].toString() == widget.appointmentId.toString()) {
        continue;
      }

      int? agDuration = int.tryParse(data['duration_min']?.toString() ?? '');

      if (agDuration == null) {
        String? savedServiceId = data['service_id']?.toString();
        if (savedServiceId != null && savedServiceId.isNotEmpty) {
          agDuration = serviceDurations[savedServiceId];
        }
        agDuration ??= 30; // fallback final
      }

      results.add({
        ...data,
        'id': data['id'],
        'computed_duration': agDuration,
      });
    }

    return results;
  }

  Widget _buildSlotsList() {
    int duration =
        int.tryParse(widget.serviceData['duration_min']?.toString() ?? '30') ??
            30;
    final isOwnerMode = widget.ownerExcludeAppointmentId != null ||
        widget.allowOccupiedSelection;

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _slotsFuture,
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

        final List<dynamic> docs = snapshot.data ?? [];
        final Map<int, Map<String, dynamic>> occupiedSlotData = {};
        List<Map<String, int>> busyIntervals = [];

        for (var data in docs) {
          final dt = DateTime.parse(data['scheduled_at']);
          int startMin = dt.hour * 60 + dt.minute;
          int agDuration = data['computed_duration'] as int;
          int endMin = startMin + agDuration;

          busyIntervals.add({"start": startMin, "end": endMin});

          if (isOwnerMode) {
            occupiedSlotData[startMin] = data;
          }
        }

        final preventGaps = widget.shopConfig['evitar_buracos_agenda'] ?? false;
        final profsToCheck =
            widget.qualifiedProfessionals ?? [widget.professionalDoc];

        // Modo dono: usa sempre o professionalDoc (sem iterar sobre qualificados)
        // Modo cliente sem escolha: itera sobre todos os qualificados por prioridade
        List<String> slots = [];
        List<String> allSlots = [];

        if (isOwnerMode) {
          // Modo dono: gera TODOS os slots do turno (livres + ocupados visíveis)
          final profData = widget.professionalDoc;
          final wsOwner = WorkSchedule.fromEmployeeRow(profData);
          final dayCfg = wsOwner.forWeekday(widget.selectedDate.weekday);
          final startStr = dayCfg?.start ??
              (profData['work_start'] ?? profData['start_time'] ?? '08:00');
          final endStr = dayCfg?.end ??
              (profData['work_end'] ?? profData['end_time'] ?? '18:00');
          int startDayMin = int.parse(startStr.split(':')[0]) * 60 +
              int.parse(startStr.split(':')[1]);
          int endDayMin = int.parse(endStr.split(':')[0]) * 60 +
              int.parse(endStr.split(':')[1]);
          // Pausa diária do dono é ignorada na visualização (liberação total),
          // mas se quiser bloquear, basta colidir o slot com o intervalo da pausa.
          final br = dayCfg?.breakInterval;
          int current = startDayMin;
          while (current + duration <= endDayMin) {
            final endSlot = current + duration;
            final overlapsBreak = br != null &&
                current < br.endMin &&
                endSlot > br.startMin;
            if (!overlapsBreak) {
              final h = (current ~/ 60).toString().padLeft(2, '0');
              final m = (current % 60).toString().padLeft(2, '0');
              allSlots.add('$h:$m');
            }
            current += widget.intervalMinutes;
          }
          slots = allSlots;
          _resolvedProfessional = widget.professionalDoc;
        } else {
          // ── DISTRIBUIÇÃO POR CARGA ────────────────────────────────────────
          // Reordena os profissionais pelo menor número de minutos já agendados
          // no dia, usando a prioridade da loja como desempate.
          // Isso evita que um profissional fique sobrecarregado enquanto outro
          // está ocioso (ex: Dionathan 3h agendado → Edmara 0h vai na frente).
          //
          // A prioridade original (índice em profsToCheck) é o desempate:
          // se dois profissionais tiverem a mesma carga, o de maior prioridade
          // (menor índice) é preferido.

          // 1. Calcula carga de cada profissional (minutos totais no dia)
          final Map<String, int> profLoad = {};
          for (int i = 0; i < profsToCheck.length; i++) {
            final profId = (profsToCheck[i]['id'] ?? '').toString();
            int totalMin = 0;
            for (var data in docs) {
              if ((data['professional_id'] ?? '').toString() != profId)
                continue;
              totalMin += (data['computed_duration'] as int? ?? 0);
            }
            profLoad[profId] = totalMin;
          }

          // 2. Cria lista ordenada: menor carga primeiro; índice original como desempate
          final List<Map<String, dynamic>> sortedProfs =
              List.from(profsToCheck);
          sortedProfs.sort((a, b) {
            final idA = (a['id'] ?? '').toString();
            final idB = (b['id'] ?? '').toString();
            final loadDiff = (profLoad[idA] ?? 0).compareTo(profLoad[idB] ?? 0);
            if (loadDiff != 0) return loadDiff;
            // Empate de carga → respeita prioridade original da loja
            return profsToCheck.indexOf(a).compareTo(profsToCheck.indexOf(b));
          });

          debugPrint(
            '⚖️ [SlotsPage] Ordem de distribuição por carga: '
            '${sortedProfs.map((p) => "${p['nome'] ?? p['name']}=${profLoad[(p['id'] ?? '').toString()]}min").join(", ")}',
          );

          // 3. Itera na nova ordem: o mais livre com disponibilidade é escolhido
          for (final prof in sortedProfs) {
            final profId = (prof['id'] ?? '').toString();

            // Verifica dia de trabalho deste profissional
            final rawWorkDays = prof['work_days'] ?? [];
            final workDays = (rawWorkDays as List)
                .map((e) => int.parse(e.toString()))
                .toList();
            if (!workDays.contains(widget.selectedDate.weekday)) continue;

            // Filtra os busyIntervals apenas deste profissional
            final profBusy = <Map<String, int>>[];
            for (var data in docs) {
              if ((data['professional_id'] ?? '').toString() != profId)
                continue;
              final dt = DateTime.parse(data['scheduled_at']);
              final startMin = dt.hour * 60 + dt.minute;
              final agDuration = data['computed_duration'] as int;
              profBusy.add({'start': startMin, 'end': startMin + agDuration});
            }

            // Inclui folgas do profissional como busyIntervals
            final profBreaks = prof['breaks'];
            if (profBreaks != null && profBreaks is List) {
              profBusy.addAll(AvailabilityUtils.parseFolgasForDate(
                  profBreaks, widget.selectedDate));
            }

            final wsProf = WorkSchedule.fromEmployeeRow(
                Map<String, dynamic>.from(prof));
            final dayCfg = wsProf.forWeekday(widget.selectedDate.weekday);
            if (dayCfg == null) continue;
            final profStartStr = dayCfg.start;
            final profEndStr = dayCfg.end;
            final breakI = dayCfg.breakInterval == null
                ? null
                : {
                    'start': dayCfg.breakInterval!.startMin,
                    'end': dayCfg.breakInterval!.endMin,
                  };

            final profSlots = AvailabilityUtils.generateSmartSlots(
              startStr: profStartStr,
              endStr: profEndStr,
              interval: widget.intervalMinutes,
              serviceDuration: duration,
              busyIntervals: profBusy,
              preventGaps: preventGaps,
              minAdvanceHours: widget.minAdvanceHours,
              selectedDate: widget.selectedDate,
              breakInterval: breakI,
            );

            if (profSlots.isNotEmpty) {
              slots = profSlots;
              _resolvedProfessional = prof;
              debugPrint(
                '✅ [SlotsPage] Profissional escolhido: ${prof['nome'] ?? prof['name']} '
                '(carga=${profLoad[profId]}min) | slots: $slots',
              );
              break; // Mais livre com disponibilidade → escolhido
            }
          }

          if (slots.isEmpty) {
            debugPrint(
                '⚠️ [SlotsPage] Nenhum profissional qualificado tem slot disponível neste dia.');
          }
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
                      DateTime.parse(entry.value['scheduled_at'].toString());
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

class StrikeThroughPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.5)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Linha diagonal inclinada (risquinho)
    canvas.drawLine(
      Offset(size.width * 0.2, size.height * 0.8),
      Offset(size.width * 0.8, size.height * 0.2),
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
