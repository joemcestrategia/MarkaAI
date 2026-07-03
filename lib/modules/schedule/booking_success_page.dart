import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/shared_bottom_nav_bar.dart';
class BookingSuccessPage extends StatelessWidget {
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
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: const SharedBottomNavBar(selectedIndex: 2), // Selecionar aba 2 (Agendamentos) porque acabaram de agendar
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30),
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
                title ?? "Agendamento Confirmado!",
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                subtitle ?? "Seu horário foi reservado com sucesso.\n${isPaid ? 'O pagamento já foi processado.' : 'Realize o pagamento no local.'}",
                style: const TextStyle(fontSize: 16, color: Colors.grey),
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
                    _buildRow(Icons.content_cut, serviceName),
                    const Divider(height: 25),
                    _buildRow(Icons.person, professionalName),
                    const Divider(height: 25),
                    _buildRow(Icons.calendar_today, "$date às $time"),
                  ],
                ),
              ),

              const Spacer(),

              // -- Salvar na Agenda -----------------------------------------
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: _openCalendar,
                  icon: const Icon(Icons.calendar_month_outlined, size: 20),
                  label: const Text('Salvar na Agenda'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryPurple,
                    side: BorderSide(color: AppColors.primaryPurple, width: 1.5),
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
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                    elevation: 5,
                  ),
                  child: const Text("VOLTAR PARA O INÍCIO",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -- Calendar helpers ----------------------------------------------------

  /// Parses "DD/MM/YYYY" + "HH:MM" into a DateTime (UTC for Google Calendar).
  DateTime? _parseDateTime() {
    try {
      final parts = date.split('/');
      final timeParts = time.split(':');
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
    final end = start.add(Duration(minutes: durationMin ?? 60));
    final salon = shopName ?? '';
    final eventTitle = Uri.encodeComponent(
        '$serviceName${salon.isNotEmpty ? ' — $salon' : ''}');
    final details = Uri.encodeComponent(
        'Profissional: $professionalName${salon.isNotEmpty ? '\nSalão: $salon' : ''}');
    final location =
        Uri.encodeComponent(shopAddress ?? salon);
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
        Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.black87)),
      ],
    );
  }
}
