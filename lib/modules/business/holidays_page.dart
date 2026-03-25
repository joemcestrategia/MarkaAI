import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/plan_features_service.dart';
import 'widgets/holiday_decision_modal.dart';
import 'widgets/custom_holiday_modal.dart';
import '../../core/services/brasilapi_service.dart';

class HolidaysPage extends StatefulWidget {
  final String shopId;

  const HolidaysPage({super.key, required this.shopId});

  @override
  State<HolidaysPage> createState() => _HolidaysPageState();
}

class _HolidaysPageState extends State<HolidaysPage> {
  DateTime _focusedDay = DateTime.now();
  List<dynamic> _nationalHolidays = [];
  bool _isLoadingHolidays = false;

  @override
  void initState() {
    super.initState();
    _fetchNationalHolidays();
  }

  Future<void> _fetchNationalHolidays() async {
    if (mounted) setState(() => _isLoadingHolidays = true);
    try {
      final year = _focusedDay.year;
      final response = await BrasilApiService.getHolidays(year);
      if (mounted) {
        setState(() {
          _nationalHolidays = response;
          _isLoadingHolidays = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao buscar feriados: $e");
      if (mounted) setState(() => _isLoadingHolidays = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('shops')
          .stream(primaryKey: ['id'])
          .eq('id', widget.shopId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final shopData = snapshot.data!.first;
        final features = PlanFeaturesService.getFeaturesForShop(shopData);
        
        final List<dynamic> pendentes = shopData['pending_holidays'] ?? [];
        final Map<String, dynamic> configurados = shopData['configured_holidays'] ?? {};
        final List<dynamic> personalizados = shopData['custom_holidays'] ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      floatingActionButton: features.customHolidays
          ? FloatingActionButton(
              onPressed: _showCustomHolidayModal,
              backgroundColor: AppColors.primaryPurple,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: Column(
        children: [
          // Banner de alerta se houver feriados pendentes
          if (pendentes.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.red.shade50,
              child: Row(
                children: [
                   if (_isLoadingHolidays)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                    )
                  else
                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "${pendentes.length} feriados aguardando sua decisÃ£o",
                      style: TextStyle(color: Colors.red.shade800, fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          
          // Novo Banner: Bloqueio AutomÃ¡tico Ativo
          if (shopData['config']?['auto_block_holidays'] ?? false)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              margin: const EdgeInsets.only(bottom: 0),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                border: Border(bottom: BorderSide(color: Colors.blue.shade100)),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Bloqueio AutomÃ¡tico Ativo",
                          style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          "Feriados pendentes sÃ£o bloqueados para agendamento online.",
                          style: TextStyle(color: Colors.blue.shade700, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryPurple.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TableCalendar(
                      // Boundaries fix: Use stable UTC dates to avoid timezone shifts causing assertion failures
                      firstDay: DateTime.utc(2023, 1, 1),
                      lastDay: DateTime.utc(2030, 12, 31),
                      focusedDay: _focusedDay,
                      locale: 'pt_BR',
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      calendarStyle: CalendarStyle(
                        todayDecoration: const BoxDecoration(
                          color: AppColors.primaryPurple,
                          shape: BoxShape.circle,
                        ),
                        weekendTextStyle: const TextStyle(color: Colors.red),
                        holidayTextStyle: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                        holidayDecoration: BoxDecoration(
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                          shape: BoxShape.circle,
                        ),
                      ),
                      holidayPredicate: (day) {
                        final iso = day.toIso8601String().split('T')[0];
                        return _nationalHolidays.any((f) => f['date'] == iso);
                      },
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, date, events) {
                          final iso = date.toIso8601String().split('T')[0];
                          
                          // 1. Pendente
                          if (pendentes.contains(iso)) {
                            final autoBlock = shopData['config']?['auto_block_holidays'] ?? false;
                            if (autoBlock) {
                              return _buildMarker(Colors.grey[700]!, Icons.block);
                            }
                            return _buildMarker(Colors.red, Icons.priority_high);
                          }
                          
                          // 2. Configurado
                          if (configurados.containsKey(iso)) {
                            final decisao = configurados[iso];
                            if (decisao == 'fechado') {
                              return _buildMarker(Colors.grey[700]!, Icons.block);
                            } else if (decisao == 'sem_impacto') {
                              return _buildMarker(Colors.green, Icons.check);
                            } else if (decisao is Map && decisao.containsKey('escala')) {
                              return _buildMarker(Colors.orange, Icons.people);
                            }
                          }
                          
                          // 3. Personalizado (Apenas se nÃ£o houver decisÃ£o)
                          final isCustom = personalizados.any((f) => f['date'] == iso);
                          if (isCustom) {
                            return _buildMarker(Colors.blue, Icons.star);
                          }

                          // 4. Feriado Nacional Sugerido (Marker discreto se ainda nÃ£o configurado)
                          final national = _nationalHolidays.firstWhere((f) => f['date'] == iso, orElse: () => null);
                          if (national != null) {
                             return Positioned(
                               right: 1,
                               bottom: 1,
                               child: Container(
                                 decoration: BoxDecoration(
                                   color: Colors.blue.withValues(alpha: 0.1),
                                   shape: BoxShape.circle,
                                 ),
                                 width: 14,
                                 height: 14,
                                 child: const Icon(Icons.event_note, color: Colors.blue, size: 8),
                               ),
                             );
                          }

                          return null;
                        },
                      ),
                      onDaySelected: (selectedDay, focusedDay) {
                        setState(() {
                          _focusedDay = focusedDay;
                        });
                        final national = _nationalHolidays.firstWhere((f) => f['date'] == selectedDay.toIso8601String().split('T')[0], orElse: () => null);
                        final holidayName = national?['name'] ?? national?['title'];
                        _showDecisionModal(selectedDay, shopData, holidayName: holidayName);
                      },
                      onPageChanged: (focusedDay) {
                        setState(() {
                          _focusedDay = focusedDay;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildMonthlyHolidayList(shopData, pendentes, configurados, personalizados),
                ],
              ),
            ),
          ),
        ],
      ),
    );
      },
    );
  }

  Widget _buildMarker(Color color, IconData icon) {
    return Positioned(
      right: 1,
      bottom: 1,
      child: Container(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        width: 14,
        height: 14,
        child: Icon(icon, color: Colors.white, size: 8),
      ),
    );
  }

  void _showDecisionModal(DateTime date, Map<String, dynamic> shopData, {String? holidayName}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => HolidayDecisionModal(
        shopId: widget.shopId,
        date: date,
        shopData: shopData,
        holidayName: holidayName,
      ),
    );
  }

  Widget _buildMonthlyHolidayList(Map<String, dynamic> shopData, List<dynamic> pendentes, Map<String, dynamic> configurados, List<dynamic> personalizados) {
    // Filtra feriados para o mÃªs atual
    final monthHolidays = _nationalHolidays.where((h) {
      final dt = DateTime.parse(h['date']);
      return dt.month == _focusedDay.month && dt.year == _focusedDay.year;
    }).toList();

    final customMonthHolidays = personalizados.where((h) {
      final dt = DateTime.parse(h['date']);
      return dt.month == _focusedDay.month && dt.year == _focusedDay.year;
    }).toList();

    if (monthHolidays.isEmpty && customMonthHolidays.isEmpty) {
      return const Column(
        children: [
          SizedBox(height: 20),
          Center(
             child: Text("Nenhum feriado neste mÃªs", style: TextStyle(color: Colors.grey)),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.event_available, color: AppColors.primaryPurple, size: 20),
            const SizedBox(width: 8),
            Text(
              "Feriados de ${DateFormat('MMMM', 'pt_BR').format(_focusedDay).capitalize()}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...monthHolidays.map((h) {
          final iso = h['date'];
          final dt = DateTime.parse(iso);
          final isPendente = pendentes.contains(iso);
          final config = configurados[iso];
          
          return _buildHolidayListItem(
            date: dt,
            name: h['name'] ?? h['title'] ?? "Feriado",
            isPendente: isPendente,
            config: config,
            color: Colors.blue,
            shopData: shopData,
          );
        }),
        ...customMonthHolidays.map((h) {
          final iso = h['date'];
          final dt = DateTime.parse(iso);
          
          return _buildHolidayListItem(
            date: dt,
            name: h['name'] ?? "Personalizado",
            isPendente: false,
            config: null,
            color: Colors.amber,
            isCustom: true,
            shopData: shopData,
          );
        }),
      ],
    );
  }

  Future<void> _removeCustomHoliday(String date, String? name) async {
     bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Excluir Data"),
        content: Text("Deseja remover '${name ?? 'esta data'}' das folgas customizadas?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("CANCELAR")),
          TextButton(
            onPressed: () => Navigator.pop(context, true), 
            child: const Text("EXCLUIR", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (mounted) setState(() => _isLoadingHolidays = true);
    try {
      await Supabase.instance.client.functions.invoke(
        'salvarFeriadoPersonalizado',
        body: {
          'shop_id': widget.shopId,
          'date': date,
          'action': 'remove',
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Data removida com sucesso!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao remover: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingHolidays = false);
    }
  }

  Widget _buildHolidayListItem({
    required DateTime date,
    required String name,
    required bool isPendente,
    required dynamic config,
    required Color color,
    required Map<String, dynamic> shopData,
    bool isCustom = false,
  }) {
    String statusText = "Agendamento Normal";
    Color statusColor = Colors.green;
    IconData statusIcon = Icons.check_circle_outline;

    final autoBlock = shopData['config']?['auto_block_holidays'] ?? false;

    if (isPendente) {
      if (autoBlock) {
        statusText = "Fechado";
        statusColor = Colors.grey[700]!;
        statusIcon = Icons.block;
      } else {
        statusText = "Aguardando DecisÃ£o";
        statusColor = Colors.red;
        statusIcon = Icons.priority_high;
      }
    } else if (config != null) {
      if (config == 'fechado') {
        statusText = "Fechado";
        statusColor = Colors.grey[700]!;
        statusIcon = Icons.block;
      } else if (config is Map && config.containsKey('escala')) {
        statusText = "Escala Reduzida";
        statusColor = Colors.orange;
        statusIcon = Icons.people_outline;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: [
                Text(
                  date.day.toString(),
                  style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16),
                ),
                Text(
                  DateFormat('E', 'pt_BR').format(date).toUpperCase(),
                  style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(statusIcon, color: statusColor, size: 12),
                    const SizedBox(width: 4),
                    Text(statusText, style: TextStyle(color: statusColor, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          if (isCustom)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              onPressed: _isLoadingHolidays ? null : () => _removeCustomHoliday(date.toIso8601String().split('T')[0], name),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 18, color: Colors.grey),
            onPressed: () => _showDecisionModal(date, shopData, holidayName: name), 
          ),
        ],
      ),
    );
  }

  void _showCustomHolidayModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomHolidayModal(shopId: widget.shopId),
    );
  }
}
