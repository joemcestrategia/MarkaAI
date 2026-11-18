import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_bottom_nav_bar.dart';
import '../clients/client_home_page.dart';
import 'widgets/booking_message_modal.dart';

class BookingSuccessPage extends StatefulWidget {
  final String serviceName;
  final String date;
  final String time;
  final String professionalName;
  final bool isPaid;
  final String? title;
  final String? subtitle;
  final String? shopName;
  final String? shopAddress;
  final int? durationMin;

  /// Quando informados (junto com [shopId]), abre automaticamente a modal
  /// opcional de mensagem sobre esta tela de confirmação.
  final String? appointmentId;
  final String? shopId;

  /// Fluxo de subdomínio: em vez de "Voltar para o início", leva o cliente
  /// direto para a aba "Meus Agendamentos".
  final bool goToMyAppointments;

  const BookingSuccessPage({
    super.key,
    required this.serviceName,
    required this.date,
    required this.time,
    required this.professionalName,
    required this.isPaid,
    this.title,
    this.subtitle,
    this.shopName,
    this.shopAddress,
    this.durationMin,
    this.appointmentId,
    this.shopId,
    this.goToMyAppointments = false,
  });

  @override
  State<BookingSuccessPage> createState() => _BookingSuccessPageState();
}

class _BookingSuccessPageState extends State<BookingSuccessPage> {
  bool _modalShown = false;

  @override
  void initState() {
    super.initState();
    _scheduleMessageModal();
  }

  void _scheduleMessageModal() {
    final apptId = widget.appointmentId;
    final sId = widget.shopId;
    if (apptId == null || apptId.isEmpty || sId == null || sId.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 450));
      if (!mounted || _modalShown) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      _modalShown = true;

      final sent = await BookingMessageModal.show(
        context,
        appointmentId: apptId,
        shopId: sId,
        shopName: widget.shopName,
      );

      if (sent == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Expanded(child: Text('Mensagem enviada com sucesso!')),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: SharedBottomNavBar(
        selectedIndex: 2,
        onDestinationSelected: (idx) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => ClientHomePage(initialTabIndex: idx),
            ),
            (r) => false,
          );
        },
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 60,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Animação de Sucesso (Ícone Pulsante)
                      TweenAnimationBuilder(
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.elasticOut,
                        builder: (context, double value, child) {
                          return Transform.scale(
                            scale: value,
                            child: Container(
                              padding: const EdgeInsets.all(25),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check_circle,
                                  size: 80, color: Colors.green),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 30),
                      Text(
                        widget.title ?? "Agendamento Confirmado!",
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.subtitle ??
                            "Seu horário foi reservado com sucesso.\n${widget.isPaid ? 'O pagamento já foi processado.' : 'Realize o pagamento no local.'}",
                        style:
                            const TextStyle(fontSize: 16, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),

                      // Cartão de Resumo (Ticket)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FD),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            _buildRow(Icons.content_cut, widget.serviceName),
                            const Divider(height: 25),
                            _buildRow(Icons.person, widget.professionalName),
                            const Divider(height: 25),
                            _buildRow(Icons.calendar_today,
                                "${widget.date} às ${widget.time}"),
                          ],
                        ),
                      ),

                      const Spacer(),
                      const SizedBox(height: 24),

                      // -- Salvar na Agenda -----------------------------------
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: _openCalendar,
                          icon: const Icon(Icons.calendar_month_outlined,
                              size: 20),
                          label: const Text('Salvar na Agenda'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryPurple,
                            side: const BorderSide(
                                color: AppColors.primaryPurple, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                            textStyle: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton(
                          onPressed: () {
                            if (widget.goToMyAppointments) {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                    builder: (_) => const ClientHomePage(
                                        initialTabIndex: 2)),
                                (_) => false,
                              );
                            } else {
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryPurple,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15)),
                            elevation: 5,
                          ),
                          child: Text(
                              widget.goToMyAppointments
                                  ? "VER MEUS AGENDAMENTOS"
                                  : "VOLTAR PARA O INÍCIO",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // -- Calendar helpers ----------------------------------------------------

  /// Parses "DD/MM/YYYY" + "HH:MM" into a DateTime (UTC for Google Calendar).
  DateTime? _parseDateTime() {
    try {
      final parts = widget.date.split('/');
      final timeParts = widget.time.split(':');
      if (parts.length != 3 || timeParts.length != 2) return null;
      return DateTime(
        int.parse(parts[2]),
        int.parse(parts[1]),
        int.parse(parts[0]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
      );
    } catch (_) {
      return null;
    }
  }

  String _gcalDate(DateTime dt) {
    String p(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}${p(dt.month)}${p(dt.day)}T${p(dt.hour)}${p(dt.minute)}00';
  }

  void _openCalendar() {
    final start = _parseDateTime();
    if (start == null) return;
    final end = start.add(Duration(minutes: widget.durationMin ?? 60));
    final salon = widget.shopName ?? '';
    final eventTitle = Uri.encodeComponent(
        '${widget.serviceName}${salon.isNotEmpty ? ' — $salon' : ''}');
    final details = Uri.encodeComponent(
        'Profissional: ${widget.professionalName}${salon.isNotEmpty ? '\nSalão: $salon' : ''}');
    final location = Uri.encodeComponent(widget.shopAddress ?? salon);
    final dates = '${_gcalDate(start)}/${_gcalDate(end)}';
    final url =
        'https://calendar.google.com/calendar/render?action=TEMPLATE'
        '&text=$eventTitle'
        '&dates=$dates'
        '&details=$details'
        '&location=$location';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Widget _buildRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primaryPurple, size: 20),
        const SizedBox(width: 15),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black87)),
        ),
      ],
    );
  }
}
